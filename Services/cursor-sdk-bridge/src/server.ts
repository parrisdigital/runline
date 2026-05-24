import Fastify, { type FastifyReply, type FastifyRequest } from "fastify";
import { ZodError } from "zod";
import { cursorAPIKey, publicAuthState, requireBridgeSecret } from "./auth.js";
import {
  cancelSDKRun,
  createSDKSession,
  listCursorModels,
  listCursorRepositories,
  listSDKArtifacts,
  sendSDKSessionMessage,
  validateCursorConnection,
} from "./cursorSdk.js";
import { encodeSSE, EventHub } from "./events.js";
import { cancelRunSchema, sessionCreateSchema, sessionMessageSchema } from "./schemas.js";
import { createSessionStore } from "./sessionStore.js";

const serviceName = "runline-sdk-bridge";
const serviceVersion = "0.1.0";
const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? "0.0.0.0";

const sessions = createSessionStore();
const events = new EventHub();

export const logRedactionPaths = [
  "req.headers.authorization",
  "req.headers.x-cursor-api-key",
  "req.headers.x-runline-bridge-secret",
  "headers.authorization",
  "headers.x-cursor-api-key",
  "headers.x-runline-bridge-secret",
];

export function buildServer() {
  const app = Fastify({
    logger: {
      level: process.env.LOG_LEVEL ?? "info",
      redact: {
        paths: logRedactionPaths,
        censor: "[redacted]",
      },
    },
    bodyLimit: 16 * 1024 * 1024,
  });

  const context = { sessions, events, logger: app.log };

  app.setErrorHandler((error, _request, reply) => {
    const statusCode = statusCodeFor(error);
    const payload = errorPayload(error);
    if (statusCode >= 500) {
      app.log.error({ error: payload.error, statusCode }, "Request failed");
    }
    reply.status(statusCode).send(payload);
  });

  app.get("/health", async (request) => ({
    ok: true,
    service: serviceName,
    version: serviceVersion,
    runtime: "node",
    auth: publicAuthState(request),
    sessionStore: {
      kind: sessions.kind,
      persistent: sessions.isPersistent,
    },
  }));

  app.get("/v1/capabilities", async (request) => {
    requireBridgeSecret(request);
    return {
      service: serviceName,
      version: serviceVersion,
      runtime: "cursor-sdk-cloud",
      transport: ["https", "sse"],
      supports: {
        createSession: true,
        followUps: true,
        runStreaming: true,
        cancel: true,
        artifacts: true,
        cursorKeyPersistence: false,
        persistentSessions: sessions.isPersistent,
      },
    };
  });

  app.get("/v1/me", async (request) => {
    requireBridgeSecret(request);
    return validateCursorConnection(cursorAPIKey(request));
  });

  app.get("/v1/models", async (request) => {
    requireBridgeSecret(request);
    return { items: await listCursorModels(cursorAPIKey(request)) };
  });

  app.get("/v1/repositories", async (request) => {
    requireBridgeSecret(request);
    return { items: await listCursorRepositories(cursorAPIKey(request)) };
  });

  app.post("/v1/sessions", async (request) => {
    requireBridgeSecret(request);
    const input = sessionCreateSchema.parse(request.body);
    const result = await createSDKSession(cursorAPIKey(request), input, context);
    return sessionResponse(result.session.sessionId, result.run.runId);
  });

  app.get("/v1/sessions", async (request) => {
    requireBridgeSecret(request);
    return { items: sessions.listSessions() };
  });

  app.get("/v1/sessions/:sessionId", async (request) => {
    requireBridgeSecret(request);
    const { sessionId } = request.params as { sessionId: string };
    const session = sessions.requireSession(sessionId);
    return {
      session,
      latestRun: session.latestRunId ? session.runs.find((run) => run.runId === session.latestRunId) : undefined,
    };
  });

  app.post("/v1/sessions/:sessionId/messages", async (request) => {
    requireBridgeSecret(request);
    const { sessionId } = request.params as { sessionId: string };
    const input = sessionMessageSchema.parse(request.body);
    const result = await sendSDKSessionMessage(cursorAPIKey(request), sessionId, input, context);
    return sessionResponse(result.session.sessionId, result.run.runId);
  });

  app.post("/v1/sessions/:sessionId/cancel", async (request) => {
    requireBridgeSecret(request);
    const { sessionId } = request.params as { sessionId: string };
    const input = cancelRunSchema.parse(request.body ?? {});
    const runID = input.runId ?? sessions.latestRun(sessionId)?.runId;
    if (!runID) {
      return replyRunNotFound();
    }
    return cancelSDKRun(cursorAPIKey(request), sessionId, runID, context);
  });

  app.get("/v1/sessions/:sessionId/events", async (request, reply) => {
    requireBridgeSecret(request);
    const { sessionId } = request.params as { sessionId: string };
    const session = sessions.requireSession(sessionId);
    const query = request.query as { runId?: string; after?: string };
    const runID = query.runId ?? session.latestRunId;
    if (!runID) {
      return replyRunNotFound(reply);
    }
    return streamEvents(request, reply, runID, query.after);
  });

  app.get("/v1/sessions/:sessionId/runs/:runId/events", async (request, reply) => {
    requireBridgeSecret(request);
    const { sessionId, runId } = request.params as { sessionId: string; runId: string };
    sessions.requireSession(sessionId);
    const query = request.query as { after?: string };
    return streamEvents(request, reply, runId, query.after);
  });

  app.get("/v1/debug/sessions/:sessionId/event-shapes", async (request) => {
    requireBridgeSecret(request);
    const { sessionId } = request.params as { sessionId: string };
    const session = sessions.requireSession(sessionId);
    const query = request.query as { runId?: string; limit?: string };
    const runID = query.runId ?? session.latestRunId;
    if (!runID) {
      return replyRunNotFound();
    }
    return { items: events.shapeSnapshot(runID, shapeLimit(query.limit)) };
  });

  app.get("/v1/debug/sessions/:sessionId/runs/:runId/event-shapes", async (request) => {
    requireBridgeSecret(request);
    const { sessionId, runId } = request.params as { sessionId: string; runId: string };
    sessions.requireSession(sessionId);
    const query = request.query as { limit?: string };
    return { items: events.shapeSnapshot(runId, shapeLimit(query.limit)) };
  });

  app.get("/v1/sessions/:sessionId/artifacts", async (request) => {
    requireBridgeSecret(request);
    const { sessionId } = request.params as { sessionId: string };
    return { items: await listSDKArtifacts(cursorAPIKey(request), sessionId, context) };
  });

  return app;
}

