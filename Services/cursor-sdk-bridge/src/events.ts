export type BridgeEvent = {
  id: string;
  event: string;
  data: unknown;
  createdAt: string;
};

export type RedactedValueShape =
  | { type: "null" }
  | { type: "undefined" }
  | { type: "string" }
  | { type: "number" }
  | { type: "boolean" }
  | { type: "bigint" }
  | { type: "symbol" }
  | { type: "function" }
  | { type: "max_depth" }
  | { type: "array"; length: number; items: RedactedValueShape[] }
  | { type: "object"; keyCount: number; keys: string[]; values: Record<string, RedactedValueShape>; truncated?: boolean }
  | { type: "object"; circular: true };

export type EventShapeSnapshot = {
  id: string;
  runId: string;
  event: string;
  createdAt: string;
  shape: RedactedValueShape;
};

type Listener = (event: BridgeEvent) => void;

export class EventHub {
  private readonly eventsByRunID = new Map<string, BridgeEvent[]>();
  private readonly eventShapesByRunID = new Map<string, EventShapeSnapshot[]>();
  private readonly listenersByRunID = new Map<string, Set<Listener>>();

  append(runID: string, event: string, data: unknown): BridgeEvent {
    const events = this.eventsByRunID.get(runID) ?? [];
    const nextIndex = events.length + 1;
    const bridgeEvent: BridgeEvent = {
      id: `${runID}:${String(nextIndex).padStart(6, "0")}`,
      event,
      data,
      createdAt: new Date().toISOString(),
    };
    events.push(bridgeEvent);
    this.eventsByRunID.set(runID, events);
    this.appendShape(runID, bridgeEvent);

    for (const listener of this.listenersByRunID.get(runID) ?? []) {
      listener(bridgeEvent);
    }
    return bridgeEvent;
  }

  snapshot(runID: string, afterID?: string): BridgeEvent[] {
    const events = this.eventsByRunID.get(runID) ?? [];
    if (!afterID) {
      return [...events];
    }
    const index = events.findIndex((event) => event.id === afterID);
    if (index === -1) {
      return [...events];
    }
    return events.slice(index + 1);
  }

  shapeSnapshot(runID: string, limit = 200): EventShapeSnapshot[] {
    const shapes = this.eventShapesByRunID.get(runID) ?? [];
    return shapes.slice(Math.max(0, shapes.length - limit));
  }

  subscribe(runID: string, listener: Listener): () => void {
    const listeners = this.listenersByRunID.get(runID) ?? new Set<Listener>();
    listeners.add(listener);
    this.listenersByRunID.set(runID, listeners);

    return () => {
      listeners.delete(listener);
      if (listeners.size === 0) {
        this.listenersByRunID.delete(runID);
      }
    };
  }

  listenerCount(runID: string): number {
    return this.listenersByRunID.get(runID)?.size ?? 0;
  }

  clearRun(runID: string) {
    this.eventsByRunID.delete(runID);
    this.eventShapesByRunID.delete(runID);
    this.listenersByRunID.delete(runID);
  }

  private appendShape(runID: string, event: BridgeEvent) {
    const shapes = this.eventShapesByRunID.get(runID) ?? [];
    shapes.push({
      id: event.id,
      runId: runID,
      event: event.event,
      createdAt: event.createdAt,
      shape: redactedShape(event.data),
    });
    this.eventShapesByRunID.set(runID, shapes.slice(-200));
  }
}

export function encodeSSE(event: BridgeEvent): string {
  const data = JSON.stringify({
    id: event.id,
    event: event.event,
    createdAt: event.createdAt,
    data: event.data,
  });
  return `id: ${event.id}\nevent: ${event.event}\ndata: ${data}\n\n`;
}

function redactedShape(value: unknown, depth = 0, seen = new WeakSet<object>()): RedactedValueShape {
  if (value === null) {
    return { type: "null" };
  }

  switch (typeof value) {
    case "undefined":
      return { type: "undefined" };
    case "string":
      return { type: "string" };
    case "number":
      return { type: "number" };
    case "boolean":
      return { type: "boolean" };
    case "bigint":
      return { type: "bigint" };
    case "symbol":
      return { type: "symbol" };
    case "function":
      return { type: "function" };
    case "object":
      break;
  }

  if (Array.isArray(value)) {
    if (depth >= 6) {
      return { type: "array", length: value.length, items: [] };
    }
    return {
      type: "array",
      length: value.length,
      items: value.slice(0, 3).map((item) => redactedShape(item, depth + 1, seen)),
    };
  }

  if (seen.has(value)) {
    return { type: "object", circular: true };
  }
  seen.add(value);

  const entries = Object.entries(value).slice(0, 50);
  const values: Record<string, RedactedValueShape> = {};
  const keys: string[] = [];
  const redactedKeyCounts = new Map<string, number>();

  for (const [key, nestedValue] of entries) {
    const safeKey = safeShapeKey(key, redactedKeyCounts);
    keys.push(safeKey);
    values[safeKey] = depth >= 6 ? { type: "max_depth" } : redactedShape(nestedValue, depth + 1, seen);
  }

  return {
    type: "object",
    keyCount: Object.keys(value).length,
    keys,
    values,
    truncated: Object.keys(value).length > entries.length ? true : undefined,
  };
}

function safeShapeKey(key: string, redactedKeyCounts: Map<string, number>): string {
  if (/^[A-Za-z_][A-Za-z0-9_-]{0,63}$/.test(key)) {
    return key;
  }

  const base = "redacted_key";
  const next = (redactedKeyCounts.get(base) ?? 0) + 1;
  redactedKeyCounts.set(base, next);
  return `${base}_${next}`;
}
