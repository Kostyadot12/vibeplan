-- CreateTable
CREATE TABLE "PendingSpaceInvite" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "email" TEXT NOT NULL,
    "spaceId" TEXT NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'member',
    "invitedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "PendingSpaceInvite_spaceId_fkey" FOREIGN KEY ("spaceId") REFERENCES "Space" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateIndex
CREATE INDEX "PendingSpaceInvite_email_idx" ON "PendingSpaceInvite"("email");

-- CreateIndex
CREATE UNIQUE INDEX "PendingSpaceInvite_email_spaceId_key" ON "PendingSpaceInvite"("email", "spaceId");
