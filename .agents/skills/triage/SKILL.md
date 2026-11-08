---
name: triage
description: Triage issues, branches, and pull requests for paperless-mobile using the local SolidCraft-style triage runner and sandbox worktree.
---

# Paperless-Mobile Triage & PR Review Skill

Use this skill whenever the user asks to analyze branches, review open Pull Requests, or triage GitHub issues.

## 1. Golden Rules
1. **Never pollute the main worktree:** Keep the root workspace on `development` (or the current feature branch). Always inspect and test third-party PRs inside `.worktrees/pr-sandbox`.
2. **Use FVM:** Always prefix Flutter/Dart commands with `fvm` (`fvm flutter ...`, `fvm dart ...`).
3. **Target branch is `development`:** All PRs in `astubenbord/paperless-mobile` must rebase cleanly onto `upstream/development`.

## 2. Standard Commands
- **Branch Overview:**
  `python .triage-tools/triage.py overview`
- **Fast PR Triage (Metadata + Area Classification):**
  `python .triage-tools/triage.py prs`
- **Deep PR Verification (Sandbox Rebase + Analyzer):**
  `python .triage-tools/triage.py prs --verify` (or `--verify --pr <NUMBER>` for a single PR)
- **Full Issue Categorization (120+ Issues):**
  `python .triage-tools/triage.py issues`

## 3. Deep-Dive Review Protocol for a Specific PR
When asked to check or review a specific PR `#N`:
1. Run `python .triage-tools/triage.py prs --verify --pr <N>`.
2. Read the generated dossier `.triage-tools/reports/prs/pr_<N>.md` (or inspect `gh pr diff <N> --repo astubenbord/paperless-mobile`).
3. **Always include a contextual Risk-Rule & Architecture Analysis in your response**, even when 0 risk rules triggered. Specifically explain:
   - **Why specific Risk-Rules triggered (or why they rightfully did *not* trigger given the touched files):** Connect the touched areas (e.g., `lib/api/models/`, `lib/core/store/`, `lib/l10n/`, `pubspec.yaml`, `AndroidManifest.xml`, interceptors/auth) to the relevant rules (`API-STRICT-REQUIRED-FIELD`, `STORE-MIGRATION-RISK`, `I18N-CROWDIN-BYPASS`, `FDROID-PROPRIETARY-LIB`, `SEC-*`) and explain *why* the PR's implementation is safe or problematic (e.g., using `@Default(...)` on model fields, keeping only `intl_en.arb` modified, etc.).
   - **Security & Storage Assessment:** Explicitly state whether networking, TLS/certificate handling, or credential/session storage (`FlutterSecureStorage` vs. unencrypted storage) are affected and whether they remain safe.
   - **Analyzer & Unit-Test Breakdown:** Summarize `flutter analyze` results and the execution of any unit/widget test suites (`✅ REBASE_CLEAN & ANALYZE_OK & TESTS_PASSED`).
4. Conclude with a clear verdict for `@astubenbord`: **Ready to merge**, **Needs rebase**, or **Needs changes**.

## 4. Live Progress & Feedback Rules
When executing multi-step triage tasks (such as verifying multiple PRs or scanning all issues):
1. **Announce before executing:** Always write a short chat message *before* launching a heavy script or batch loop (e.g., *"Ich starte jetzt den Sandbox-Check für die PRs #702, #693 und #622. Ich gehe die Schritte nacheinander durch..."*).
2. **Break down batches:** If checking multiple PRs, process them with individual `--pr <ID>` flags or output intermediate findings so the user sees live progress instead of waiting for a single monolithic output.
