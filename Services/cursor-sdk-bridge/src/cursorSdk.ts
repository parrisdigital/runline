import { Agent, Cursor, type AgentOptions, type McpServerConfig, type Run, type SDKAgent, type SDKImage, type SDKMessage, type SDKUserMessage, type SendOptions } from "@cursor/sdk";
import type { FastifyBaseLogger } from "fastify";
import { conversationTitle } from "./conversationTitle.js";
import { EventHub } from "./events.js";
import type { SessionCreateInput, SessionMessageInput } from "./schemas.js";
import type { BridgeRunState, BridgeSession, SessionStore } from "./sessionStore.js";

type PromptTextInput = {
  prompt: string;
  repo?: SessionCreateInput["repo"];
  repositoryUrl?: string;
  startingRef?: string;
  prUrl?: string;
};

type UserMessageInput = PromptTextInput & {
  images?: SessionCreateInput["images"];
};

export type BridgeContext = {
  sessions: SessionStore;
  events: EventHub;
  logger: FastifyBaseLogger;
};

export async function validateCursorConnection(apiKey: string) {
  return Cursor.me({ apiKey });
}

export async function listCursorModels(apiKey: string) {
  return Cursor.models.list({ apiKey });
}

export async function listCursorRepositories(apiKey: string) {
  return Cursor.repositories.list({ apiKey });
}

export async function createSDKSession(
  apiKey: string,
  input: SessionCreateInput,
  context: BridgeContext
): Promise<{ session: BridgeSession; run: BridgeRunState }> {
  const agent = await Agent.create(agentOptions(apiKey, input));
  const run = await agent.send(userMessage(input), sendOptions(input));
  const now = new Date().toISOString();
  const repo = normalizedRepo(input);
  const session: BridgeSession = {
    sessionId: agent.agentId,
    agentId: agent.agentId,
    name: conversationTitle(input.prompt),
    repositoryUrl: repo?.url,
    startingRef: repo?.startingRef,
    prUrl: repo?.prUrl,
    modelId: normalizedModelID(input.modelId),
    autoCreatePR: input.autoCreatePR,
    latestRunId: run.id,
    runs: [],
    createdAt: now,
    updatedAt: now,
  };
  context.sessions.upsertSession(session);
  const runState = bridgeRunState(agent.agentId, run);
  context.sessions.appendRun(session.sessionId, runState);
  collectRun(session.sessionId, run, context);
  return { session: context.sessions.requireSession(session.sessionId), run: runState };
}

export async function sendSDKSessionMessage(
  apiKey: string,
  sessionID: string,
  input: SessionMessageInput,
  context: BridgeContext
): Promise<{ session: BridgeSession; run: BridgeRunState }> {
  const session = context.sessions.requireSession(sessionID);
  if (!session.name) {
    context.sessions.upsertSession({
      ...session,
      name: conversationTitle(input.prompt),
      updatedAt: new Date().toISOString(),
    });
  }
  const agent = await Agent.resume(session.agentId, { apiKey });
  const run = await agent.send(userMessage(userMessageInput(input, session)), sendOptions(input));
  const runState = bridgeRunState(agent.agentId, run);
  const updatedSession = context.sessions.appendRun(sessionID, runState);
  collectRun(sessionID, run, context);
  return { session: updatedSession, run: runState };
}

export async function cancelSDKRun(
  apiKey: string,
  sessionID: string,
  runID: string,
  context: BridgeContext
): Promise<BridgeRunState> {
  const session = context.sessions.requireSession(sessionID);
  await Agent.cancelRun(runID, {
    runtime: "cloud",
    agentId: session.agentId,
    apiKey,
  });
  context.events.append(runID, "status", {
    type: "status",
    agent_id: session.agentId,
    run_id: runID,
    status: "CANCELLED",
    message: "Run cancelled.",
  });
  return context.sessions.updateRun(sessionID, runID, { status: "cancelled" });
}

export async function listSDKArtifacts(apiKey: string, sessionID: string, context: BridgeContext) {
  const session = context.sessions.requireSession(sessionID);
  const agent = await Agent.resume(session.agentId, { apiKey });
  return agent.listArtifacts();
}

export async function downloadSDKArtifact(
  apiKey: string,
  sessionID: string,
  path: string,
  context: BridgeContext
): Promise<Buffer> {
  const session = context.sessions.requireSession(sessionID);
  const agent = await Agent.resume(session.agentId, { apiKey });
  return agent.downloadArtifact(path);
}

