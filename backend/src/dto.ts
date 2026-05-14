/// Wire types — the shape of the JSON we send out and expect on input.
/// Distinct from Prisma's database types so the API contract is independent
/// of internal storage choices.

export interface TaskDTO {
  id: string;
  title: string;
  note: string;
  startDate: string;          // ISO 8601
  durationMinutes: number;
  category: string;
  status: string;
  sortOrder: number;
  inInbox: boolean;
  createdAt: string;
  updatedAt: string;
  subtasks: SubtaskDTO[];
  assignees: AssigneeDTO[];
}

export interface AssigneeDTO {
  id: string;
  email: string;
  name: string;
}

export interface SubtaskDTO {
  id: string;
  title: string;
  done: boolean;
  order: number;
}

/** Convert the Prisma include-result into the wire shape. */
export function taskToDTO(t: {
  id: string; title: string; note: string;
  startDate: Date; durationMinutes: number;
  category: string; status: string;
  sortOrder: number; inInbox: boolean;
  createdAt: Date; updatedAt: Date;
  subtasks: { id: string; title: string; done: boolean; order: number }[];
  assignees: { user: { id: string; email: string; name: string } }[];
}): TaskDTO {
  return {
    id: t.id,
    title: t.title,
    note: t.note,
    startDate: t.startDate.toISOString(),
    durationMinutes: t.durationMinutes,
    category: t.category,
    status: t.status,
    sortOrder: t.sortOrder,
    inInbox: t.inInbox,
    createdAt: t.createdAt.toISOString(),
    updatedAt: t.updatedAt.toISOString(),
    subtasks: t.subtasks
      .slice()
      .sort((a, b) => a.order - b.order)
      .map(s => ({ id: s.id, title: s.title, done: s.done, order: s.order })),
    assignees: t.assignees.map(a => ({
      id: a.user.id, email: a.user.email, name: a.user.name
    }))
  };
}
