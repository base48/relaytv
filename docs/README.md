# RelayTV Docs

Use this directory as a small operator/product doc set for the release/install branch.

## Primary Docs

- `INSTALL.md`: installation, first boot, and environment defaults
- `API.md`: HTTP endpoint reference
- `JELLYFIN_OPERATIONS.md`: Jellyfin runtime config, verification, troubleshooting
- `NATIVE_RUNTIME_OPERATIONS.md`: runtime operations, readiness checks, logging, and soak workflow

Development history, migration notes, archived docs, deep validation notes, and engineering-only guidance now live on the `dev` branch instead of the product/install branch.

## Rule

New docs should usually do one of these:

1. extend an existing primary runbook
2. add a narrowly scoped new operator/product doc
3. stay off `main` if they are project notes, plans, migration history, or engineering-only reference material
