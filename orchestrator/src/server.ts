import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { Agent } from "@cursor/sdk";

const port = Number(process.env.PORT ?? 8787);

type CloudRunRequest = {
  prompt?: string;
  images?: Array<{
    data?: string;
    mimeType?: string;
    dimension?: {
      width: number;
      height: number;
    };
  }>;
  repositoryUrl?: string;
  startingRef?: string;
  prUrl?: string;
  modelId?: string;
  autoCreatePR?: boolean;
  skipReviewerRequest?: boolean;
  mcpServers?: unknown;
  agents?: unknown;
};

type RouteParams = {
  agentId: string;
  runId: string;
};

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`);

    if (request.method === "GET" && url.pathname === "/health") {
      sendJSON(response, 200, {
        ok: true,
        service: "runline-orchestrator",
        sdk: "@cursor/sdk",
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/runs/cloud") {
      await createCloudRun(request, response);
      return;
    }

    const runParams = matchRunRoute(url.pathname);
    if (request.method === "GET" && runParams && url.pathname.endsWith("/state")) {
      await getRunState(request, response, runParams);
      return;
    }

    if (request.method === "GET" && runParams && url.pathname.endsWith("/events")) {
      await streamRunEvents(request, response, runParams);
      return;
    }

    sendJSON(response, 404, { error: "not_found" });
  } catch (error) {
    sendError(response, error);
  }
});

server.listen(port, () => {
  console.log(`Runline orchestrator listening on http://localhost:${port}`);
});

async function createCloudRun(request: IncomingMessage, response: ServerResponse) {
  const body = await readJSON<CloudRunRequest>(request);
  const apiKey = apiKeyFrom(request);
  if (!apiKey) {
    sendJSON(response, 401, { error: "missing_cursor_api_key" });
    return;
  }

  if (!body.prompt?.trim()) {
    sendJSON(response, 400, { error: "prompt_required" });
    return;
  }
  const promptText = body.prompt.trim();

  if (!body.repositoryUrl && !body.prUrl) {
    sendJSON(response, 400, { error: "repository_or_pr_required" });
    return;
  }

  const repo = body.prUrl
    ? { prUrl: body.prUrl }
    : { url: body.repositoryUrl!, startingRef: emptyToUndefined(body.startingRef) };

  // This spike keeps SDK-only shapes opaque until the backend API is hardened.
  const createOptions: any = {
    apiKey,
    cloud: {
      repos: [repo],
      autoCreatePR: body.autoCreatePR ?? false,
      skipReviewerRequest: body.skipReviewerRequest ?? false,
    },
  };

  if (body.modelId) {
    createOptions.model = { id: body.modelId };
  }
  if (body.mcpServers) {
    createOptions.mcpServers = body.mcpServers;
  }
  if (body.agents) {
    createOptions.agents = body.agents;
  }

  const agent = await Agent.create(createOptions);
  const prompt = body.images?.length
    ? {
        text: promptText,
        images: body.images
          .filter((image) => image.data?.trim())
          .map((image) => ({
            data: image.data!,
            mimeType: image.mimeType ?? "image/jpeg",
            dimension: image.dimension,
          })),
      }
    : promptText;

  const run = await agent.send(prompt);

  sendJSON(response, 202, {
    agentId: agent.agentId,
    runId: run.id,
    status: run.status,
    eventsURL: `/agents/${agent.agentId}/runs/${run.id}/events`,
    stateURL: `/agents/${agent.agentId}/runs/${run.id}/state`,
  });
}

async function getRunState(request: IncomingMessage, response: ServerResponse, params: RouteParams) {
  const apiKey = apiKeyFrom(request);
  if (!apiKey) {
    sendJSON(response, 401, { error: "missing_cursor_api_key" });
    return;
  }

  const run = await Agent.getRun(params.runId, {
    runtime: "cloud",
    agentId: params.agentId,
    apiKey,
  });

  sendJSON(response, 200, {
    agentId: run.agentId,
    runId: run.id,
    status: run.status,
    result: run.result,
    durationMs: run.durationMs,
    git: run.git,
  });
}

async function streamRunEvents(request: IncomingMessage, response: ServerResponse, params: RouteParams) {
  const apiKey = apiKeyFrom(request);
  if (!apiKey) {
    sendJSON(response, 401, { error: "missing_cursor_api_key" });
    return;
  }

  const run = await Agent.getRun(params.runId, {
    runtime: "cloud",
    agentId: params.agentId,
    apiKey,
  });

  response.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache, no-transform",
    Connection: "keep-alive",
  });

  try {
    for await (const event of run.stream()) {
      response.write(`event: ${event.type}\n`);
      response.write(`data: ${JSON.stringify(event)}\n\n`);
    }
    response.write("event: done\n");
    response.write("data: {}\n\n");
    response.end();
  } catch (error) {
    response.write("event: error\n");
    response.write(`data: ${JSON.stringify(errorPayload(error))}\n\n`);
    response.end();
  }
}

function matchRunRoute(pathname: string): RouteParams | undefined {
  const match = pathname.match(/^\/agents\/([^/]+)\/runs\/([^/]+)\/(?:state|events)$/);
  if (!match) {
    return undefined;
  }
  return {
    agentId: decodeURIComponent(match[1]!),
    runId: decodeURIComponent(match[2]!),
  };
}

async function readJSON<T>(request: IncomingMessage): Promise<T> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  return raw ? JSON.parse(raw) as T : {} as T;
}

function apiKeyFrom(request: IncomingMessage): string | undefined {
  const authorization = request.headers.authorization;
  if (authorization?.toLowerCase().startsWith("bearer ")) {
    return authorization.slice("bearer ".length).trim();
  }
  return emptyToUndefined(process.env.CURSOR_API_KEY);
}

function emptyToUndefined(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function sendJSON(response: ServerResponse, statusCode: number, body: unknown) {
  response.writeHead(statusCode, { "Content-Type": "application/json" });
  response.end(JSON.stringify(body));
}

function sendError(response: ServerResponse, error: unknown) {
  const payload = errorPayload(error);
  sendJSON(response, payload.statusCode, payload);
}

function errorPayload(error: unknown) {
  const message = error instanceof Error ? error.message : "Unknown error";
  return {
    statusCode: 500,
    error: "orchestrator_error",
    message,
  };
}
