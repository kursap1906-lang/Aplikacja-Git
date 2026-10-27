ALTER TABLE "Team" ADD COLUMN "roadmap" JSONB NOT NULL DEFAULT '[]';
WITH roots AS (
  SELECT m."id", m."teamId",
    FIRST_VALUE(m."id") OVER (PARTITION BY m."teamId" ORDER BY
      CASE WHEN b."name" ILIKE '%lead%' OR b."name" ILIKE '%lider%' THEN 0 ELSE 1 END,
      m."createdAt", m."id") AS leader
  FROM "TeamBot" m JOIN "Bot" b ON b."id" = m."botId"
  WHERE m."parentId" IS NULL
)
UPDATE "TeamBot" m SET "parentId" = roots.leader FROM roots
WHERE m."id" = roots."id" AND m."id" <> roots.leader;
CREATE TABLE "TeamExecution" (
  "id" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "state" TEXT NOT NULL,
  "data" JSONB NOT NULL,
  "leaseUntil" TIMESTAMPTZ(6),
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL,
  CONSTRAINT "TeamExecution_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "TeamExecution_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX "TeamExecution_teamId_createdAt_idx" ON "TeamExecution"("teamId", "createdAt");
CREATE INDEX "TeamExecution_state_leaseUntil_idx" ON "TeamExecution"("state", "leaseUntil");
CREATE UNIQUE INDEX "TeamExecution_one_active_team" ON "TeamExecution"("teamId") WHERE "state" NOT IN ('STOPPED', 'RELEASED');
