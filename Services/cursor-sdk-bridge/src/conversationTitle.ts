const knownForms: Record<string, string> = {
  api: "API",
  sdk: "SDK",
  ui: "UI",
  ux: "UX",
  ios: "iOS",
  ipados: "iPadOS",
  macos: "macOS",
  github: "GitHub",
  gitlab: "GitLab",
  json: "JSON",
  sse: "SSE",
  pr: "PR",
  repo: "Repo",
};

export function conversationTitle(prompt: string): string | undefined {
  if (isGenericBuildPrompt(prompt)) {
    return "Next Project Ideas";
  }

  const cleaned = cleanTitleSource(prompt);
  if (!cleaned) {
    return undefined;
  }
  return titleCase(cleaned);
}

function cleanTitleSource(value: string): string {
  let text = value.split(/\r?\n/, 1)[0] ?? value;
  text = text.replace(/^["'`]*\s*(please\s+)?(can|could|would)\s+you\s+/i, "");
  text = text.replace(/^["'`]*\s*(please\s+)?(help\s+me|i\s+need\s+you\s+to|i\s+want\s+to|let'?s|we\s+need\s+to)\s+/i, "");
  text = text.replace(/\busing\s+(cursor|runline|the\s+app)\b/gi, "");
  text = text.replace(/["'`*_#>\[\]()]+/g, " ");
  text = text.replace(/[.!?;:]+$/g, "");

  return text
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 7)
    .join(" ")
    .trim();
}

function titleCase(value: string): string {
  return value
    .split(/\s+/)
    .filter(Boolean)
    .map(formatWord)
    .join(" ");
}

function formatWord(word: string): string {
  const trimmed = word.replace(/^[^a-z0-9]+|[^a-z0-9]+$/gi, "");
  const lowercase = trimmed.toLowerCase();
  const known = knownForms[lowercase];
  if (known) {
    return known;
  }
  if (/[A-Z]/.test(trimmed) && /[a-z]/.test(trimmed.slice(1))) {
    return trimmed;
  }
  return lowercase ? `${lowercase[0]?.toUpperCase()}${lowercase.slice(1)}` : trimmed;
}

function normalizedComparisonValue(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function isGenericBuildPrompt(value: string): boolean {
  const normalized = normalizedComparisonValue(value);
  return normalized.includes("what should") && normalized.includes("build")
    || normalized.includes("what are we building")
    || normalized.includes("project ideas")
    || normalized.includes("next project");
}
