# Requirement traceability

| Requirement | Implementation | Tests / proof | Status |
|---|---|---|---|
| All 15 destinations | `mobile/lib/src/features/shell/app_shell.dart`, `mobile/lib/src/app_router.dart` | `mobile/test/widget_test.dart` checks 15 routes and mobile “Więcej” entry | Partial; some destinations remain unimplemented |
| Project create and user isolation | `/api/projects` in `src/app.ts`; `Project` Prisma model | Backend API tests; TypeScript check | Implemented locally; staging migration/smoke pending |
| Team membership and bot assignment | `/api/teams` and `/api/teams/:teamId/bots`; `Team`/`TeamBot` models; Teams UI | Backend team ownership test; Flutter team screen widget test | Implemented locally; staging migration/smoke pending |
| Project task dependencies and gates | `/api/tasks` and `/api/tasks/:taskId/dependencies`; `ProjectTask`/`TaskDependency` models | Backend unmet-prerequisite and cycle-rejection tests; Flutter task board widget test | Implemented locally; staging migration/smoke pending |
| Project collaboration messages and help requests | `/api/projects/:projectId/collaboration`, `/messages`, `/help-requests`; owner-scoped `ProjectMessage`/`ProjectHelpRequest` models | Backend create/resolve/list and cross-user access tests; Flutter collaboration screen widget test | Implemented locally; owner-authored only; not delivered to agents; staging migration/smoke pending |
| Manual project checkpoint notes | `/api/projects/:projectId/checkpoints`; `ProjectCheckpoint` model | Backend persistence test; Flutter collaboration widget test | Implemented locally; does not capture/verify worker state or resume tasks; staging migration/smoke pending |
| Intelligent project progress scan and bot context | `/api/projects/:projectId/scan`; `ProjectScan` Prisma model; pinned GitHub commit, repository inventory, progress markers, bot stage-state context | Scanner unit tests and API persistence/access test; Copilot prompt-context regression test | Implemented locally; staging migration/smoke pending; estimate is evidence-based, not an AI assertion |
| PDF upload, encryption and versions | `/api/projects/:projectId/documents`; `Document` and `DocumentVersion` models | Backend encrypted round-trip/version/access regression test | Implemented locally; staging migration/smoke pending |
| PDF text extraction | `pdftotext` isolated process in API image; extraction metadata | Backend injected-parser tests; release image build; staging smoke pending | Implemented locally; OCR unavailable |
| Download only as attachment | `/api/documents/:documentId/versions/:version/download` | Backend response-header and byte round-trip test | Implemented locally; staging migration/smoke pending |
| CI + exact SHA + preview + test approval | Existing stage gate in `src/app.ts` | Existing test verifies approval is blocked | Not complete; gate remains closed |
| Schedules and usage costs | No current service | No acceptance evidence | Not started |

Latest local automated verification: backend 48/48 tests; TypeScript and Prisma
schema validation pass; Flutter 11/11 widget tests and analysis pass. The
latest Flutter Web release build was terminated by the host (dart2js exit -9);
staging migrations and smoke tests have not been run for this increment.
