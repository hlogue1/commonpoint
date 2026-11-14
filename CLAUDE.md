# CommonPoint — Claude Code instructions

Current focus: the **terminology service** (`cmd/terms`) and everything it needs. Start with `docs/PLAN.md`
(scope, verified findings T*/R*, milestones M0–M8), and work the milestones in order. Tick checkboxes in
the same commit as the work.

**Out of scope, don't modify:** `migrations/##-cp-core-*.sql`, anything build-related (`cmd/ctl/cli/build`,
the `build` schema, the Doltgres `build-db`), and the IdP itself (`deploy/id`, `cmd/idp`,
`internal/modules/idp`). The terms service is an OAuth2 *resource server* for the CommonPoint clinical IdP,
which runs as an outside service. Validating its tokens is in scope; building or changing the IdP is not.
The terms service runs on PostgreSQL 18 only (no Doltgres). If a task seems to need an out-of-scope change,
stop and ask.

@docs/terms/CLAUDE.md

## Repo-wide rules
- Conventional Commits, scoped (`fix(terms-schema): T2 …`, `feat(ctl-terms): …`). Reference the finding ID when fixing one.
- Migrations: tern format (`NNN_name.sql`, `---- create above / drop below ----` with real down SQL).
  Applied migrations are never edited, only followed by new ones.
- Every migration change keeps the migration tests (up → down → up on PostgreSQL 18) green.
- Container images are pinned. Never `:latest`.
- No secrets in the repo.
- Ask before deciding anything about licensing of terminology content.
