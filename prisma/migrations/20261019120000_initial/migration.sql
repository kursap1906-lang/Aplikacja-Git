-- Bind short-lived mobile sessions to the OAuth state before exchanging them.
-- Any pending handoff created before this change must be re-authorized.
ALTER TABLE "OAuthHandoff"
ADD COLUMN "stateHash" TEXT NOT NULL DEFAULT '';

UPDATE "OAuthHandoff"
SET "consumedAt" = CURRENT_TIMESTAMP
WHERE "consumedAt" IS NULL;

ALTER TABLE "OAuthHandoff"
ALTER COLUMN "stateHash" DROP DEFAULT;

CREATE INDEX "OAuthHandoff_stateHash_consumedAt_idx"
ON "OAuthHandoff"("stateHash", "consumedAt");

CREATE TABLE "PullRequestComment" (
    "id" TEXT NOT NULL,
    "pullRequestId" TEXT NOT NULL,
    "githubCommentId" TEXT NOT NULL,
    "authorLogin" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "htmlUrl" TEXT NOT NULL,
    "postedAt" TIMESTAMPTZ(6) NOT NULL,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "PullRequestComment_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "PullRequestComment_pullRequestId_postedAt_idx"
ON "PullRequestComment"("pullRequestId", "postedAt");

CREATE UNIQUE INDEX "PullRequestComment_pullRequestId_githubCommentId_key"
ON "PullRequestComment"("pullRequestId", "githubCommentId");

ALTER TABLE "PullRequestComment"
ADD CONSTRAINT "PullRequestComment_pullRequestId_fkey"
FOREIGN KEY ("pullRequestId") REFERENCES "PullRequest"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
