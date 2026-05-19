---
name: moa-repo-guardrails
description: Repository-level operating rules for MOA. Use before any work in this repository, especially code edits, document updates, rebranding, Firebase changes, release preparation, or impact analysis, to preserve user data, existing behavior, and legacy compatibility.
---

# MOA Repo Guardrails

## Core Rule

Treat user data preservation, existing behavior, and legacy compatibility as higher priority than new features or cleanup.

Before changing files, read the relevant root documents:

- Always read `AGENTS.md`, `CURRENT_PHASE.md`, and `DATA_COMPATIBILITY.md`.
- Read `SKILL.md` for technical workflows and file-specific cautions.
- Read `PROJECT_CONTEXT.md` for product and brand context.
- Read `RELEASE_RULES.md` when release, build, QA, Firebase deploy, or store work is involved.
- Read the most relevant plan under `plans/` when the request touches an existing phase or known risk.

## Workflow

1. Confirm the requested scope and editable files.
2. Classify impact from the viewpoint of user original videos, project metadata, local index, account ownership, subscription/payment state, and cloud sync state.
3. Prefer small changes within one system at a time. Do not combine Flutter UI, Firebase rules, Functions, DB schema, and platform config changes in one task unless explicitly approved.
4. If the request is not a code-change request, edit Markdown only.
5. Prefer deprecated handling, fallback, dual-read/write, or compatibility layers over deletion, rename, or migration.
6. Stop for explicit approval before changing any item listed as approval-required in `AGENTS.md`, `CURRENT_PHASE.md`, or `DATA_COMPATIBILITY.md`.
7. After changes, check for forbidden identifier changes, document conflicts, and validation needs.

## Forbidden Without Approval

Do not change package IDs, Firebase project IDs, Firestore collection names, Storage prefixes, SharedPreferences keys, local file directories, local index schemas, IAP product IDs, `pubspec.lock`, Gradle/iOS platform settings, Firebase config files, or any user data deletion/migration behavior without explicit approval, dry-run, backup, and rollback planning.

Do not weaken Firebase security rules or leave secrets, real user IDs, keystore data, OAuth secrets, or live tokens in code or documentation.

## Completion Report

Report:

- Changed or created files.
- Core source documents reviewed.
- Main operational rule or implementation change.
- Validation commands run and results.
- Why anything was not validated.
- Remaining risk and follow-up approval items.