function collectRun(sessionID: string, run: Run, context: BridgeContext) {
  void (async () => {
    context.events.append(run.id, "status", {
      type: "status",
      agent_id: run.agentId,
      run_id: run.id,
      status: "RUNNING",
      message: "Run started.",
    });

    try {
      if (run.supports("stream")) {
        for await (const message of run.stream()) {
          context.events.append(run.id, message.type, message);
        }
      }

      const result = await run.wait();
      const terminalStatus = result.status === "finished" ? "finished" : result.status;
      context.sessions.updateRun(sessionID, run.id, {
        status: terminalStatus,
        result: result.result,
        durationMs: result.durationMs,
        git: result.git,
      });
      context.events.append(run.id, "result", {
        type: "result",
        agent_id: run.agentId,
        run_id: run.id,
        status: result.status,
        result: result.result,
        durationMs: result.durationMs,
        git: result.git,
      });
      context.events.append(run.id, "done", {
        type: "done",
        agent_id: run.agentId,
        run_id: run.id,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown Cursor SDK error.";
      context.sessions.updateRun(sessionID, run.id, { status: "error", result: message });
      context.events.append(run.id, "error", {
        type: "error",
        agent_id: run.agentId,
        run_id: run.id,
        message,
      });
      context.events.append(run.id, "done", {
        type: "done",
        agent_id: run.agentId,
        run_id: run.id,
      });
      context.logger.warn({ err: redactError(error), runId: run.id }, "Cursor SDK run failed");
    }
  })();
}

function agentOptions(apiKey: string, input: SessionCreateInput): AgentOptions {
  const repo = normalizedRepo(input);
  const options: AgentOptions = {
    apiKey,
    idempotencyKey: input.idempotencyKey,
    cloud: {
      repos: repo ? [repo] : undefined,
      autoCreatePR: input.autoCreatePR,
      skipReviewerRequest: input.skipReviewerRequest,
      workOnCurrentBranch: input.workOnCurrentBranch,
    },
    mcpServers: input.mcpServers as Record<string, McpServerConfig> | undefined,
    agents: input.agents as AgentOptions["agents"],
  };

  const modelID = normalizedModelID(input.modelId);
  if (modelID) {
    options.model = { id: modelID };
  }
  return options;
}

function sendOptions(input: SessionMessageInput): SendOptions {
  const options: SendOptions = {
    idempotencyKey: input.idempotencyKey,
    mcpServers: input.mcpServers as Record<string, McpServerConfig> | undefined,
  };
  const modelID = normalizedModelID(input.modelId);
  if (modelID) {
    options.model = { id: modelID };
  }
  return options;
}

function userMessage(input: UserMessageInput): string | SDKUserMessage {
  const text = promptText(input);
  if (!input.images?.length) {
    return text;
  }
  return {
    text,
    images: input.images.map((image): SDKImage => ({
      data: image.data,
      mimeType: image.mimeType,
      dimension: image.dimension,
    })),
  };
}

function userMessageInput(input: SessionMessageInput, session: BridgeSession): UserMessageInput {
  return {
    ...input,
    repositoryUrl: session.repositoryUrl,
    startingRef: session.startingRef,
    prUrl: session.prUrl,
  };
}

export function promptText(input: PromptTextInput): string {
  if (normalizedRepo(input)) {
    return input.prompt;
  }

  return [
    "You are in Runline General Chat, a repo-less Cursor Chat conversation.",
    "Answer conversationally and directly. Do not inspect the workspace, search files, run terminal commands, or create files unless the user explicitly asks to create or inspect a repository-backed workspace.",
    "",
    "User message:",
    input.prompt,
  ].join("\n");
}

function bridgeRunState(agentId: string, run: Run): BridgeRunState {
  return {
    runId: run.id,
    agentId,
    status: run.status,
    createdAt: new Date(run.createdAt ?? Date.now()).toISOString(),
    updatedAt: new Date().toISOString(),
    result: run.result,
    durationMs: run.durationMs,
    git: run.git,
  };
}

function normalizedRepo(input: PromptTextInput): { url: string; startingRef?: string; prUrl?: string } | undefined {
  if (input.repo) {
    return input.repo;
  }
  if (input.repositoryUrl) {
    return {
      url: input.repositoryUrl,
      startingRef: input.startingRef,
      prUrl: input.prUrl,
    };
  }
  return undefined;
}

function normalizedModelID(modelID: string | undefined): string | undefined {
  const trimmed = modelID?.trim();
  if (!trimmed || trimmed.toLowerCase() === "default") {
    return undefined;
  }
  return trimmed;
}

function redactError(error: unknown) {
  if (!(error instanceof Error)) {
    return { name: "UnknownError" };
  }
  return {
    name: error.name,
    stack: process.env.NODE_ENV === "production" ? undefined : error.stack,
  };
}
