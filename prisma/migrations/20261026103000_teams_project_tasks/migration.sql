CREATE TYPE "ProjectTaskStatus" AS ENUM ('TODO', 'IN_PROGRESS', 'BLOCKED', 'COMPLETED');

CREATE TABLE "Team" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "Team_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "TeamBot" (
    "id" TEXT NOT NULL,
    "teamId" TEXT NOT NULL,
    "botId" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "TeamBot_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ProjectTask" (
    "id" TEXT NOT NULL,
    "projectId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "status" "ProjectTaskStatus" NOT NULL DEFAULT 'TODO',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "ProjectTask_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "TaskDependency" (
    "id" TEXT NOT NULL,
    "taskId" TEXT NOT NULL,
    "dependsOnTaskId" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "TaskDependency_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "TaskDependency_not_self_dependent_check" CHECK ("taskId" <> "dependsOnTaskId")
);

CREATE UNIQUE INDEX "Team_userId_name_key" ON "Team"("userId", "name");
CREATE INDEX "Team_userId_updatedAt_idx" ON "Team"("userId", "updatedAt");
CREATE UNIQUE INDEX "TeamBot_teamId_botId_key" ON "TeamBot"("teamId", "botId");
CREATE INDEX "TeamBot_botId_idx" ON "TeamBot"("botId");
CREATE INDEX "ProjectTask_projectId_status_updatedAt_idx" ON "ProjectTask"("projectId", "status", "updatedAt");
CREATE INDEX "ProjectTask_userId_updatedAt_idx" ON "ProjectTask"("userId", "updatedAt");
CREATE UNIQUE INDEX "TaskDependency_taskId_dependsOnTaskId_key" ON "TaskDependency"("taskId", "dependsOnTaskId");
CREATE INDEX "TaskDependency_dependsOnTaskId_idx" ON "TaskDependency"("dependsOnTaskId");

ALTER TABLE "Team"
    ADD CONSTRAINT "Team_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "TeamBot"
    ADD CONSTRAINT "TeamBot_teamId_fkey"
    FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    ADD CONSTRAINT "TeamBot_botId_fkey"
    FOREIGN KEY ("botId") REFERENCES "Bot"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ProjectTask"
    ADD CONSTRAINT "ProjectTask_projectId_fkey"
    FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    ADD CONSTRAINT "ProjectTask_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "TaskDependency"
    ADD CONSTRAINT "TaskDependency_taskId_fkey"
    FOREIGN KEY ("taskId") REFERENCES "ProjectTask"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    ADD CONSTRAINT "TaskDependency_dependsOnTaskId_fkey"
    FOREIGN KEY ("dependsOnTaskId") REFERENCES "ProjectTask"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
