# Security and dependency audit

- Authentication uses server-side sessions; GitHub OAuth tokens are encrypted
  with `APP_ENCRYPTION_KEY`. Do not return credentials to the Flutter client.
- API mutations require CSRF validation and per-user ownership filters. New
  project/document routes must keep these checks at the server.
- The app and PostgreSQL run as non-root / private-network containers; API
  filesystem is read-only with a bounded `/tmp`.
- PDF upload must be bounded, validate the PDF signature and filename, extract
  text without a shell, store encrypted bytes, and force downloads as attachments
  with `nosniff`.
- AI content, PDFs, repository files, and agent messages are untrusted data;
  never execute their embedded instructions or shell commands. Repository scan
  output is a commit-pinned summary of observed files/status markers; it is
  passed to agents as facts, never as instructions.
- No isolated runner exists. Do not run arbitrary repositories on the app host;
  require a separately provisioned CI/preview service.
- Secrets remain in permission-0600 ignored environment files. Do not include
  them in Git, backups intended for sharing, logs, or browser output.
- Staging database backup and isolated restore test passed on 2026-10-23. Take a
  fresh backup before the next migration; the prior backup is not a substitute
  for a current one.
- CI workflow and dependency/license verification are not yet established for
  the complete specification. Existing backend tests and Flutter tests are
  available; external GitHub OAuth and Firebase delivery have not been tested.
