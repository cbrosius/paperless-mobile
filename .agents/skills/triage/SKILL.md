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
- **Deep Issue Triage & Actionable Sub-Reports:**
  `python .triage-tools/triage.py issues`

## 3. Deep Issue Triage Reports (`.triage-tools/reports/`)
Running `python .triage-tools/triage.py issues` produces an Executive Summary dashboard (`issue_triage.md`) and four specialized, actionable detail reports in `.triage-tools/reports/issues/`:

1. **`1_resolved_by_open_prs.md` (Open PR to Issue Cross-Reference):**
   - Maps open issues to open PRs via explicit references (`fixes #N`, `closes #N`, `related to #N`) and symptom/keyword heuristic rules.
   - Provides ready-to-run `gh issue comment` and `gh issue close` CLI blocks for maintainers once PRs are merged.
2. **`2_duplicate_and_crash_clusters.md` (Crash Signatures & Duplicate Clusters):**
   - Groups recurring bug reports using automated stacktrace extraction (Dart Type/Cast errors, JSON serializer crashes, package frames, Dio network exceptions) and curated keyword clusters (`cluster:saved-views-v3`, `cluster:date-off-by-one-timezone`, `cluster:keyboard-autocorrect-suggestions`, `cluster:network-timeouts-slow-upload`, `cluster:filter-by-owner-permissions`, `cluster:mtls-client-certificates`, `cluster:oidc-oauth-sso`, `cluster:scanner-crop-rotation`).
   - Designates the oldest/most detailed ticket as the **Canonical Master Issue** and outputs ready-to-run `gh issue comment` / `gh issue close` commands to deduplicate tickets.
3. **`3_quick_win_candidates.md` (Actionable Bugs Without Open PRs):**
   - Ranks high-value bugs that do not have an open PR, scored by community upvotes (`👍`), cluster size (+3 pts per duplicate), technical reproducibility (stacktraces, repro steps), and domain scope clarity.
   - Features local codebase file pointers (`lib/`) discovered via `git grep` and detailed mini-dossiers for the Top 5 Quick Wins with concrete Flutter/Dart fix strategies.
4. **`4_stale_and_needs_info.md` (Stale, Outdated & Needs-Info Triage):**
   - Catalogs outdated app versions (`< v4.3.0`) with no activity for $> 180$ days, unanswered maintainer questions ($> 60$ days waiting for user feedback), and incomplete bug reports (`< 150` characters without logs/version).
   - Generates batch `gh issue comment` templates to ping reporters or prepare obsolete issues for closure.

## 4. How the Agent Uses Quick Wins to Fix High-Impact Bugs
When asked to pick, investigate, or implement the next bug fix:
1. Run `python .triage-tools/triage.py issues` to refresh all reports.
2. Open `.triage-tools/reports/issues/3_quick_win_candidates.md` and review the **Top 5 Quick Wins** dossiers.
3. Cross-reference with `.triage-tools/reports/issues/2_duplicate_and_crash_clusters.md` to see all duplicate issues, symptoms, and user reports associated with that bug.
4. Check the suspected source files in `lib/` identified in the dossier and inspect the suggested fix strategy.
5. Create a dedicated feature branch off `upstream/development`, write a reproduction test, implement the fix, run `fvm flutter test` and `fvm flutter analyze`, and format with `black .` if python scripts are modified.

## 5. Deep-Dive Review Protocol for a Specific PR
When asked to check or review a specific PR `#N`:
1. Run `python .triage-tools/triage.py prs --verify --pr <N>`.
2. Read the generated dossier `.triage-tools/reports/prs/pr_<N>.md` (or inspect `gh pr diff <N> --repo astubenbord/paperless-mobile`).
3. **Always include a contextual Risk-Rule & Architecture Analysis in your response**, even when 0 risk rules triggered. Specifically explain:
   - **Why specific Risk-Rules triggered (or why they rightfully did *not* trigger given the touched files):** Connect the touched areas (e.g., `lib/api/models/`, `lib/core/store/`, `lib/l10n/`, `pubspec.yaml`, `AndroidManifest.xml`, interceptors/auth) to the relevant rules (`API-STRICT-REQUIRED-FIELD`, `STORE-MIGRATION-RISK`, `I18N-CROWDIN-BYPASS`, `FDROID-PROPRIETARY-LIB`, `SEC-*`) and explain *why* the PR's implementation is safe or problematic (e.g., using `@Default(...)` on model fields, keeping only `intl_en.arb` modified, etc.).
   - **Security & Storage Assessment:** Explicitly state whether networking, TLS/certificate handling, or credential/session storage (`FlutterSecureStorage` vs. unencrypted storage) are affected and whether they remain safe.
   - **Analyzer & Unit-Test Breakdown:** Summarize `flutter analyze` results and the execution of any unit/widget test suites (`✅ REBASE_CLEAN & ANALYZE_OK & TESTS_PASSED`).
4. Conclude with a clear verdict for `@astubenbord`: **Ready to merge**, **Needs rebase**, or **Needs changes**.

## 6. Live Progress & Feedback Rules
When executing multi-step triage tasks (such as verifying multiple PRs or scanning all issues):
1. **Announce before executing:** Always write a short chat message *before* launching a heavy script or batch loop (e.g., *"Ich starte jetzt den Sandbox-Check für die PRs #702, #693 und #622. Ich gehe die Schritte nacheinander durch..."*).
2. **Break down batches:** If checking multiple PRs, process them with individual `--pr <ID>` flags or output intermediate findings so the user sees live progress instead of waiting for a single monolithic output.
