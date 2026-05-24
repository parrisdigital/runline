import { describe, expect, it } from "vitest";
import { conversationTitle } from "../src/conversationTitle.js";

describe("conversationTitle", () => {
  it("creates short display names without retaining full prompts", () => {
    expect(conversationTitle("Can you research native Cursor app architecture?"))
      .toBe("Research Native Cursor App Architecture");
    expect(conversationTitle("alright what should we build?"))
      .toBe("Next Project Ideas");
    expect(conversationTitle("Plan the SDK bridge workspace drawer and persistence model"))
      .toBe("Plan The SDK Bridge Workspace Drawer And");
  });
});
