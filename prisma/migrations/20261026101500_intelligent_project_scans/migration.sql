CREATE TYPE "ProjectProgressStage" AS ENUM (
    'DISCOVERY',
    'PLANNING',
    'IMPLEMENTATION',
    'BLOCKED',
    'VALIDATION'
);

CREATE TABLE "ProjectScan" (
    "id" TEXT NOT NULL,
    "projectId" TEXT NOT NULL,
    "accountLogin" TEXT NOT NULL,
    "repository" TEXT NOT NULL,
    "branch" TEXT NOT NULL,
    "commitSha" TEXT NOT NULL,
    "lifecycleStage" "ProjectProgressStage" NOT NULL,
    "filesScanned" INTEGER NOT NULL,
    "sourceFiles" INTEGER NOT NULL,
    "testFiles" INTEGER NOT NULL,
    "openItems" INTEGER NOT NULL,
    "taskCounts" JSONB NOT NULL,
    "technologies" TEXT[] NOT NULL,
    "evidenceFiles" TEXT[] NOT NULL,
    "treeTruncated" BOOLEAN NOT NULL DEFAULT false,
    "summary" TEXT NOT NULL,
    "scannedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ProjectScan_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "ProjectScan_projectId_scannedAt_idx" ON "ProjectScan"("projectId", "scannedAt");
CREATE INDEX "ProjectScan_repository_scannedAt_idx" ON "ProjectScan"("repository", "scannedAt");

ALTER TABLE "ProjectScan"
    ADD CONSTRAINT "ProjectScan_projectId_fkey"
    FOREIGN KEY ("projectId") REFERENCES "Project"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
