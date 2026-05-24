import type { FastifyRequest } from "fastify";

export class BridgeAuthError extends Error {
  readonly statusCode = 401;

  constructor(message = "Bridge authorization is required.") {
    super(message);
    this.name = "BridgeAuthError";
  }
}

export class CursorAPIKeyError extends Error {
  readonly statusCode = 401;

  constructor(message = "Cursor API key is required.") {
    super(message);
    this.name = "CursorAPIKeyError";
  }
}

export function requireBridgeSecret(request: FastifyRequest) {
  const configuredSecret = process.env.RUNLINE_BRIDGE_AUTH_SECRET?.trim();
  if (!configuredSecret) {
    return;
  }

  const providedSecret = headerValue(request, "x-runline-bridge-secret");
  if (providedSecret !== configuredSecret) {
    throw new BridgeAuthError();
  }
}

export function cursorAPIKey(request: FastifyRequest): string {
  const key = headerValue(request, "x-cursor-api-key") ?? process.env.CURSOR_API_KEY;
  const trimmedKey = key?.trim();
  if (!trimmedKey) {
    throw new CursorAPIKeyError();
  }
  return trimmedKey;
}

export function publicAuthState(request: FastifyRequest) {
  const bridgeAuthConfigured = Boolean(process.env.RUNLINE_BRIDGE_AUTH_SECRET?.trim());
  return {
    bridgeAuthConfigured,
    bridgeAuthorized: !bridgeAuthConfigured || headerValue(request, "x-runline-bridge-secret") === process.env.RUNLINE_BRIDGE_AUTH_SECRET?.trim(),
    cursorKeyFallbackConfigured: Boolean(process.env.CURSOR_API_KEY?.trim()),
  };
}

function headerValue(request: FastifyRequest, name: string): string | undefined {
  const value = request.headers[name];
  if (Array.isArray(value)) {
    return value[0];
  }
  return value;
}
