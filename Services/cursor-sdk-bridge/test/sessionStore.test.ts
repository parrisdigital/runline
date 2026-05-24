import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, describe, expect, it } from "vitest";
import {
  FileSessionStore,
  InMemorySessionStore,
  type BridgeRunState,
  type BridgeSession,
} from "../src/sessionStore.js";

let temporaryDirectories: string[] = [];

afterEach(() => {
  for (const directory of temporaryDirectories) {
    rmSync(directory, { recursive: true, force: true });
  }
  temporaryDirectories = [];
});

describe("session stores", () => {
  it("keeps in-memory sessions sorted by update time", () => {
    const store = new InMemorySessionStore();
    store.upsertSession(session("session-older", "2026-05-23T10:00:00.000Z"));
    store.upsertSession(session("session-newer", "2026-05-23T11:00:00.000Z"));

    expect(store.kind).toBe("memory");
    expect(store.isPersistent).toBe(false);
    expect(store.listSessions().map((item) => item.sessionId)).toEqual(["session-newer", "session-older"]);
  });

  it("persists session metadata across store instances", () => {
    const storePath = temporaryStorePath();
    const first = new FileSessionStore(storePath);
    const bridgeSession = {
      ...session("agent-1", "2026-05-23T10:00:00.000Z"),
      name: "Build Expo Testable App",
    };
    const run = runState("run-1", "agent-1", "running");

    first.upsertSession(bridgeSession);
    first.appendRun(bridgeSession.sessionId, run);
    first.updateRun(bridgeSession.sessionId, run.runId, {
      status: "finished",
      result: "private assistant summary should not be persisted",
      durationMs: 1_250,
      git: {
        branches: [
          {
            prUrl: "https://github.com/acme/app/pull/12",
          },
        ],
      } as BridgeRunState["git"],
    });

    const second = new FileSessionStore(storePath);
    const restored = second.requireSession("agent-1");

    expect(second.kind).toBe("file");
    expect(second.isPersistent).toBe(true);
    expect(restored.name).toBe("Build Expo Testable App");
    expect(restored.latestRunId).toBe("run-1");
    expect(restored.runs[0]?.status).toBe("finished");
    expect(restored.runs[0]?.durationMs).toBe(1_250);
    expect(restored.runs[0]?.result).toBeUndefined();
    expect(JSON.stringify(restored)).not.toContain("private assistant summary");
  });

  it("throws a classified not-found error for missing sessions", () => {
    const store = new InMemorySessionStore();

    expect(() => store.requireSession("missing")).toThrow("Session not found.");
  });
});

function temporaryStorePath(): string {
  const directory = mkdtempSync(join(tmpdir(), "runline-session-store-"));
  temporaryDirectories.push(directory);
  return join(directory, "sessions.json");
}

function session(sessionID: string, updatedAt: string): BridgeSession {
  return {
    sessionId: sessionID,
    agentId: sessionID,
    repositoryUrl: "https://github.com/acme/app",
    startingRef: "main",
    modelId: "composer-2.5",
    autoCreatePR: true,
    runs: [],
    createdAt: "2026-05-23T09:00:00.000Z",
    updatedAt,
  };
}

function runState(runID: string, agentID: string, status: BridgeRunState["status"]): BridgeRunState {
  return {
    runId: runID,
    agentId: agentID,
    status,
    createdAt: "2026-05-23T10:01:00.000Z",
    updatedAt: "2026-05-23T10:01:00.000Z",
  };
}
