-- CreateEnum
CREATE TYPE "TaskRunStatus" AS ENUM ('QUEUED', 'RUNNING', 'AWAITING_REVIEW', 'APPROVED', 'REJECTED', 'PUSHED', 'PR_OPENED', 'FAILED', 'CANCELLED');

-- CreateTable
CREATE TABLE "TaskRun" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "taskId" TEXT NOT NULL,
    "botId" TEXT NOT NULL,
    "repository" TEXT NOT NULL,
    "defaultBranch" TEXT NOT NULL,
    "baseSha" TEXT,
    "status" "TaskRunStatus" NOT NULL DEFAULT 'QUEUED',
    "stack" TEXT,
    "summary" TEXT,
    "changes" JSONB,
    "testsPassed" BOOLEAN,
    "testCommand" TEXT,
    "testOutput" TEXT,
    "sessionId" TEXT,
    "branchName" TEXT,
    "pushedCommitSha" TEXT,
    "pullRequestUrl" TEXT,
    "errorCode" TEXT,
    "errorMessage" TEXT,
    "cancelRequested" BOOLEAN NOT NULL DEFAULT false,
    "leaseToken" UUID,
    "leaseExpiresAt" TIMESTAMPTZ(6),
    "queuedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "startedAt" TIMESTAMPTZ(6),
    "finishedAt" TIMESTAMPTZ(6),
    "reviewedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "TaskRun_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TaskRunEvent" (
    "id" TEXT NOT NULL,
    "runId" TEXT NOT NULL,
    "seq" INTEGER NOT NULL,
    "kind" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TaskRunEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "TaskRun_userId_createdAt_idx" ON "TaskRun"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "TaskRun_status_queuedAt_idx" ON "TaskRun"("status", "queuedAt");

-- CreateIndex
CREATE INDEX "TaskRun_taskId_createdAt_idx" ON "TaskRun"("taskId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "TaskRunEvent_runId_seq_key" ON "TaskRunEvent"("runId", "seq");

-- AddForeignKey
ALTER TABLE "TaskRun" ADD CONSTRAINT "TaskRun_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TaskRun" ADD CONSTRAINT "TaskRun_taskId_fkey" FOREIGN KEY ("taskId") REFERENCES "ProjectTask"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TaskRun" ADD CONSTRAINT "TaskRun_botId_fkey" FOREIGN KEY ("botId") REFERENCES "Bot"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TaskRunEvent" ADD CONSTRAINT "TaskRunEvent_runId_fkey" FOREIGN KEY ("runId") REFERENCES "TaskRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- At most one active run per task.
CREATE UNIQUE INDEX "TaskRun_one_active_per_task" ON "TaskRun"("taskId") WHERE "status" IN ('QUEUED', 'RUNNING');
