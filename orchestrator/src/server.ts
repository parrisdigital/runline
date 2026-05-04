import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { Agent, type McpServerConfig } from "@cursor/sdk";

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
  intent?: "continue" | "plan" | "execute";
  repositoryUrl?: string;
  startingRef?: string;
  prUrl?: string;
  modelId?: string;
  mcpProfileId?: string;
  autoCreatePR?: boolean;
  skipReviewerRequest?: boolean;
  mcpServers?: Record<string, McpServerConfig>;
  agents?: unknown;
};

type RouteParams = {
  agentId: string;
  runId: string;
};

type SessionRouteParams = {
  sessionId: string;
  runId?: string;
};

type SDKMCPProfile = {
  id: string;
  name: string;
  description?: string;
  mcpServers?: Record<string, McpServerConfig>;
  agents?: unknown;
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

    if (request.method === "GET" && url.pathname === "/sdk/mcp-profiles") {
      sendJSON(response, 200, { profiles: publicMCPProfiles() });
      return;
    }

    if (request.method === "POST" && url.pathname === "/sdk/sessions") {
      await createSDKSession(request, response);
      return;
    }

    const sessionParams = matchSessionRoute(url.pathname);
    if (sessionParams && request.method === "POST" && url.pathname.endsWith("/messages")) {
      await sendSDKSessionMessage(request, response, sessionParams);
      return;
    }

    if (sessionParams && request.method === "GET" && url.pathname.endsWith("/state")) {
      await getSDKSessionState(request, response, sessionParams, url);
      return;
    }

    if (sessionParams && request.method === "GET" && sessionParams.runId && url.pathname.endsWith("/events")) {
      await streamRunEvents(request, response, {
        agentId: sessionParams.sessionId,
        runId: sessionParams.runId,
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/runs/cloud") {
      await createSDKSession(request, response);
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

async function createSDKSession(request: IncomingMessage, response: ServerResponse) {
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

  const agent = await Agent.create(createOptionsFor(apiKey, body));
  const run = await agent.send(promptFor(promptText, body));

  sendJSON(response, 202, {
    sessionId: agent.agentId,
    agentId: agent.agentId,
    runId: run.id,
    status: run.status,
    mode: "sdk-agent",
    mcpProfile: selectedProfileMetadata(body.mcpProfileId),
    eventsURL: `/agents/${agent.agentId}/runs/${run.id}/events`,
    sessionEventsURL: `/sdk/sessions/${agent.agentId}/runs/${run.id}/events`,
    stateURL: `/agents/${agent.agentId}/runs/${run.id}/state`,
    sessionStateURL: `/sdk/sessions/${agent.agentId}/state?runId=${run.id}`,
  });
}

async function sendSDKSessionMessage(request: IncomingMessage, response: ServerResponse, params: SessionRouteParams) {
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

  const agent = await Agent.resume(params.sessionId, { apiKey });
  const run = await agent.send(promptFor(body.prompt.trim(), body), sendOptionsFor(body));

  sendJSON(response, 202, {
    sessionId: params.sessionId,
    agentId: agent.agentId,
    runId: run.id,
    status: run.status,
    mode: "sdk-agent",
    mcpProfile: selectedProfileMetadata(body.mcpProfileId),
    eventsURL: `/agents/${agent.agentId}/runs/${run.id}/events`,
    sessionEventsURL: `/sdk/sessions/${params.sessionId}/runs/${run.id}/events`,
    stateURL: `/agents/${agent.agentId}/runs/${run.id}/state`,
    sessionStateURL: `/sdk/sessions/${params.sessionId}/state?runId=${run.id}`,
  });
}

async function getSDKSessionState(
  request: IncomingMessage,
  response: ServerResponse,
  params: SessionRouteParams,
  url: URL
) {
  const apiKey = apiKeyFrom(request);
  if (!apiKey) {
    sendJSON(response, 401, { error: "missing_cursor_api_key" });
    return;
  }

  const runId = emptyToUndefined(url.searchParams.get("runId") ?? undefined);
  if (runId) {
    const run = await Agent.getRun(runId, {
      runtime: "cloud",
      agentId: params.sessionId,
      apiKey,
    });
    sendJSON(response, 200, {
      sessionId: params.sessionId,
      latestRun: publicRun(run),
    });
    return;
  }

  const runs = await Agent.listRuns(params.sessionId, {
    runtime: "cloud",
    apiKey,
    limit: 1,
  });

  sendJSON(response, 200, {
    sessionId: params.sessionId,
    latestRun: runs.items[0] ? publicRun(runs.items[0]) : undefined,
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

function createOptionsFor(apiKey: string, body: CloudRunRequest) {
  const repo = body.prUrl
    ? { prUrl: body.prUrl }
    : { url: body.repositoryUrl!, startingRef: emptyToUndefined(body.startingRef) };
  const profile = mcpProfile(body.mcpProfileId);

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
  if (body.mcpServers ?? profile?.mcpServers) {
    createOptions.mcpServers = body.mcpServers ?? profile?.mcpServers;
  }
  if (body.agents ?? profile?.agents) {
    createOptions.agents = body.agents ?? profile?.agents;
  }
  return createOptions;
}

function sendOptionsFor(body: CloudRunRequest) {
  const profile = mcpProfile(body.mcpProfileId);
  const options: any = {};
  if (body.modelId) {
    options.model = { id: body.modelId };
  }
  if (body.mcpServers ?? profile?.mcpServers) {
    options.mcpServers = body.mcpServers ?? profile?.mcpServers;
  }
  return Object.keys(options).length ? options : undefined;
}

function promptFor(promptText: string, body: CloudRunRequest) {
  const text = promptedIntentText(promptText, body.intent);
  return body.images?.length
    ? {
        text,
        images: body.images
          .filter((image) => image.data?.trim())
          .map((image) => ({
            data: image.data!,
            mimeType: image.mimeType ?? "image/jpeg",
            dimension: image.dimension,
          })),
      }
    : text;
}

function promptedIntentText(promptText: string, intent: CloudRunRequest["intent"]) {
  switch (intent) {
    case "plan":
      return [
        "Create a concise implementation plan first. Do not modify files or execute changes until the user explicitly asks you to execute.",
        "",
        promptText,
      ].join("\n");
    case "execute":
      return [
        "Execute the requested implementation. Keep the work scoped, run relevant checks, and summarize the concrete result.",
        "",
        promptText,
      ].join("\n");
    default:
      return promptText;
  }
}

function publicRun(run: any) {
  return {
    agentId: run.agentId,
    runId: run.id,
    status: run.status,
    result: run.result,
    durationMs: run.durationMs,
    git: run.git,
  };
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

function matchSessionRoute(pathname: string): SessionRouteParams | undefined {
  let match = pathname.match(/^\/sdk\/sessions\/([^/]+)\/(?:messages|state)$/);
  if (match) {
    return { sessionId: decodeURIComponent(match[1]!) };
  }

  match = pathname.match(/^\/sdk\/sessions\/([^/]+)\/runs\/([^/]+)\/events$/);
  if (!match) {
    return undefined;
  }
  return {
    sessionId: decodeURIComponent(match[1]!),
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

function mcpProfile(id: string | undefined): SDKMCPProfile | undefined {
  const profileId = emptyToUndefined(id);
  if (!profileId) {
    return undefined;
  }
  return mcpProfiles().find((profile) => profile.id === profileId);
}

function selectedProfileMetadata(id: string | undefined) {
  const profile = mcpProfile(id);
  return profile ? publicMCPProfile(profile) : undefined;
}

function publicMCPProfiles() {
  return mcpProfiles().map(publicMCPProfile);
}

function publicMCPProfile(profile: SDKMCPProfile) {
  return {
    id: profile.id,
    name: profile.name,
    description: profile.description,
    mcpServerCount: Object.keys(profile.mcpServers ?? {}).length,
    subagentCount: profile.agents && typeof profile.agents === "object" ? Object.keys(profile.agents).length : 0,
  };
}

function mcpProfiles(): SDKMCPProfile[] {
  const raw = emptyToUndefined(process.env.RUNLINE_SDK_MCP_PROFILES);
  if (!raw) {
    return [];
  }
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed)) {
    throw new Error("RUNLINE_SDK_MCP_PROFILES must be a JSON array.");
  }
  return parsed
    .filter((profile): profile is SDKMCPProfile => {
      return Boolean(
        profile
        && typeof profile === "object"
        && typeof profile.id === "string"
        && typeof profile.name === "string"
      );
    });
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
