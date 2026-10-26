CREATE TYPE "SdkMetadataStatus" AS ENUM ('QUEUED', 'RUNNING', 'READY', 'FAILED');

CREATE TABLE "SdkCostPolicy" (
    "userId" TEXT NOT NULL,
    "monthlyExtraLimitMinor" INTEGER NOT NULL,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "SdkCostPolicy_pkey" PRIMARY KEY ("userId"),
    CONSTRAINT "SdkCostPolicy_limit_check" CHECK ("monthlyExtraLimitMinor" >= 0 AND "monthlyExtraLimitMinor" <= 1000000),
    CONSTRAINT "SdkCostPolicy_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE "SdkAccountMetadata" (
    "githubAccountId" TEXT NOT NULL,
    "status" "SdkMetadataStatus" NOT NULL DEFAULT 'QUEUED',
    "leaseToken" UUID,
    "leaseExpiresAt" TIMESTAMPTZ(6),
    "catalog" JSONB,
    "quota" JSONB,
    "fetchedAt" TIMESTAMPTZ(6),
    "requestedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "errorCode" TEXT,
    "errorMessage" TEXT,
    CONSTRAINT "SdkAccountMetadata_pkey" PRIMARY KEY ("githubAccountId"),
    CONSTRAINT "SdkAccountMetadata_githubAccountId_fkey" FOREIGN KEY ("githubAccountId") REFERENCES "GitHubAccount"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX "SdkAccountMetadata_status_requestedAt_idx" ON "SdkAccountMetadata"("status", "requestedAt");
CREATE UNIQUE INDEX "SdkAccountMetadata_one_running" ON "SdkAccountMetadata"((true)) WHERE "status" = 'RUNNING';
