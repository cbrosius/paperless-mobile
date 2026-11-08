# Paperless-Mobile Triage & PR Verification Tool

[`.triage-tools/triage.py`](./triage.py) is a lightweight, zero-dependency Python 3 CLI for triaging upstream branches, open Pull Requests, and GitHub issues in [`astubenbord/paperless-mobile`](https://github.com/astubenbord/paperless-mobile) without polluting your primary working tree.

---

## 1. Environment Setup

### Prerequisites
1. **Python 3.10+** (uses only the Python standard library; no `pip install` needed).
2. **GitHub CLI (`gh`)** installed and authenticated:
   ```powershell
   gh auth status
   # If not logged in:
   gh auth login
   ```
3. **FVM (Flutter Version Management)** installed so `fvm dart analyze` and `fvm flutter test` use the project's pinned Flutter SDK:
   ```powershell
   fvm install
   ```

### Configure the `upstream` Git Remote
The tool fetches branches and PR refs from a remote named `upstream` pointing to `astubenbord/paperless-mobile`:

```powershell
git remote add upstream https://github.com/astubenbord/paperless-mobile.git
git fetch upstream --prune
```
*(If `upstream` already exists, verify it with `git remote -v`.)*

### Create the Sandbox Worktree (`.worktrees/pr-sandbox`)
To verify Pull Requests (rebase check + `fvm dart analyze`) without touching your main working directory, create an isolated Git worktree inside `.worktrees/pr-sandbox` and bootstrap its dependencies once:

```powershell
# 1. Create the detached sandbox worktree from upstream/development
git worktree add --detach .worktrees/pr-sandbox upstream/development

# 2. Initialize submodules and Dart/Flutter packages inside the sandbox
Push-Location .worktrees/pr-sandbox
git submodule update --init --recursive
fvm flutter pub get
Pop-Location
```

> **Note:** Both `.worktrees/` and `.triage-tools/reports/` are git-ignored so sandbox checkouts and generated Markdown reports never clutter your commits.

---

## 2. Usage

Run all commands from the **repository root**:

### A. Upstream Branch Overview (`overview`)
Fetches the latest `upstream` refs and compares every upstream branch against `upstream/development` (ahead/behind commit counts and last commit date):

```powershell
python .triage-tools/triage.py overview
```
- **Output:** Prints a summary table to the terminal and writes `.triage-tools/reports/branch_overview.md`.

### B. Fast Pull Request Triage (`prs`)
Lists open PRs from `astubenbord/paperless-mobile`, classifies touched areas (`area:scanner`, `area:api`, `area:auth`, `area:documents`, etc.), and preserves any previously recorded sandbox verification results:

```powershell
python .triage-tools/triage.py prs
```
- **Output:** Updates `.triage-tools/reports/pr_triage.md`.

### C. Deep PR Verification in Sandbox (`prs --verify`)
For each targeted PR, fetches `pull/<ID>/head` into `.worktrees/pr-sandbox` and performs an automated 7-step verification pipeline:
1. Fetches the latest PR head from `upstream`.
2. Rebases the PR branch onto `upstream/development`.
3. **Scans the rebased diff for security, F-Droid compliance, and architectural risks** (14 rules: `SEC-TLS-BYPASS`, `FDROID-PROPRIETARY-LIB`, `SEC-LOG-CREDENTIALS`, `SEC-MANIFEST-PERM`, `REPO-SUBMODULE-DRIFT`, `NET-HTTP-OVERRIDES`, `I18N-CROWDIN-BYPASS`, `STORE-MIGRATION-RISK`, `API-STRICT-REQUIRED-FIELD`, `CI-PIPELINE-OR-SIGNING`, `SUPPLY-UNPINNED-GIT-DEP`, `SEC-INSECURE-CREDENTIAL-STORAGE`, `SEC-WEBVIEW-OR-CLEARTEXT`, `PERF-SYNC-FILE-IO`).
4. Ensures `.dart_tool/package_config.json` is present (running `fvm flutter pub get` automatically if missing or if any `pubspec` file changed).
5. Runs `fvm flutter gen-l10n` (when `.arb` files changed) and/or `fvm dart run build_runner build --delete-conflicting-outputs` (when `models/`, `specs/`, `cubit`, `bloc`, `store/`, or `routes/` files changed).
6. Runs `fvm flutter analyze --no-pub` on all modified `.dart` files.
7. Runs `fvm flutter test` automatically on any modified `test/**/*_test.dart` files.

```powershell
# Verify a single PR:
python .triage-tools/triage.py prs --verify --pr 703

# Verify multiple specific PRs in one run:
python .triage-tools/triage.py prs --verify --pr 703 702 695

# Verify all open PRs:
python .triage-tools/triage.py prs --verify
```
- **Outputs:**
  - Updates the `Sandbox Check` column in `.triage-tools/reports/pr_triage.md` (`✅ REBASE_CLEAN & ANALYZE_OK`, `✅ REBASE_CLEAN (non-Dart PR)`, `⚠️ REBASE_CLEAN / ANALYZE_ISSUES`, or `❌ REBASE_CONFLICT`).
  - Writes a per-PR dossier to `.triage-tools/reports/prs/pr_<NUMBER>.md` containing the PR metadata, description, touched files, rebase/analyzer output, and full diff.

### D. Issue Categorization (`issues`)
Fetches up to 200 open issues, groups them by inferred functional area, and flags `needs-info` candidates (short descriptions or missing version details):

```powershell
python .triage-tools/triage.py issues
```
- **Output:** Writes `.triage-tools/reports/issue_triage.md`.

---

## 3. Generated Reports Structure

All generated artifacts live under `.triage-tools/reports/`:

```text
.triage-tools/
├── triage.md                  # This documentation
├── triage.py                  # Triage CLI script
└── reports/                   # (git-ignored)
    ├── branch_overview.md     # Upstream branch comparison table
    ├── pr_triage.md           # Open PR overview + sandbox status table
    ├── issue_triage.md        # Open issues grouped by area + needs-info list
    └── prs/
        └── pr_<NUMBER>.md     # Detailed per-PR review dossier & diff
```

