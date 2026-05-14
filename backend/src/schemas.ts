import { z } from "zod";

export const Category = z.enum(["personal", "work", "urgent", "ideas", "learning"]);
export const Status   = z.enum(["open", "inProgress", "done"]);

export const SubtaskInput = z.object({
  id:    z.string().optional(),
  title: z.string().min(1),
  done:  z.boolean().default(false),
  order: z.number().int().default(0)
});

export const TaskCreateInput = z.object({
  // optional — if client wants stable cross-device IDs it can send its own
  id:               z.string().optional(),
  title:            z.string().min(1),
  note:             z.string().default(""),
  startDate:        z.string().datetime(),
  durationMinutes:  z.number().int().min(1).max(24 * 60).default(30),
  category:         Category.default("work"),
  status:           Status.default("open"),
  sortOrder:        z.number().int().default(0),
  inInbox:          z.boolean().default(false),
  subtasks:         z.array(SubtaskInput).default([])
});

export const TaskPatchInput = z.object({
  title:            z.string().min(1).optional(),
  note:             z.string().optional(),
  startDate:        z.string().datetime().optional(),
  durationMinutes:  z.number().int().min(1).max(24 * 60).optional(),
  category:         Category.optional(),
  status:           Status.optional(),
  sortOrder:        z.number().int().optional(),
  inInbox:          z.boolean().optional(),
  subtasks:         z.array(SubtaskInput).optional()
});

export type TaskCreate = z.infer<typeof TaskCreateInput>;
export type TaskPatch  = z.infer<typeof TaskPatchInput>;
