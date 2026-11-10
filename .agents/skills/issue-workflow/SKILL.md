---
name: issue-workflow
description: Systematically triage, reproduce, fix, test, and prepare PR drafts for issues in paperless-mobile following strict fork-only, git notes, and verification rules. Use when diagnosing, fixing, or preparing pull request drafts for GitHub issues.
---

# Issue Resolution Workflow Skill

## Overview

This skill defines the standardized end-to-end workflow for resolving issues in the `paperless-mobile` repository. It covers fetching issue details, branching, diagnosing root causes, implementing robust fixes, verifying via unit and emulator integration tests, committing, creating detached PR drafts via Git Notes, and pushing exclusively to the user's fork.

---

## Strict Constraints & Core Rules

1. **Upstream PR Protection:**
   - **NEVER** push branches or create Pull Requests directly against upstream (`astubenbord/paperless-mobile`).
   - Push branches **only** to the user's fork (`origin = https://github.com/cbrosius/paperless-mobile.git`).
   - Upstream maintainers must decide when/if to accept PRs; no PR should appear in upstream without explicit user confirmation.

2. **PR Draft Preservation via Git Notes:**
   - Every completed fix must include a comprehensive PR draft.
   - Save the PR draft markdown locally in `.git/pr-drafts/issue-<number>.md`.
   - Attach the draft directly to the commit object via Git Notes:
     ```powershell
     git notes add -f -F .git/pr-drafts/issue-<number>.md HEAD
     ```
   - Push Git Notes to the user's fork:
     ```powershell
     git push origin refs/notes/*
     ```
   - This keeps the PR draft permanently associated with the commit without polluting repo files or creating premature upstream PRs.

3. **No Ephemeral Test Files in Branches:**
   - Temporary on-device / on-emulator integration tests (`integration_test/temp_*.dart`) may be used to verify fixes on the Android Emulator or physical device.
   - **All temporary integration test files MUST be deleted before staging and committing.**

4. **Code Quality & Formatting:**
   - Source code comments, console logs, and commit messages must always be in **English**.
   - Format modified Dart files with `fvm dart format <files>`.
   - Run `black .` after any Python changes.
   - Run `fvm flutter analyze lib/` (0 errors required).
   - If `git commit` hangs due to `commit.gpgsign=true` without a running SSH agent in background tasks, pass `--no-gpg-sign`.

5. **Visual/UI Bug Screenshot Comparison (Before & After):**
   - For issues involving visual defects, rendering glitches, broken layouts, alignment problems, missing UI controls, or theming/dark mode bugs:
     - **Before Fix:** Capture a screenshot from inside the running app on the simulator/emulator reproducing the bug (`issue-<number>-before.png`).
     - **After Fix:** Capture a screenshot from inside the running app on the simulator/emulator displaying the resolved state on the exact same screen (`issue-<number>-after.png`).
     - **In-App Screen Requirement:** Screenshots must show the actual application UI exhibiting the bug/fix — **never** the launcher desktop, lock screen, or transition screen.
     - **Consistent Framing & Soft Keyboard:** Keep both before and after screenshots identically framed. Dismiss or disable the soft keyboard (e.g., `autofocus: false` or `adb shell input keyevent 111`) so bottom controls and lists are not obscured.
     - **Capturing While App is Active:** Screenshots must be taken *while the app or integration test is actively running and displaying the screen* — never after the test process has already terminated and returned to the OS launcher.
     - **Robust Capture via adb:** Use direct on-device capture and `adb pull` to avoid Windows PowerShell piping, encoding, and file-lock issues:
       ```powershell
       adb shell screencap -p /data/local/tmp/screen.png
       adb pull /data/local/tmp/screen.png .git/screenshots/issue-<number>-<state>.png
       adb shell rm /data/local/tmp/screen.png
       ```
     - Save screenshots locally in `.git/screenshots/` so they remain untracked.
     - Always inspect the captured image files using `read_file` to verify they display the intended app screen.
     - Provide a clear before-and-after visual comparison in the PR draft and user status report.

---

## Step-by-Step Workflow

### Step 1: Fetch and Analyze the Issue

Inspect the issue description, discussion comments, and device/version metadata using the GitHub CLI:

```powershell
gh issue view <issue-number> --repo astubenbord/paperless-mobile --comments
```

Identify:
- Exact error messages, stack traces, and affected components.
- Conditions under which the bug occurs (e.g. locale, Android/iOS version, permissions, network state).
- Community workarounds or hints provided in the thread.

### Step 2: Set Up a Clean Working Branch

Sync the base development branch with upstream and create an isolated fix branch:

```powershell
git checkout development
git pull upstream development
git checkout -b fix/<short-issue-description>
```

### Step 3: Root Cause Analysis

1. Locate referenced source code files and trace the call hierarchy.
2. Check for missing permission checks, unhandled exceptions, type-mismatches, unsafe null assertions (`!`), or hardcoded lists.
3. Check git history/blame on affected sections to understand author intent:
   ```powershell
   git log -L <start>,<end>:<file>
   ```
