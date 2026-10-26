# Repository inventory

Audit baseline: branch `feature/github-agent-tasks`, commit `bfd9618`, staging image
`c112795`. The attached 70-page PDF is the target specification; this inventory
records the repository as found before this implementation increment.

## Stack and deployment

- Flutter/Dart client in `mobile/`; routing uses `go_router`, state uses Riverpod,
  HTTP uses Dio, and the web build is served by the Fastify API container.
- TypeScript/Fastify API in `src/`; validation uses Zod, persistence uses Prisma 7
  with PostgreSQL 17.
- Docker Compose separates staging API/database, Caddy proxy, and the
  authenticated code-server workspace. Production is not deployed.
- Database changes use forward-only Prisma migrations. Staging PostgreSQL data is
  persisted in a named Docker volume and has verified custom-format backups.
- The repository has no configured CI workflow or isolated preview runner for
  arbitrary user repositories. GitHub Agent Tasks is used for supported task
  starts; it does not expose pause/resume or worker logs.

## Existing API and data

Prisma models include `User`, `AuthSession`, `GitHubAccount`, `Bot`, `Stage`,
`BackgroundJob`, `PullRequest`, `PullRequestComment`, `Notification`,
`PushDevice`, and `AuditEvent`. Routes in `src/app.ts` cover local auth, GitHub
OAuth/accounts/repositories, bots, Copilot task submission/status, PR comments,
notifications, editor sessions, and stage transitions.

The implementation increment adds durable project/document and pinned
project-scan models. Team, collaboration, schedule, cost, CI run, preview
deployment, and manual-test evidence models are still pending.

## Client surfaces

`mobile/lib/src/app_router.dart` routes the 15 named sections. `AppShell` contains
the desktop sidebar and mobile drawer. Before this increment, several sections
explicitly rendered unsupported-feature notices instead of saving data.
`workspace_pages.dart` contains those section views; `api.dart` and
`providers.dart` hold the shared API client and asynchronous data providers.

## Verification and operation

- Backend: Node test runner, TypeScript `--noEmit`, Prisma schema validation.
- Client: Flutter widget tests, `flutter analyze`, release web build.
- Existing staging: `https://staging.copilotcontrolcenter.com`; `/health/ready`
  returned HTTP 200 at audit time.
- GitHub push authentication is not configured in the current shell. Local
  commits are retained on the feature branch and have not been pushed.
