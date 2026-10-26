ALTER TABLE "ProjectTask" ADD COLUMN "githubStageId" TEXT;
CREATE UNIQUE INDEX "ProjectTask_githubStageId_key" ON "ProjectTask"("githubStageId");
ALTER TABLE "ProjectTask" ADD CONSTRAINT "ProjectTask_githubStageId_fkey"
  FOREIGN KEY ("githubStageId") REFERENCES "Stage"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
