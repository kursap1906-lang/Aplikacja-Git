CREATE TYPE "ProjectHelpRequestStatus" AS ENUM ('OPEN', 'RESOLVED');

CREATE TABLE "ProjectMessage" (
    "id" TEXT NOT NULL,
    "projectId" TEXT NOT NULL,
    "authorUserId" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ProjectMessage_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ProjectHelpRequest" (
    "id" TEXT NOT NULL,
    "projectId" TEXT NOT NULL,
    "authorUserId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "status" "ProjectHelpRequestStatus" NOT NULL DEFAULT 'OPEN',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMPTZ(6),
    CONSTRAINT "ProjectHelpRequest_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ProjectCheckpoint" (
    "id" TEXT NOT NULL,
    "projectId" TEXT NOT NULL,
    "authorUserId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "notes" TEXT NOT NULL DEFAULT '',
    "commitSha" TEXT,
    "progressStage" "ProjectProgressStage",
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ProjectCheckpoint_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "ProjectMessage_projectId_createdAt_idx" ON "ProjectMessage"("projectId", "createdAt");
CREATE INDEX "ProjectMessage_authorUserId_createdAt_idx" ON "ProjectMessage"("authorUserId", "createdAt");
CREATE INDEX "ProjectHelpRequest_projectId_status_createdAt_idx" ON "ProjectHelpRequest"("projectId", "status", "createdAt");
CREATE INDEX "ProjectHelpRequest_authorUserId_createdAt_idx" ON "ProjectHelpRequest"("authorUserId", "createdAt");
CREATE INDEX "ProjectCheckpoint_projectId_createdAt_idx" ON "ProjectCheckpoint"("projectId", "createdAt");
CREATE INDEX "ProjectCheckpoint_authorUserId_createdAt_idx" ON "ProjectCheckpoint"("authorUserId", "createdAt");

ALTER TABLE "ProjectMessage"
    ADD CONSTRAINT "ProjectMessage_projectId_fkey"
    FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    ADD CONSTRAINT "ProjectMessage_authorUserId_fkey"
    FOREIGN KEY ("authorUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ProjectHelpRequest"
    ADD CONSTRAINT "ProjectHelpRequest_projectId_fkey"
    FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    ADD CONSTRAINT "ProjectHelpRequest_authorUserId_fkey"
    FOREIGN KEY ("authorUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ProjectCheckpoint"
    ADD CONSTRAINT "ProjectCheckpoint_projectId_fkey"
    FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    ADD CONSTRAINT "ProjectCheckpoint_authorUserId_fkey"
    FOREIGN KEY ("authorUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
