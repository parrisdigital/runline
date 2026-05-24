import { z } from "zod";

const imageDimensionSchema = z.object({
  width: z.number().int().positive(),
  height: z.number().int().positive(),
});

const imageSchema = z.object({
  data: z.string().min(1),
  mimeType: z.enum(["image/png", "image/jpeg", "image/gif", "image/webp"]),
  dimension: imageDimensionSchema.optional(),
});

const repoSchema = z.object({
  url: z.string().url(),
  startingRef: z.string().trim().min(1).optional(),
  prUrl: z.string().url().optional(),
});

export const sessionCreateSchema = z.object({
  prompt: z.string().trim().min(1),
  images: z.array(imageSchema).max(5).optional(),
  repo: repoSchema.optional(),
  repositoryUrl: z.string().url().optional(),
  startingRef: z.string().trim().min(1).optional(),
  prUrl: z.string().url().optional(),
  modelId: z.string().trim().min(1).optional(),
  autoCreatePR: z.boolean().default(true),
  skipReviewerRequest: z.boolean().optional(),
  workOnCurrentBranch: z.boolean().optional(),
  mcpServers: z.record(z.unknown()).optional(),
  agents: z.record(z.unknown()).optional(),
  idempotencyKey: z.string().trim().min(1).optional(),
});

export const sessionMessageSchema = z.object({
  prompt: z.string().trim().min(1),
  images: z.array(imageSchema).max(5).optional(),
  modelId: z.string().trim().min(1).optional(),
  mcpServers: z.record(z.unknown()).optional(),
  idempotencyKey: z.string().trim().min(1).optional(),
});

export const cancelRunSchema = z.object({
  runId: z.string().trim().min(1).optional(),
});

export type SessionCreateInput = z.infer<typeof sessionCreateSchema>;
export type SessionMessageInput = z.infer<typeof sessionMessageSchema>;
export type CancelRunInput = z.infer<typeof cancelRunSchema>;
