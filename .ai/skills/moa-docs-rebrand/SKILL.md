---
name: moa-docs-rebrand
description: Documentation, branding, and user-facing copy workflow for MOA. Use when editing Markdown, plans, README, benchmark docs, release notes, app display copy, manifest strings, or rebranding text from legacy Three Sec/3s/One Second wording to MOA while preserving legacy identifiers.
---

# MOA Docs Rebrand

## Required Context

Read `PROJECT_CONTEXT.md`, `CURRENT_PHASE.md`, `AGENTS.md`, and `DATA_COMPATIBILITY.md`. For rebrand phase decisions, prefer `plans/archive/moa_rebrand_phase_plan_interactive_v1.html` when present.

## Brand Rules

- Use `MOA` for user-facing brand.
- Use `2초 촬영 + Vlog` for product description.
- Avoid spreading user-facing legacy names such as `원세컨`, `One Second Vlog`, `1s Vlog`, `Three Sec Vlog`, and `3s`.
- Preserve legacy identifiers used for compatibility, including `three_sec_vlog`, `three_s`, `com.dk.three_sec`, `fir-3s-8edb9`, `3s_*`, `vlog_projects`, and `vlog_folders`.

## Documentation Workflow

1. Classify the document as policy, procedure, current scope, architecture, data compatibility, release, issue, or historical plan.
2. Use real file names, service names, keys, paths, and validation commands.
3. Separate user-facing brand language from internal legacy identifiers.
4. Keep historical documents as legacy/as-is records unless the request explicitly asks to revise them.
5. Do not delete old plans or rewrite broad archives just to make branding uniform.
6. For code-change-related docs, state forbidden targets, approval-required targets, validation commands, and rollback criteria.
7. After edits, check for conflicts with `AGENTS.md`, `DATA_COMPATIBILITY.md`, and `RELEASE_RULES.md`.

## Current Phase Boundary

Allowed by default:

- Markdown operating document cleanup.
- User-facing copy alignment to MOA.
- Low or medium impact UI text cleanup.
- Validation checklist, release gate, and known issue documentation.

Approval required:

- Package/bundle ID changes.
- Firebase project/schema/path/rules changes.
- Storage or local file path changes.
- SharedPreferences key changes.
- IAP product ID changes.
- Mass rename, migration, backfill, purge, or user data deletion.
