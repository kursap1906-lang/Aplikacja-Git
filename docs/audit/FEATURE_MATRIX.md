# PDF feature matrix

Status is based on code and deployed behavior, not the PDF's illustrative
screenshots. `Partial` means some backend-backed behavior exists but the PDF
acceptance criteria are not met.

| Requirement | Status at audit | Evidence / gap |
|---|---|---|
| F-001 Login, sessions, organizations, RBAC | Partial | `src/app.ts` implements local sessions and OAuth; no organization membership or RBAC model. |
| F-002 Organization dashboard, activity, budget | Partial | `mobile/lib/src/features/dashboard/dashboard_page.dart` uses bot/stage data; no organization KPI, costs, credits, or help counts. |
| F-003 Team builder and membership | Partial | Owner-scoped Team and TeamBot models/API plus Flutter team/bot assignment UI; staging migration and broader organizational roles are not complete. |
| F-004 Agent registry and role/capability catalog | Partial | Bot CRUD exists; role registry, tools policy, model/usage limits do not. |
| F-005 Agent sessions, checkpoint, pause/resume, logs | Missing/blocked | GitHub Agent Tasks API lacks these controls; no worker/session store. User-authored project notes are not runtime checkpoints. |
| F-006 Projects and PDF versions/extraction | Partial | Project/PDF API and UI support owner-isolated projects, encrypted versioned uploads (10 MiB limit), text extraction via `pdftotext`, and attachment downloads. Staging migration/smoke test pending. |
| F-007 Missions/tasks/DAG | Partial | Owner-scoped project tasks and dependency edges exist; API rejects cycles and blocks start/completion with unfinished prerequisites. Staging migration and broader mission workflow remain pending. |
| F-008 Team context and project memory | Partial | Commit-pinned project scans persist repository inventory and progress-marker counts; the latest scan for the same repository is added to Copilot task context. No general team memory/retrieval store. |
| F-009 Agent messages/help requests | Partial | Owner-authored project log and durable help requests exist; messages are not delivered to agents and no agent-to-agent channel/coordinator exists. |
| F-010 Protect main task and worktree isolation | Missing/blocked | No coordinator or worktree service. |
| F-011 Checkpoints and resume | Partial/blocked | Manually authored project notes can be saved, optionally with an unverified SHA reference; worker state capture and resume are unavailable. |
| F-012 Delegation policies | Missing | No policy engine. |
| F-013 Git branches, commit/PR, conflicts | Partial | GitHub repositories/PR/comments are available; no workspace Git service. |
| F-014 Integration manifest and SHA build | Missing | No CI or immutable review manifest. |
| F-015 Code Center | Partial | Authenticated code-server opens; selected project/repository/branch isolation is not wired. |
| F-016 SHA-bound Review Center | Partial | Review UI and server-side approval block exist; no CI, preview, or manual-test evidence store. |
| F-017 Release and rollback | Missing/blocked | No approved release pipeline; production is intentionally not deployed. |
| F-018 OpenAI planning/writing | Missing | No server-side OpenAI adapter or key configuration. |
| F-019 Schedules and working windows | Missing | `/schedule` showed an unsupported notice; no scheduler or start gate. |
| F-020 Costs, budgets, subscription split | Missing | `/costs` showed an unsupported notice; no usage import or budget policy. |
| F-021 Notifications | Partial | Persistent in-app notifications exist; push delivery requires Firebase configuration. |
| F-022 Audit | Partial | Critical existing auth/bot/stage actions are recorded; no complete audit scan/report or tenant event correlation. |
| F-023 Integration manager | Partial | GitHub OAuth is implemented; no integration health registry for OpenAI, CI, storage, or preview. |
| F-024 PWA and accessibility | Partial | Responsive Flutter web and semantics exist; no complete WCAG/visual regression evidence. |

## UI destination status

All 15 routes exist, but route existence is not feature completion. Bot/account,
repository, task/stage, PR, notification, and editor screens are partly backed
by existing APIs. Projects/PDF and evidence-based repository progress scans now have local
implementations awaiting staging verification. Teams and project-task dependencies have
local persistent services. Project collaboration entries are owner-authored only;
agent-agent coordination, runtime checkpoints, schedules, and costs are not
implemented. Review approval is intentionally closed.