4. **Visual/UI Bugs Pre-Fix Capture:**
   - If the issue is a visual defect (layout overflow, alignment error, broken styling, font/icon glitch, missing UI control, dark/light mode bug), reproduce the bug on the emulator.
   - **Crucial Requirement:** The screenshot must capture the **active app screen** showing the defect, never the emulator desktop or launcher.
   - Ensure the screenshots directory exists:
     ```powershell
     if (-not (Test-Path .git\screenshots)) { New-Item -ItemType Directory -Path .git\screenshots }
     ```
   - Capture directly on-device while the app is actively in the foreground displaying the buggy UI, then pull the file:
     ```powershell
     adb shell screencap -p /data/local/tmp/before.png
     adb pull /data/local/tmp/before.png .git/screenshots/issue-<issue-number>-before.png
     adb shell rm /data/local/tmp/before.png
     ```
   - Inspect the screenshot via the `read_file` tool to confirm that the app screen is properly captured.

### Step 4: Implementation

- Apply clean, defensive, and modular changes.
- Ensure fallback behavior (e.g. graceful fallbacks on unexpected/null inputs instead of crashing the app).
- Maintain documentation integrity and keep existing comments intact.

### Step 5: Verification & Testing

1. **Unit Tests:**
   - Write comprehensive tests in `test/src/...` reproducing the issue before and proving the fix after.
   - Run unit tests:
     ```powershell
     fvm flutter test <path-to-test>
     ```
2. **Android Emulator / Device Verification (when applicable):**
   - Check if the emulator is running: `adb devices`. If not, start it:
     ```powershell
     & "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd Medium_Phone_API_37.0 -no-snapshot-load
     ```
   - For on-device verification, write a temporary integration test: `integration_test/temp_<name>_test.dart`.
   - Execute on the device:
     ```powershell
     fvm flutter test integration_test/temp_<name>_test.dart -d emulator-5554
     ```
   - **Immediately delete the temporary file after verification:**
     ```powershell
     Remove-Item -Force integration_test/temp_<name>_test.dart
     ```
3. **Visual Bug Verification & After Screenshot:**
   - For visual/UI bugs, run the app with the fix on the simulator/emulator and capture the **After** screenshot on the exact same screen with consistent framing (dismiss soft keyboard):
     ```powershell
     adb shell screencap -p /data/local/tmp/after.png
     adb pull /data/local/tmp/after.png .git/screenshots/issue-<issue-number>-after.png
     adb shell rm /data/local/tmp/after.png
     ```
   - **Automated Capture via Integration Test:** When using a temporary integration test (`integration_test/temp_<name>_test.dart`), emit marker strings in stdout (e.g. `debugPrint('###_READY_###')`), hold the frame with `await Future.delayed(...)`, and trigger the capture while the test process is alive:
     ```powershell
     $pinfo = New-Object System.Diagnostics.ProcessStartInfo("fvm.exe", "flutter test integration_test/temp_ui_test.dart -d emulator-5554")
     $pinfo.RedirectStandardOutput = $true; $pinfo.UseShellExecute = $false
     $proc = [System.Diagnostics.Process]::Start($pinfo)
     while (-not $proc.HasExited) {
         $line = $proc.StandardOutput.ReadLine()
         if ($line -match "###_READY_###") {
             Start-Sleep -Seconds 2
             adb shell screencap -p /data/local/tmp/s.png
             adb pull /data/local/tmp/s.png .git/screenshots/issue-<number>-after.png
             adb shell rm /data/local/tmp/s.png
         }
     }
     ```
   - **Inspect Both Screenshots:** Always inspect both `.git/screenshots/issue-<number>-before.png` and `issue-<number>-after.png` with the `read_file` tool before finishing to confirm they depict the actual app UI, have consistent framing, and clearly demonstrate the fix.
4. **Static Analysis & Formatting:**
   - Format:
     ```powershell
     fvm dart format <modified-files>
     ```
   - Analyze:
     ```powershell
     fvm flutter analyze lib/
     ```

### Step 6: Commit

Stage modified files (excluding any untracked or temporary files) and commit:

```powershell
git add <files>
git commit --no-gpg-sign -m "fix(<scope>): <description> (#<issue-number>)"
```

### Step 7: Create and Attach PR Draft

1. Create directory if needed: `.git/pr-drafts/`
2. Save draft to `.git/pr-drafts/issue-<issue-number>.md` with the following structure:
   ```markdown
   # Description
   Fixes #<issue-number>

   ### Root Cause
   <Detailed explanation of why the bug occurred, including stack traces and failure points>

   ### Solution
   <Bulleted list of architectural and code changes made to resolve the root cause>

   ### Verification
   - Unit tests: <test file path> passed (X/X tests)
   - Emulator verification: Verified on Android Emulator (<AVD name>)
   - Static analysis: `fvm flutter analyze lib/` reports 0 errors
   - Visual comparison (for UI bugs): Before & after screenshots captured in `.git/screenshots/`
   ```
3. Attach to commit via Git Notes:
   ```powershell
   git notes add -f -F .git/pr-drafts/issue-<issue-number>.md HEAD
   ```

### Step 8: Push Exclusively to Fork

Push the branch and Git Notes to the user's remote (`origin`):

```powershell
git push -u origin fix/<short-issue-description>
git push origin refs/notes/*
```

**Verify:** Confirm that no PR was created against `upstream`.

### Step 9: Report Status to User

Report back with:
- Branch name and commit hash.
- Summary of the root cause and solution.
- Verification results (test outputs, emulator test results, and before/after screenshot comparisons for visual bugs).
- Confirmation of Git Notes attached and pushed to `origin`.
- Ask for the next issue to tackle.

