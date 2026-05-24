import { describe, expect, it } from "vitest";
import { classifiedError, logRedactionPaths } from "../src/server.js";

describe("bridge auth", () => {
  it("redacts Cursor and bridge secret headers from request logs", async () => {
    expect(logRedactionPaths).toContain("req.headers.x-cursor-api-key");
    expect(logRedactionPaths).toContain("req.headers.x-runline-bridge-secret");
  });

  it("maps Cursor hard-limit failures to a sanitized 429 response", async () => {
    const error = new Error("[usage_limit_exceeded] You need to increase your hard limit. Private provider detail.");
    const result = classifiedError(error);

    expect(result.statusCode).toBe(429);
    expect(result.code).toBe("usage_limit_exceeded");
    expect(result.message).toContain("hard usage limit");
    expect(result.message).not.toContain("Private provider detail");
  });
});