function sessionResponse(sessionID: string, runID: string) {
  return {
    sessionId: sessionID,
    agentId: sessionID,
    runId: runID,
    status: "running",
    eventsURL: `/v1/sessions/${encodeURIComponent(sessionID)}/events?runId=${encodeURIComponent(runID)}`,
    runEventsURL: `/v1/sessions/${encodeURIComponent(sessionID)}/runs/${encodeURIComponent(runID)}/events`,
    stateURL: `/v1/sessions/${encodeURIComponent(sessionID)}`,
  };
}

function streamEvents(
  request: FastifyRequest,
  reply: FastifyReply,
  runID: string,
  afterID?: string
): Promise<void> {
  reply.raw.writeHead(200, {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-cache, no-transform",
    Connection: "keep-alive",
    "X-Accel-Buffering": "no",
  });

  for (const event of events.snapshot(runID, afterID ?? request.headers["last-event-id"] as string | undefined)) {
    reply.raw.write(encodeSSE(event));
  }

  const unsubscribe = events.subscribe(runID, (event) => {
    reply.raw.write(encodeSSE(event));
  });

  const heartbeat = setInterval(() => {
    reply.raw.write(": heartbeat\n\n");
  }, 20_000);

  request.raw.on("close", () => {
    clearInterval(heartbeat);
    unsubscribe();
  });

  return new Promise(() => {
    // Keep the SSE response open until the client disconnects.
  });
}

function replyRunNotFound(reply?: FastifyReply) {
  const payload = {
    error: "run_not_found",
    message: "No run is available for this session.",
  };
  if (reply) {
    return reply.status(404).send(payload);
  }
  const error = new Error(payload.message);
  Object.assign(error, { statusCode: 404, code: payload.error });
  throw error;
}

function shapeLimit(value: string | undefined): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return 200;
  }
  return Math.min(200, Math.max(1, Math.trunc(parsed)));
}

function statusCodeFor(error: unknown): number {
  if (error instanceof ZodError) {
    return 400;
  }
  return classifiedError(error).statusCode;
}

function errorPayload(error: unknown) {
  if (error instanceof ZodError) {
    return {
      error: "invalid_request",
      message: "Request body did not match the bridge API contract.",
      issues: error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    };
  }
  const classified = classifiedError(error);
  return { error: classified.code, message: classified.message };
}

export function classifiedError(error: unknown): { code: string; message: string; statusCode: number } {
  const statusCode = typeof error === "object" && error && "statusCode" in error && typeof error.statusCode === "number"
    ? error.statusCode
    : undefined;
  const rawCode = typeof error === "object" && error && "code" in error && typeof error.code === "string"
    ? error.code
    : undefined;
  const rawMessage = error instanceof Error ? error.message : "";

  if (rawCode === "usage_limit_exceeded" || /\[usage_limit_exceeded\]/i.test(rawMessage)) {
    return {
      code: "usage_limit_exceeded",
      message: "Your Cursor account has reached its hard usage limit. Increase the hard limit in Cursor settings, then try again.",
      statusCode: 429,
    };
  }

  if (statusCode && statusCode < 500) {
    return {
      code: rawCode ?? "request_failed",
      message: rawMessage || "Request failed.",
      statusCode,
    };
  }

  return {
    code: rawCode ?? "request_failed",
    message: "Cursor SDK request failed.",
    statusCode: statusCode ?? 500,
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = buildServer();
  await server.listen({ port, host });
}
