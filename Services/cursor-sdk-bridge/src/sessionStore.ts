import type { RunResult } from "@cursor/sdk";
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { z } from "zod";

export type BridgeRunState = {
  runId: string;
  agentId: string;
  status: "running" | "finished" | "error" | "cancelled";
  createdAt: string;
  updatedAt: string;
  result?: string;
  durationMs?: number;
  git?: RunResult["git"];
};

export type BridgeSession = {
  sessionId: string;
  agentId: string;
  name?: string;
  repositoryUrl?: string;
  startingRef?: string;
  prUrl?: string;
  modelId?: string;
  autoCreatePR: boolean;
  latestRunId?: string;
  runs: BridgeRunState[];
  createdAt: string;
  updatedAt: string;
};

export interface SessionStore {
  readonly kind: "memory" | "file";
  readonly isPersistent: boolean;
  upsertSession(session: BridgeSession): BridgeSession;
  getSession(sessionID: string): BridgeSession | undefined;
  listSessions(): BridgeSession[];
  requireSession(sessionID: string): BridgeSession;
  appendRun(sessionID: string, run: BridgeRunState): BridgeSession;
  updateRun(sessionID: string, runID: string, update: Partial<BridgeRunState>): BridgeRunState;
  latestRun(sessionID: string): BridgeRunState | undefined;
}

const persistedRunSchema = z.object({
  runId: z.string().min(1),
  agentId: z.string().min(1),
  status: z.enum(["running", "finished", "error", "cancelled"]),
  createdAt: z.string().min(1),
  updatedAt: z.string().min(1),
  durationMs: z.number().optional(),
  git: z.unknown().optional(),
});

const persistedSessionSchema = z.object({
  sessionId: z.string().min(1),
  agentId: z.string().min(1),
  name: z.string().optional(),
  repositoryUrl: z.string().optional(),
  startingRef: z.string().optional(),
  prUrl: z.string().optional(),
  modelId: z.string().optional(),
  autoCreatePR: z.boolean(),
  latestRunId: z.string().optional(),
  runs: z.array(persistedRunSchema),
  createdAt: z.string().min(1),
  updatedAt: z.string().min(1),
});

const persistedFileSchema = z.object({
  version: z.literal(1),
  sessions: z.array(persistedSessionSchema),
});

type PersistedFile = z.infer<typeof persistedFileSchema>;

export class InMemorySessionStore implements SessionStore {
  readonly kind: SessionStore["kind"] = "memory";
  readonly isPersistent: boolean = false;
  protected readonly sessions = new Map<string, BridgeSession>();

  constructor(initialSessions: BridgeSession[] = []) {
    for (const session of initialSessions) {
      this.sessions.set(session.sessionId, session);
    }
  }

  upsertSession(session: BridgeSession): BridgeSession {
    this.sessions.set(session.sessionId, session);
    this.didMutate();
    return session;
  }

  getSession(sessionID: string): BridgeSession | undefined {
    return this.sessions.get(sessionID);
  }

  listSessions(): BridgeSession[] {
    return [...this.sessions.values()].sort((lhs, rhs) => rhs.updatedAt.localeCompare(lhs.updatedAt));
  }

  requireSession(sessionID: string): BridgeSession {
    const session = this.getSession(sessionID);
    if (!session) {
      const error = new Error("Session not found.");
      Object.assign(error, { statusCode: 404, code: "session_not_found" });
      throw error;
    }
    return session;
  }

  appendRun(sessionID: string, run: BridgeRunState): BridgeSession {
    const session = this.requireSession(sessionID);
    session.latestRunId = run.runId;
    session.runs = [run, ...session.runs.filter((existing) => existing.runId !== run.runId)];
    session.updatedAt = new Date().toISOString();
    this.sessions.set(sessionID, session);
    this.didMutate();
    return session;
  }

  updateRun(sessionID: string, runID: string, update: Partial<BridgeRunState>): BridgeRunState {
    const session = this.requireSession(sessionID);
    const index = session.runs.findIndex((run) => run.runId === runID);
    if (index === -1) {
      const error = new Error("Run not found.");
      Object.assign(error, { statusCode: 404, code: "run_not_found" });
      throw error;
    }
    const updatedRun = {
      ...session.runs[index],
      ...update,
      updatedAt: new Date().toISOString(),
    };
    session.runs[index] = updatedRun;
    session.updatedAt = updatedRun.updatedAt;
    this.sessions.set(sessionID, session);
    this.didMutate();
    return updatedRun;
  }

  latestRun(sessionID: string): BridgeRunState | undefined {
    const session = this.requireSession(sessionID);
    return session.latestRunId ? session.runs.find((run) => run.runId === session.latestRunId) : undefined;
  }

  protected didMutate() {
    // In-memory store has nothing to flush.
  }
}

export class FileSessionStore extends InMemorySessionStore {
  override readonly kind = "file";
  override readonly isPersistent = true;

  constructor(private readonly filePath: string) {
    super(loadPersistedSessions(filePath));
  }

  protected override didMutate() {
    const directory = dirname(this.filePath);
    mkdirSync(directory, { recursive: true, mode: 0o700 });

    const payload: PersistedFile = {
      version: 1,
      sessions: this.listSessions().map(sessionForPersistence),
    };
    const temporaryPath = `${this.filePath}.${process.pid}.tmp`;
    writeFileSync(temporaryPath, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
    renameSync(temporaryPath, this.filePath);
  }
}

export function createSessionStore(): SessionStore {
  const explicitPath = process.env.RUNLINE_BRIDGE_SESSION_STORE_PATH?.trim();
  const legacyPath = process.env.RUNLINE_BRIDGE_STORE_PATH?.trim();
  const flyPath = process.env.FLY_APP_NAME ? "/data/runline-sdk-bridge/sessions.json" : undefined;
  const storePath = explicitPath || legacyPath || flyPath;
  return storePath ? new FileSessionStore(storePath) : new InMemorySessionStore();
}

function loadPersistedSessions(filePath: string): BridgeSession[] {
  if (!existsSync(filePath)) {
    return [];
  }

  const raw = readFileSync(filePath, "utf8");
  if (!raw.trim()) {
    return [];
  }

  const parsed = persistedFileSchema.parse(JSON.parse(raw));
  return parsed.sessions.map((session) => ({
    ...session,
    runs: session.runs.map((run) => ({
      ...run,
      result: undefined,
      git: run.git as RunResult["git"] | undefined,
    })),
  }));
}

function sessionForPersistence(session: BridgeSession): BridgeSession {
  return {
    ...session,
    runs: session.runs.map((run) => ({
      ...run,
      result: undefined,
    })),
  };
}
