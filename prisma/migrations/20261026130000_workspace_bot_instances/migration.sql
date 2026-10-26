-- CreateEnum
CREATE TYPE "TaskPriority" AS ENUM ('LOW', 'NORMAL', 'HIGH', 'URGENT');

-- CreateEnum
CREATE TYPE "BotMessageRole" AS ENUM ('USER', 'ASSISTANT', 'CONTEXT');

-- CreateEnum
CREATE TYPE "BotMessageStatus" AS ENUM ('DRAFT', 'SENT', 'FAILED');

-- AlterTable
ALTER TABLE "Bot" ADD COLUMN     "definitionId" TEXT;

-- AlterTable
ALTER TABLE "Project" ADD COLUMN     "brief" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "defaultBranch" TEXT,
ADD COLUMN     "mainGithubAccountId" TEXT,
ADD COLUMN     "repositoryContext" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "repositoryId" TEXT;

-- AlterTable
ALTER TABLE "Team" ADD COLUMN     "projectId" TEXT;

-- AlterTable
ALTER TABLE "TeamBot" ADD COLUMN     "parentId" TEXT;

-- AlterTable
ALTER TABLE "ProjectTask" ADD COLUMN     "botId" TEXT,
ADD COLUMN     "priority" "TaskPriority" NOT NULL DEFAULT 'NORMAL',
ADD COLUMN     "teamId" TEXT;

-- CreateTable
CREATE TABLE "BotDefinition" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "role" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "systemPrompt" TEXT NOT NULL,
    "skills" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "BotDefinition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BotMessage" (
    "id" TEXT NOT NULL,
    "botId" TEXT NOT NULL,
    "role" "BotMessageRole" NOT NULL DEFAULT 'USER',
    "status" "BotMessageStatus" NOT NULL DEFAULT 'DRAFT',
    "content" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BotMessage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BotWorkSchedule" (
    "id" TEXT NOT NULL,
    "botId" TEXT NOT NULL,
    "timezone" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "days" INTEGER[],
    "startTime" TEXT NOT NULL,
    "endTime" TEXT NOT NULL,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "BotWorkSchedule_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WorkspaceFile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "projectId" TEXT,
    "messageId" TEXT,
    "transitionId" TEXT,
    "filename" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "contentHash" TEXT NOT NULL,
    "encryptedContent" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WorkspaceFile_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "BotDefinition_userId_updatedAt_idx" ON "BotDefinition"("userId", "updatedAt");

-- CreateIndex
CREATE UNIQUE INDEX "BotDefinition_userId_name_key" ON "BotDefinition"("userId", "name");

-- CreateIndex
CREATE INDEX "BotMessage_botId_createdAt_idx" ON "BotMessage"("botId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "BotWorkSchedule_botId_key" ON "BotWorkSchedule"("botId");

-- CreateIndex
CREATE INDEX "WorkspaceFile_projectId_createdAt_idx" ON "WorkspaceFile"("projectId", "createdAt");

-- CreateIndex
CREATE INDEX "WorkspaceFile_messageId_createdAt_idx" ON "WorkspaceFile"("messageId", "createdAt");

-- CreateIndex
CREATE INDEX "WorkspaceFile_transitionId_createdAt_idx" ON "WorkspaceFile"("transitionId", "createdAt");

-- CreateIndex
CREATE INDEX "WorkspaceFile_userId_createdAt_idx" ON "WorkspaceFile"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "Bot_definitionId_idx" ON "Bot"("definitionId");

-- CreateIndex
CREATE INDEX "Project_mainGithubAccountId_idx" ON "Project"("mainGithubAccountId");

-- CreateIndex
CREATE INDEX "Team_projectId_idx" ON "Team"("projectId");

-- CreateIndex
CREATE INDEX "TeamBot_parentId_idx" ON "TeamBot"("parentId");

-- CreateIndex
CREATE INDEX "ProjectTask_teamId_botId_idx" ON "ProjectTask"("teamId", "botId");

-- AddForeignKey
ALTER TABLE "Bot" ADD CONSTRAINT "Bot_definitionId_fkey" FOREIGN KEY ("definitionId") REFERENCES "BotDefinition"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BotDefinition" ADD CONSTRAINT "BotDefinition_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Project" ADD CONSTRAINT "Project_mainGithubAccountId_fkey" FOREIGN KEY ("mainGithubAccountId") REFERENCES "GitHubAccount"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Team" ADD CONSTRAINT "Team_projectId_fkey" FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TeamBot" ADD CONSTRAINT "TeamBot_parentId_fkey" FOREIGN KEY ("parentId") REFERENCES "TeamBot"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProjectTask" ADD CONSTRAINT "ProjectTask_botId_fkey" FOREIGN KEY ("botId") REFERENCES "Bot"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProjectTask" ADD CONSTRAINT "ProjectTask_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BotMessage" ADD CONSTRAINT "BotMessage_botId_fkey" FOREIGN KEY ("botId") REFERENCES "Bot"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BotWorkSchedule" ADD CONSTRAINT "BotWorkSchedule_botId_fkey" FOREIGN KEY ("botId") REFERENCES "Bot"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WorkspaceFile" ADD CONSTRAINT "WorkspaceFile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WorkspaceFile" ADD CONSTRAINT "WorkspaceFile_projectId_fkey" FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WorkspaceFile" ADD CONSTRAINT "WorkspaceFile_messageId_fkey" FOREIGN KEY ("messageId") REFERENCES "BotMessage"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WorkspaceFile" ADD CONSTRAINT "WorkspaceFile_transitionId_fkey" FOREIGN KEY ("transitionId") REFERENCES "StageTransitionEvent"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "WorkspaceFile" ADD CONSTRAINT "WorkspaceFile_one_owner_check"
CHECK (num_nonnulls("projectId", "messageId", "transitionId") = 1);

ALTER TABLE "WorkspaceFile" ADD CONSTRAINT "WorkspaceFile_size_check"
CHECK ("sizeBytes" > 0 AND "sizeBytes" <= 10485760);
