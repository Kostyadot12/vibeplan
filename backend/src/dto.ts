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
  creatorId: string | null;
  spaceId:   string | null;   // NULL = personal (creator only)
  reminderMinutes: number | null;
  subtasks: SubtaskDTO[];
  assignees: AssigneeDTO[];
  attachments: AttachmentDTO[];
  tagIds: string[];
}

export interface AssigneeDTO {
  id: string;
  email: string;
  name: string;
}

export interface AttachmentDTO {
  id: string;
  filename: string;
  mimeType: string;
  sizeBytes: number;
  url: string;          // /uploads/attachments/...
  uploadedAt: string;
  uploadedById: string | null;
}

export function attachmentToDTO(a: {
  id: string; filename: string; mimeType: string; sizeBytes: number;
  storagePath: string; uploadedAt: Date; uploadedById: string | null;
}): AttachmentDTO {
  return {
    id: a.id,
    filename: a.filename,
    mimeType: a.mimeType,
    sizeBytes: a.sizeBytes,
    url: a.storagePath,
    uploadedAt: a.uploadedAt.toISOString(),
    uploadedById: a.uploadedById
  };
}

export interface SpaceDTO {
  id: string;
  name: string;
  color: string;
  ownerId: string;
  createdAt: string;
  members: SpaceMemberDTO[];
}

export interface SpaceMemberDTO {
  userId: string;
  email: string;
  name: string;
  role: string;       // "owner" | "member"
  joinedAt: string;
}

export function spaceToDTO(s: {
  id: string; name: string; color: string;
  ownerId: string; createdAt: Date;
  members: { userId: string; role: string; joinedAt: Date;
             user: { email: string; name: string } }[];
}): SpaceDTO {
  return {
    id: s.id,
    name: s.name,
    color: s.color,
    ownerId: s.ownerId,
    createdAt: s.createdAt.toISOString(),
    members: s.members.map(m => ({
      userId: m.userId,
      email:  m.user.email,
      name:   m.user.name,
      role:   m.role,
      joinedAt: m.joinedAt.toISOString()
    }))
  };
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
  creatorId: string | null; spaceId: string | null;
  reminderMinutes: number | null;
  subtasks: { id: string; title: string; done: boolean; order: number }[];
  assignees: { user: { id: string; email: string; name: string } }[];
  attachments: { id: string; filename: string; mimeType: string;
                 sizeBytes: number; storagePath: string;
                 uploadedAt: Date; uploadedById: string | null }[];
  tags: { tagId: string }[];
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
    creatorId: t.creatorId,
    spaceId:   t.spaceId,
    reminderMinutes: t.reminderMinutes,
    subtasks: t.subtasks
      .slice()
      .sort((a, b) => a.order - b.order)
      .map(s => ({ id: s.id, title: s.title, done: s.done, order: s.order })),
    assignees: t.assignees.map(a => ({
      id: a.user.id, email: a.user.email, name: a.user.name
    })),
    attachments: t.attachments.map(attachmentToDTO),
    tagIds: t.tags.map(tt => tt.tagId)
  };
}
