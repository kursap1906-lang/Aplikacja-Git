CREATE TYPE "AiAnalysisKind" AS ENUM ('TEAM_TASKS', 'REPOSITORY_CONTEXT', 'DIAGNOSTIC');
CREATE TYPE "AiAnalysisStatus" AS ENUM ('QUEUED', 'RUNNING', 'COMPLETED', 'FAILED', 'UNKNOWN');

CREATE TABLE "AiBudgetPeriod" (
    "month" VARCHAR(7) NOT NULL,
    "reservedMicros" INTEGER NOT NULL DEFAULT 0,
    "spentMicros" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "AiBudgetPeriod_pkey" PRIMARY KEY ("month"),
    CONSTRAINT "AiBudgetPeriod_limits_check" CHECK (
        "month" ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
        AND "reservedMicros" >= 0 AND "spentMicros" >= 0
        AND "reservedMicros" + "spentMicros" <= 10000000
    )
);

CREATE TABLE "AiAnalysis" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "projectId" TEXT,
    "teamId" TEXT,
    "kind" "AiAnalysisKind" NOT NULL,
    "status" "AiAnalysisStatus" NOT NULL DEFAULT 'QUEUED',
    "requestKey" UUID NOT NULL,
    "inputFingerprint" VARCHAR(64) NOT NULL,
    "model" TEXT NOT NULL,
    "budgetMonth" VARCHAR(7) NOT NULL,
    "reservedCostMicros" INTEGER NOT NULL DEFAULT 1000000,
    "estimatedCostMicros" INTEGER,
    "inputTokens" INTEGER,
    "cachedTokens" INTEGER,
    "outputTokens" INTEGER,
    "providerResponseId" TEXT,
    "providerStartedAt" TIMESTAMPTZ(6),
    "leaseToken" UUID,
    "leaseExpiresAt" TIMESTAMPTZ(6),
    "result" JSONB,
    "errorCode" TEXT,
    "errorMessage" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,
    "finishedAt" TIMESTAMPTZ(6),
    CONSTRAINT "AiAnalysis_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "AiAnalysis_limits_check" CHECK (
        "reservedCostMicros" >= 0 AND "reservedCostMicros" <= 1000000
        AND ("estimatedCostMicros" IS NULL OR
             ("estimatedCostMicros" >= 0 AND "estimatedCostMicros" <= "reservedCostMicros"))
        AND "inputFingerprint" ~ '^[a-f0-9]{64}$'
    ),
    CONSTRAINT "AiAnalysis_scope_check" CHECK (
        ("kind" = 'TEAM_TASKS' AND "projectId" IS NOT NULL AND "teamId" IS NOT NULL)
        OR ("kind" = 'REPOSITORY_CONTEXT' AND "projectId" IS NOT NULL AND "teamId" IS NULL)
        OR ("kind" = 'DIAGNOSTIC' AND "projectId" IS NULL AND "teamId" IS NULL)
    ),
    CONSTRAINT "AiAnalysis_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "AiAnalysis_projectId_fkey" FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "AiAnalysis_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "AiAnalysis_budgetMonth_fkey" FOREIGN KEY ("budgetMonth") REFERENCES "AiBudgetPeriod"("month") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "AiAnalysis_userId_requestKey_key" ON "AiAnalysis"("userId", "requestKey");
CREATE INDEX "AiAnalysis_status_createdAt_idx" ON "AiAnalysis"("status", "createdAt");
CREATE INDEX "AiAnalysis_userId_createdAt_idx" ON "AiAnalysis"("userId", "createdAt");
CREATE INDEX "AiAnalysis_projectId_createdAt_idx" ON "AiAnalysis"("projectId", "createdAt");
CREATE INDEX "AiAnalysis_teamId_createdAt_idx" ON "AiAnalysis"("teamId", "createdAt");
CREATE UNIQUE INDEX "AiAnalysis_one_active_per_user" ON "AiAnalysis"("userId") WHERE "status" IN ('QUEUED', 'RUNNING');
CREATE UNIQUE INDEX "AiAnalysis_one_running_globally" ON "AiAnalysis"((true)) WHERE "status" = 'RUNNING';
