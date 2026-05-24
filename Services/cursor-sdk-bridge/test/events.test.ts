import { describe, expect, it } from "vitest";
import { encodeSSE, EventHub } from "../src/events.js";

describe("EventHub", () => {
  it("stores replayable events after a cursor", () => {
    const hub = new EventHub();
    const first = hub.append("run-1", "status", { status: "RUNNING" });
    const second = hub.append("run-1", "assistant", { text: "Hello" });

    expect(hub.snapshot("run-1")).toHaveLength(2);
    expect(hub.snapshot("run-1", first.id)).toEqual([second]);
  });

  it("notifies subscribers and removes them on unsubscribe", () => {
    const hub = new EventHub();
    const seen: string[] = [];
    const unsubscribe = hub.subscribe("run-1", (event) => {
      seen.push(event.id);
    });

    const first = hub.append("run-1", "status", { status: "RUNNING" });
    expect(seen).toEqual([first.id]);
    expect(hub.listenerCount("run-1")).toBe(1);

    unsubscribe();
    hub.append("run-1", "assistant", { text: "Hello" });

    expect(seen).toEqual([first.id]);
    expect(hub.listenerCount("run-1")).toBe(0);
  });

  it("encodes valid SSE frames", () => {
    const hub = new EventHub();
    const event = hub.append("run-1", "done", { type: "done" });

    expect(encodeSSE(event)).toContain(`id: ${event.id}`);
    expect(encodeSSE(event)).toContain("event: done");
    expect(encodeSSE(event)).toContain("data:");
  });

  it("records redacted event shapes without payload values or path-like keys", () => {
    const hub = new EventHub();
    hub.append("run-1", "assistant", {
      text: "do not retain this prompt",
      "src/private.ts": {
        patch: "do not retain this diff",
      },
      artifacts: [
        {
          url: "https://example.com/private-artifact",
        },
      ],
    });

    const shapeText = JSON.stringify(hub.shapeSnapshot("run-1"));
    expect(shapeText).toContain("text");
    expect(shapeText).toContain("redacted_key_1");
    expect(shapeText).not.toContain("do not retain");
    expect(shapeText).not.toContain("src/private.ts");
    expect(shapeText).not.toContain("https://example.com");
  });

  it("limits retained event shapes and clears run state", () => {
    const hub = new EventHub();
    const unsubscribe = hub.subscribe("run-1", () => {});

    for (let index = 0; index < 250; index += 1) {
      hub.append("run-1", "status", { index });
    }

    expect(hub.snapshot("run-1")).toHaveLength(250);
    expect(hub.shapeSnapshot("run-1", 250)).toHaveLength(200);
    expect(hub.listenerCount("run-1")).toBe(1);

    hub.clearRun("run-1");

    expect(hub.snapshot("run-1")).toEqual([]);
    expect(hub.shapeSnapshot("run-1")).toEqual([]);
    expect(hub.listenerCount("run-1")).toBe(0);
    unsubscribe();
  });
});
