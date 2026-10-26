# Gap analysis

## P0 — safety and trustworthy state

- Stage approval must remain disabled until CI, preview, manual tests, reviewer
  permission, and the exact commit SHA are verified by the server.
- No isolated CI/preview service exists. Do not execute uploaded/user repository
  code inside the application or database containers.
- The application has no organization/RBAC boundary beyond per-user ownership.
- PDF content is untrusted input and must never be executed or used as shell
  instructions.

## P1 — core workflow gaps

- Projects/PDF documents now have local persistence, owner-scoped access,
  versions, text extraction, and authenticated downloads; source citations,
  automated retention, and staging verification remain missing.
- Teams and project task DAGs now have local persistence and server-side
  ownership/dependency checks. Project messages/help requests and manual notes
  persist, but agent-agent delivery, runtime checkpoints, resume, and coordinator
  state remain missing.
- Schedule and budget controls do not gate task starts; there is no cost ledger
  or separation of subscription and usage charges.
- Review Center lacks immutable SHA manifests, verified CI checks, preview
  deployments, manual-test records, and approval history.

## P2 — integrations and operations

- OpenAI generation, usage attribution, model costs, and settings are absent.
- Git workspaces, branch selection, conflict handling, commit/PR creation, and
  integration/release pipelines are absent.
- Push notifications need Firebase; audit coverage and activity correlation are
  incomplete.
- Mobile navigation should match the PDF's compact bottom shortcuts plus a
  discoverable “More” menu.

## P3 — acceptance evidence

- The PDF requires end-to-end desktop/mobile flows, screen-reader/keyboard
  checks, visual regression screenshots, CI/deployment evidence, rollback tests,
  and a traceability report. These do not exist as a complete suite.
