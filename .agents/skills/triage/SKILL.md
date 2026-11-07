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
When asked to deeply review a specific PR `#N`:
1. Run `python .triage-tools/triage.py prs --verify --pr <N>`.
2. Inspect the diff via `gh pr diff <N> --repo astubenbord/paperless-mobile`.
3. Check inside `.worktrees/pr-sandbox`:
   - If the PR modifies models, API specs (`specs/`), or state classes, verify if code generation is needed: `fvm dart run build_runner build --delete-conflicting-outputs`.
   - If the PR modifies `.arb` localization files, verify only the base language (`app_en.arb` / `app_de.arb`) is changed unless translations come from Crowdin.
   - Run relevant tests: `fvm flutter test`.
4. Draft a concise, constructive GitHub review comment summarizing:
   - Rebase status against `upstream/development`
   - Analyzer & test results
   - Code quality / architecture notes
   - Clear verdict for `@astubenbord`: **Ready to merge**, **Needs rebase**, or **Needs changes**.