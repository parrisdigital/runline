import { describe, expect, it } from "vitest";
import { promptText } from "../src/cursorSdk.js";

describe("promptText", () => {
  it("keeps repository-backed prompts unchanged", () => {
    const prompt = "Build the settings polish in this repo.";

    expect(promptText({
      prompt,
      repo: {
        url: "https://github.com/acme/app",
        startingRef: "main",
      },
    })).toBe(prompt);

    expect(promptText({
      prompt,
      repositoryUrl: "https://github.com/acme/app",
      startingRef: "main",
    })).toBe(prompt);
  });

  it("adds a direct-answer instruction for repo-less General Chat", () => {
    const text = promptText({
      prompt: "What should we build this weekend?",
    });

    expect(text).toContain("Runline General Chat");
    expect(text).toContain("Do not inspect the workspace");
    expect(text).toContain("What should we build this weekend?");
  });
});
