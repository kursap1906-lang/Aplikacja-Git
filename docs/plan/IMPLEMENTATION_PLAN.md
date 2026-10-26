# Implementation plan

Implementation is incremental; the application is not considered complete until
the end-to-end acceptance criteria in the attached PDF have evidence.

1. **Audit (complete):** inventory the stack and routes, classify the PDF
   requirements, record risks, and preserve existing deployments.
2. **Projects and documents (active):** project CRUD, owner isolation, bounded
   encrypted PDF upload, text extraction, version history, preview text and
   authenticated download; test and deploy additively.
3. **Teams and task DAG (implemented locally):** durable teams/membership,
   project task ownership and dependencies, and server-side gates. Staging
   migration/verification remains pending.
4. **Collaboration (partial, implemented locally):** owner-authored project
   messages, help requests and manual checkpoint notes. Agent-agent delivery,
   runtime checkpoint capture, and resume remain blocked by the absence of a
   worker coordinator/API.
5. **Operations:** schedule windows and server-side start gates; CSV usage
   import; separate fixed subscriptions from usage costs; budget limits.
6. **Review evidence:** integrate a verified CI provider and isolated preview
   per immutable manifest/SHA; record manual tests and authorization; only then
   consider enabling approval.
7. **AI and integrations:** configure a server-side OpenAI adapter and usage
   metering; maintain integration health and secret handling.
8. **Acceptance:** complete all menu workflows, automated/integration/E2E and
   visual/accessibility checks, migration backup/rollback, staging smoke tests,
   and traceability evidence. Production remains a separate, explicitly
   approved decision.

## Deployment decisions used for this increment

- Existing OVH/Compose/Caddy staging host remains the deployment target.
- PDF bytes are encrypted in the existing persistent PostgreSQL volume; maximum
  upload is 10 MiB. Default retention is one year, subject to a later automated
  purge implementation.
- Costs initially use explicit CSV imports; imported usage is never represented
  as a subscription charge.
- Manual tests must be bound to the exact immutable SHA.
- CI/preview must use GitHub Actions and an isolated, ephemeral environment.
  This is not yet provisioned, so approval remains disabled.
