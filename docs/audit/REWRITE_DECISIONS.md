# Rewrite and migration decisions

| Area | Decision | Rationale and migration |
|---|---|---|
| Flutter app and Fastify API | Keep and extend | They are deployed and tested. Add backward-compatible routes and additive Prisma migrations instead of a platform rewrite. |
| Existing `Bot` / `Stage` models | Keep | Existing data and Copilot task flow remain the source for current agents. Add project/team/task relations only with migrations and ownership checks. |
| Projects/PDF | Add durable service | Encrypt PDF bytes with the existing AES-256-GCM key, keep version metadata and extracted text in PostgreSQL, and serve files only as attachments after owner checks. |
| Review approval | Keep closed | No verifiable CI/preview/manual evidence provider exists yet. Do not weaken the server gate to make the UI appear complete. |
| GitHub task controls | Keep capability limits visible | The upstream API does not provide pause/resume/logs; do not simulate these actions. |
| CI/preview | Defer external execution | Requires an approved isolated runner and preview host. A shared host or application container is not a safe substitute. |
| Production deployment | Do not change | Work is staged on the existing staging host only. Back up the staging database before each schema migration. |

