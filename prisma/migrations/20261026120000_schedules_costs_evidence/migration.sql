-- CreateEnum
CREATE TYPE "ReviewEvidenceKind" AS ENUM ('MANUAL_TEST', 'PREVIEW');

-- CreateEnum
CREATE TYPE "ReviewEvidenceResult" AS ENUM ('PASSED', 'FAILED');

-- CreateEnum
CREATE TYPE "CostCategory" AS ENUM ('USAGE', 'SUBSCRIPTION');

-- CreateTable
CREATE TABLE "ReviewEvidence" (
    "id" TEXT NOT NULL,
    "pullRequestId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "commitSha" TEXT NOT NULL,
    "kind" "ReviewEvidenceKind" NOT NULL,
    "result" "ReviewEvidenceResult" NOT NULL,
    "note" TEXT NOT NULL,
    "url" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ReviewEvidence_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WorkSchedule" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "timezone" TEXT NOT NULL DEFAULT 'UTC',
    "windows" JSONB NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "WorkSchedule_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CostBudget" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "monthlyLimitMinor" INTEGER NOT NULL,
    "currency" VARCHAR(3) NOT NULL,
    "enforce" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CostBudget_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CostEntry" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "occurredOn" DATE NOT NULL,
    "category" "CostCategory" NOT NULL,
    "amountMinor" INTEGER NOT NULL,
    "currency" VARCHAR(3) NOT NULL,
    "description" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CostEntry_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ReviewEvidence_pullRequestId_commitSha_kind_idx" ON "ReviewEvidence"("pullRequestId", "commitSha", "kind");

-- CreateIndex
CREATE UNIQUE INDEX "WorkSchedule_userId_key" ON "WorkSchedule"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "CostBudget_userId_key" ON "CostBudget"("userId");

-- CreateIndex
CREATE INDEX "CostEntry_userId_occurredOn_idx" ON "CostEntry"("userId", "occurredOn");

-- AddForeignKey
ALTER TABLE "ReviewEvidence" ADD CONSTRAINT "ReviewEvidence_pullRequestId_fkey" FOREIGN KEY ("pullRequestId") REFERENCES "PullRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReviewEvidence" ADD CONSTRAINT "ReviewEvidence_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WorkSchedule" ADD CONSTRAINT "WorkSchedule_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CostBudget" ADD CONSTRAINT "CostBudget_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CostEntry" ADD CONSTRAINT "CostEntry_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
