#!/usr/bin/env python3
"""
Local Triage & PR Verification Tool for paperless-mobile (SolidCraft-inspired).
Supports multi-PR verification, non-destructive report updates, and per-PR diff dossiers.
"""

import argparse
from collections import Counter, defaultdict
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

UPSTREAM_REPO = "astubenbord/paperless-mobile"
SANDBOX_DIR = Path(".worktrees/pr-sandbox")
REPORTS_DIR = Path(".triage-tools/reports")
PR_DOSSIERS_DIR = REPORTS_DIR / "prs"
ISSUES_REPORTS_DIR = REPORTS_DIR / "issues"

AREA_RULES = {
    "area:saved-views": [
        "saved_view",
        "saved view",
        "savedview",
        "gespeicherte ansicht",
        "showondashboard",
        "showinsidebar",
    ],
    "area:custom-fields": [
        "custom_field",
        "custom field",
        "customfield",
        "zusatzfeld",
        "longtext",
        "monetary",
    ],
    "area:scanner": ["scanner", "camera", "edge_detection", "crop", "camscan"],
    "area:inbox": ["inbox"],
    "area:labels": [
        "labels",
        "correspondent",
        "document_type",
        "document type",
        "storage_path",
        "storage path",
        "tags",
        "asn",
    ],
    "area:auth": [
        "auth",
        "login",
        "logoff",
        "mtls",
        "certificate",
        "biometric",
        "fingerprint",
        "totp",
        "2fa",
        "oidc",
        "openid",
    ],
    "area:i18n": ["l10n", ".arb", "crowdin", "locale", "transliterate"],
    "area:ci-build": [
        ".github/",
        "fastlane/",
        "android/",
        "ios/",
        "pubspec",
        "build.yaml",
        "fvm",
    ],
    "area:documents": [
        "documents",
        "document_details",
        "pdf",
        "pdfrx",
        "viewer",
        "upload",
        "download",
        "thumbnail",
        "share",
    ],
    "area:api": ["specs/", "api", "openapi", "dio", "interceptor", "timeout"],
}

# Risk detection rules evaluated against the rebased git diff
RISK_RULES = [
    # 1. TLS and Certificate Verification Bypasses
    {
        "id": "SEC-TLS-BYPASS",
        "severity": "CRITICAL",
        "description": "Potential TLS validation or badCertificateCallback bypass",
        "pattern": re.compile(
            r"(\+.*badCertificateCallback\s*=\s*\(.*?\)\s*=>\s*true|\+.*allowBadCertificates\s*=\s*true)",
            re.IGNORECASE,
        ),
        "file_filter": lambda f: f.endswith(".dart"),
    },
    # 2. F-Droid & Anti-Features (Google Play Services / MLKit / Firebase)
    {
        "id": "FDROID-PROPRIETARY-LIB",
        "severity": "CRITICAL",
        "description": "Proprietary Google Play Services / Firebase dependency breaks F-Droid build",
        "pattern": re.compile(
            r"(\+.*google_mlkit|\+.*play-services-|\+.*firebase_|\+.*google-services)",
            re.IGNORECASE,
        ),
        "file_filter": lambda f: f.endswith("pubspec.yaml")
        or f.endswith(".gradle")
        or f.endswith(".gradle.kts"),
    },
    # 3. Sensitive Data in Logging
    {
        "id": "SEC-LOG-CREDENTIALS",
        "severity": "WARNING",
        "description": "Possible logging of credentials, auth tokens, or passwords",
        "pattern": re.compile(
            r"\+.*(logger\.[a-z]+\(|print\().*(password|authToken|api_key|bearer|private_key)",
            re.IGNORECASE,
        ),
        "file_filter": lambda f: f.endswith(".dart"),
    },
    # 4. Critical Android Permissions & Manifest Changes
    {
        "id": "SEC-MANIFEST-PERM",
        "severity": "WARNING",
        "description": "New permission or exported component added to AndroidManifest.xml",
        "pattern": re.compile(
            r"\+.*<uses-permission|\+.*android:exported=\"true\"",
            re.IGNORECASE,
        ),
        "file_filter": lambda f: f.endswith("AndroidManifest.xml"),
    },
    # 5. Git Submodule Changes (Accidental Pointer Drift)
    {
        "id": "REPO-SUBMODULE-DRIFT",
        "severity": "WARNING",
        "description": "Submodule commit pointer modified (accidental checkout)",
        "pattern": re.compile(r"\+Subproject commit [0-9a-f]+", re.IGNORECASE),
        "file_filter": lambda f: True,
    },
    # 6. Global HttpOverrides Modification
    {
        "id": "NET-HTTP-OVERRIDES",
        "severity": "NOTICE",
        "description": "Global network interceptor/HttpOverrides modified",
        "pattern": re.compile(r"\+.*HttpOverrides\.global\s*=", re.IGNORECASE),
        "file_filter": lambda f: f.endswith(".dart"),
    },
    # 7. Crowdin Localization Bypass (editing non-English .arb files directly)
    {
        "id": "I18N-CROWDIN-BYPASS",
        "severity": "WARNING",
        "description": "Non-base localization file modified directly (only edit intl_en.arb; translations use Crowdin)",
        "pattern": None,
        "file_filter": lambda f: f.startswith("lib/l10n/")
        and f.endswith(".arb")
        and f != "lib/l10n/intl_en.arb",
    },
    # 8. Persisted Store Migration Risk (new required field without @Default)
    {
        "id": "STORE-MIGRATION-RISK",
        "severity": "WARNING",
        "description": "New required field without @Default in persisted local store slice may break app upgrades",
        "pattern": re.compile(r"^\+(?!.*@Default).*?\brequired\s+", re.IGNORECASE),
        "file_filter": lambda f: f.startswith("lib/core/store/")
        and f.endswith(".dart")
        and not f.endswith((".g.dart", ".freezed.dart")),
    },
    # 9. Strict Required Field in API Model (without @Default)
    {
        "id": "API-STRICT-REQUIRED-FIELD",
        "severity": "NOTICE",
        "description": "New required field without @Default in API model may fail on older/newer Paperless-ngx versions",
        "pattern": re.compile(r"^\+(?!.*@Default).*?\brequired\s+", re.IGNORECASE),
        "file_filter": lambda f: f.startswith("lib/api/models/")
        and f.endswith(".dart")
        and not f.endswith((".g.dart", ".freezed.dart")),
    },
    # 10. CI/CD Workflows, Fastlane, or Release Signing Config Modified
    {
        "id": "CI-PIPELINE-OR-SIGNING",
        "severity": "CRITICAL",
        "description": "CI/CD workflow, Fastlane config, or Android signingConfig modified",
        "pattern": re.compile(r"\+.*signingConfig", re.IGNORECASE),
        "file_only_filter": lambda f: f.startswith(".github/workflows/")
        or f.startswith("fastlane/")
        or f.endswith("key.properties"),
        "file_filter": lambda f: f.endswith((".gradle", ".gradle.kts")),
    },
    # 11. Unpinned Git or Local Path Dependency in pubspec.yaml
    {
        "id": "SUPPLY-UNPINNED-GIT-DEP",
        "severity": "CRITICAL",
        "description": "Git or local path dependency added in pubspec.yaml (supply-chain & F-Droid reproducibility risk)",
        "pattern": re.compile(
            r"^\+\s*(git:|path:|ref:\s*(main|master|HEAD|develop|development)\b)",
            re.IGNORECASE,
        ),
        "file_filter": lambda f: f.endswith("pubspec.yaml"),
    },
    # 12. Insecure Credential / Token Storage
    {
        "id": "SEC-INSECURE-CREDENTIAL-STORAGE",
        "severity": "CRITICAL",
        "description": "Sensitive credentials/tokens referenced near unencrypted storage (use FlutterSecureStorage)",
        "pattern": re.compile(
            r"\+.*(SharedPreferences|Hive\.box|localStore).*(token|password|secret|passphrase|clientCertificate)",
            re.IGNORECASE,
        ),
        "file_filter": lambda f: f.endswith(".dart"),
    },
    # 13. Insecure WebView Flags or Cleartext HTTP Traffic
    {
        "id": "SEC-WEBVIEW-OR-CLEARTEXT",
        "severity": "WARNING",
        "description": "Insecure WebView configuration or cleartext HTTP traffic enabled",
        "pattern": re.compile(
            r"\+.*(JavaScriptMode\.unrestricted|allowUniversalAccessFromFileURLs|allowFileAccessFromFileURLs|usesCleartextTraffic\s*=\s*\"true\"|NSAllowsArbitraryLoads)",
            re.IGNORECASE,
        ),
        "file_filter": lambda f: f.endswith(
            (".dart", "AndroidManifest.xml", "Info.plist")
        ),
    },
    # 14. Synchronous File I/O on UI Thread
    {
        "id": "PERF-SYNC-FILE-IO",
        "severity": "NOTICE",
        "description": "Synchronous file I/O in app code may block the Flutter UI thread",
        "pattern": re.compile(
            r"\+.*\.(readAsBytesSync|readAsStringSync|writeAsBytesSync|writeAsStringSync|listSync)\s*\(",
            re.IGNORECASE,
        ),
        "file_filter": lambda f: f.startswith("lib/")
        and f.endswith(".dart")
        and "isolate" not in f.lower(),
    },
]


def scan_pr_risks(cwd: Path | None = None, diff_text: str | None = None) -> list[dict]:
    """Inspects the git diff of the PR against upstream/development for security/architectural risks."""
    if diff_text is None:
        diff_res = run_cmd(["git", "diff", "upstream/development...HEAD"], cwd=cwd)
        if diff_res.returncode != 0:
            return []
        diff_text = diff_res.stdout

    findings = []
    seen_rule_files: set[tuple[str, str]] = set()
    current_file = ""

    for line in diff_text.splitlines():
        if line.startswith("diff --git a/"):
            parts = line.split(" b/")
            current_file = parts[1] if len(parts) > 1 else ""
            for rule in RISK_RULES:
                file_only_fn = rule.get("file_only_filter")
                is_file_only = (
                    rule["pattern"] is None and rule["file_filter"](current_file)
                ) or (file_only_fn is not None and file_only_fn(current_file))
                if is_file_only and (rule["id"], current_file) not in seen_rule_files:
                    seen_rule_files.add((rule["id"], current_file))
                    findings.append(
                        {
                            "id": rule["id"],
                            "severity": rule["severity"],
                            "file": current_file,
                            "description": rule["description"],
                            "line": f"(file modified: {current_file})",
                        }
                    )
            continue

        if not line.startswith("+") or line.startswith("+++"):
            continue

        for rule in RISK_RULES:
            if (
                rule["pattern"] is not None
                and (rule["id"], current_file) not in seen_rule_files
                and rule["file_filter"](current_file)
            ):
                if rule["pattern"].search(line):
                    seen_rule_files.add((rule["id"], current_file))
                    findings.append(
                        {
                            "id": rule["id"],
                            "severity": rule["severity"],
                            "file": current_file,
                            "description": rule["description"],
                            "line": line[1:].strip()[:100],
                        }
                    )
    return findings


def format_risk_assessment_section(risk_findings: list[dict]) -> str:
    """Formats Section 2b (Risk Assessment) with a detailed pass/fail table for all RISK_RULES."""
    findings_by_rule: dict[str, list[dict]] = {}
    for f in risk_findings:
        findings_by_rule.setdefault(f["id"], []).append(f)

    failed_rules_count = len(findings_by_rule)
    total_rules = len(RISK_RULES)

    lines = ["\n## 2b. Risk Assessment"]
    if failed_rules_count == 0:
        lines.append(
            f"✅ **All {total_rules}/{total_rules} risk checks passed.** No suspicious security or build-breaking patterns detected.\n"
        )
    else:
        lines.append(
            f"⚠️ **{failed_rules_count} of {total_rules} risk rule(s) triggered ({len(risk_findings)} finding(s) total):**\n"
        )

    table_lines = [
        "| Rule ID | Severity | Status | Description | Findings |",
        "| :--- | :--- | :--- | :--- | :--- |",
    ]

    for rule in RISK_RULES:
        rule_id = rule["id"]
        severity = rule["severity"]
        desc = rule["description"].replace("|", "\\|")
        rule_findings = findings_by_rule.get(rule_id, [])

        if not rule_findings:
            status_cell = "✅ PASS"
            findings_cell = "—"
        else:
            status_cell = "❌ FAIL" if severity == "CRITICAL" else "⚠️ FAIL"
            formatted_items = []
            for rf in rule_findings:
                safe_line = (
                    rf["line"]
                    .replace("|", "\\|")
                    .replace("`", "'")
                    .replace("\n", " ")
                    .replace("\r", " ")
                )
                formatted_items.append(f"`{rf['file']}` (`{safe_line}`)")
            findings_cell = "<br>".join(formatted_items)

        table_lines.append(
            f"| `{rule_id}` | `{severity}` | {status_cell} | {desc} | {findings_cell} |"
        )

    if failed_rules_count == 0:
        lines.extend(
            [
                "<details>",
                f"<summary>Show all {total_rules} risk check results</summary>\n",
                *table_lines,
                "\n</details>",
            ]
        )
    else:
        lines.extend(table_lines)

    return "\n".join(lines)


def run_cmd(
    cmd: list[str], cwd: Path | None = None, check: bool = False
) -> subprocess.CompletedProcess:
    use_shell = os.name == "nt" and cmd[0] in ("fvm", "flutter", "dart")

    # Prevent any interactive password/passphrase prompts in background
    env = os.environ.copy()
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GCM_INTERACTIVE"] = "never"
    env["SSH_BATCH_MODE"] = "yes"
    env["GIT_EDITOR"] = "true"

    # Suppress GPG/SSH signing automatically during git rebase/commit/merge
    if cmd and cmd[0] == "git":
        cmd = [
            "git",
            "-c",
            "user.name=Triage Sandbox",
            "-c",
            "user.email=triage@localhost",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "tag.gpgsign=false",
        ] + cmd[1:]

    return subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,  # Never block on interactive user input!
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        shell=use_shell,
        check=check,
    )


def gh_json(args: list[str]) -> list | dict:
    cmd = ["gh"] + args + ["--repo", UPSTREAM_REPO]
    res = run_cmd(cmd)
    if res.returncode != 0:
        print(
            f"[ERROR] gh command failed: {' '.join(cmd)}\n{res.stderr}", file=sys.stderr
        )
        sys.exit(1)
    return json.loads(res.stdout) if res.stdout.strip() else []


def infer_areas_from_paths(paths: list[str]) -> list[str]:
    areas = set()
    for p in paths:
        p_lower = p.lower()
        for area, keywords in AREA_RULES.items():
            if any(k in p_lower for k in keywords):
                areas.add(area)
    return sorted(areas) or ["area:general"]


def infer_areas_from_text(title: str, body: str) -> list[str]:
    title_lower = title.lower()
    body_lower = body.lower()
    areas: list[str] = []
    # Match title first (in specificity order), then body
    for area, keywords in AREA_RULES.items():
        if any(k in title_lower for k in keywords):
            areas.append(area)
    for area, keywords in AREA_RULES.items():
        if area not in areas and any(k in body_lower for k in keywords):
            areas.append(area)
    return areas or ["area:unclassified"]


def load_existing_sandbox_checks(report_path: Path) -> dict[int, str]:
    """Read existing Sandbox Check column values from pr_triage.md so partial runs don't wipe them."""
    checks: dict[int, str] = {}
    if not report_path.exists():
        return checks
    row_re = re.compile(r"^\|\s*\[#(\d+)\]\([^)]+\)\s*\|.*\|\s*([^|]+?)\s*\|$")
    for line in report_path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = row_re.match(line.strip())
        if m:
            pr_num = int(m.group(1))
            status = m.group(2).strip()
            if status and not status.startswith("Skipped"):
                checks[pr_num] = status
    return checks


def cmd_overview(_args: argparse.Namespace) -> None:
    print("Fetching latest refs from upstream...")
    run_cmd(["git", "fetch", "upstream", "--prune"])

    res = run_cmd(
        [
            "git",
            "for-each-ref",
            "--sort=-committerdate",
            "refs/remotes/upstream/",
            "--format=%(refname:short)|%(committerdate:short)|%(authorname)|%(contents:subject)",
        ]
    )
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    out_lines = [
        "# Upstream Branch Overview (`paperless-mobile`)",
        f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}\n",
        "| Branch | Last Commit | Ahead / Behind `development` | Last Commit Subject |",
        "| :--- | :--- | :--- | :--- |",
    ]
    print("\n=== UPSTREAM BRANCHES (excluding PR refs) ===")
    print(
        f"{'Branch':<42} | {'Last Commit':<11} | {'Ahead/Behind dev':<18} | {'Subject'}"
    )
    print("-" * 110)

    for line in res.stdout.splitlines():
        if (
            not line
            or line.startswith("upstream/pr/")
            or line.startswith("upstream/HEAD")
        ):
            continue
        branch, date, _author, subject = (line.split("|", 3) + ["", "", "", ""])[:4]
        ab_res = run_cmd(
            [
                "git",
                "rev-list",
                "--left-right",
                "--count",
                f"upstream/development...{branch}",
            ]
        )
        behind, ahead = ("?", "?")
        if ab_res.returncode == 0 and ab_res.stdout.strip():
            parts = ab_res.stdout.strip().split()
            if len(parts) == 2:
                behind, ahead = parts[0], parts[1]
        ab_str = f"+{ahead} / -{behind}"
        print(f"{branch:<42} | {date:<11} | {ab_str:<18} | {subject[:50]}")
        out_lines.append(f"| `{branch}` | {date} | `{ab_str}` | {subject} |")

    overview_path = REPORTS_DIR / "branch_overview.md"
    overview_path.write_text("\n".join(out_lines) + "\n", encoding="utf-8")
    print(f"\n[OK] Branch overview saved to: {overview_path}")


def cmd_prs(args: argparse.Namespace) -> None:
    prs = gh_json(
        [
            "pr",
            "list",
            "--state",
            "open",
            "--limit",
            "50",
            "--json",
            "number,title,author,updatedAt,mergeable,isDraft,headRefName,baseRefName,files,additions,deletions,url,body",
        ]
    )
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    report_path = REPORTS_DIR / "pr_triage.md"
    existing_checks = load_existing_sandbox_checks(report_path)
    target_prs = set(args.pr) if args.pr else None

    report_lines = [
        "# Pull Request Triage Report (`paperless-mobile`)",
        f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}\n",
        "| PR | Title | Author | Mergeable | Size | Areas | Sandbox Check |",
        "| :--- | :--- | :--- | :--- | :--- | :--- | :--- |",
    ]

    for pr in prs:
        num = pr["number"]
        files = [f["path"] for f in pr.get("files", [])]
        areas = infer_areas_from_paths(files)
        size_str = f"+{pr['additions']}/-{pr['deletions']}"
        mergeable = pr.get("mergeable") or "UNKNOWN"

        should_verify = args.verify and (target_prs is None or num in target_prs)

        if should_verify:
            sandbox_status = verify_pr_in_sandbox(pr, files)
            print(
                f"PR #{num:<4} [{mergeable:<11}] {size_str:<12} -> {sandbox_status} | {pr['title']}"
            )
        else:
            sandbox_status = existing_checks.get(num, "Skipped (use `--verify`)")
            if target_prs is None:
                print(
                    f"PR #{num:<4} [{mergeable:<11}] {size_str:<12} {', '.join(areas):<28} | {pr['title']}"
                )

        report_lines.append(
            f"| [#{num}]({pr['url']}) | {pr['title']} | @{pr['author']['login']} "
            f"| `{mergeable}` | `{size_str}` | {', '.join(f'`{a}`' for a in areas)} | {sandbox_status} |"
        )

    report_path.write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    print(f"\n[OK] Updated full table in: {report_path}")


def verify_pr_in_sandbox(pr: dict, changed_files: list[str]) -> str:
    pr_number = pr["number"]
    title = pr["title"]
    print(f"\n👉 [Sandbox] Starting verification for PR #{pr_number}: {title}")

    if not SANDBOX_DIR.exists():
        return "ERROR: .worktrees/pr-sandbox missing"

    print("   [1/7] Fetching latest refs from upstream/development...")
    fetch_res = run_cmd(
        [
            "git",
            "fetch",
            "upstream",
            f"pull/{pr_number}/head:refs/remotes/upstream/pr/{pr_number}",
        ],
        cwd=SANDBOX_DIR,
    )
    if fetch_res.returncode != 0:
        return "FETCH_FAILED"

    run_cmd(["git", "rebase", "--abort"], cwd=SANDBOX_DIR)
    run_cmd(["git", "reset", "--hard"], cwd=SANDBOX_DIR)
    run_cmd(
        ["git", "checkout", "--detach", f"refs/remotes/upstream/pr/{pr_number}"],
        cwd=SANDBOX_DIR,
    )

    print("   [2/7] Testing rebase onto upstream/development...")
    rebase_res = run_cmd(["git", "rebase", "upstream/development"], cwd=SANDBOX_DIR)
    if rebase_res.returncode != 0:
        conflict_output = (rebase_res.stdout + "\n" + rebase_res.stderr).strip()
        run_cmd(["git", "rebase", "--abort"], cwd=SANDBOX_DIR)
        write_pr_dossier(pr, changed_files, "❌ REBASE_CONFLICT", conflict_output)
        return "❌ REBASE_CONFLICT"

    # Risk Assessment Check
    print("   [3/7] Scanning diff for security & architectural risks...")
    risk_findings = scan_pr_risks(cwd=SANDBOX_DIR)
    critical_risks = [f for f in risk_findings if f["severity"] == "CRITICAL"]
    warnings = [f for f in risk_findings if f["severity"] == "WARNING"]

    if risk_findings:
        print(
            f"   ⚠️ Found {len(risk_findings)} risk flag(s): {len(critical_risks)} CRITICAL, {len(warnings)} WARNING"
        )
        for f in risk_findings:
            print(
                f"      • [{f['severity']}] {f['id']}: {f['description']} in {f['file']}"
            )
    else:
        print("   ✅ No high-risk patterns detected in diff.")

    dart_files = [
        f for f in changed_files if f.endswith(".dart") and (SANDBOX_DIR / f).exists()
    ]
    if not dart_files:
        print("   [4/7] No Dart files modified (skipping codegen, analyze & tests).")
        status = "✅ REBASE_CLEAN (non-Dart PR)"
        write_pr_dossier(
            pr,
            changed_files,
            status,
            "No Dart files modified.",
            risk_findings=risk_findings,
        )
        return status

    # 1. Ensure package_config.json exists or update if pubspec changed
    if not (SANDBOX_DIR / ".dart_tool" / "package_config.json").exists() or any(
        "pubspec" in f for f in changed_files
    ):
        print("   [4/7] Running 'flutter pub get'...")
        run_cmd(["fvm", "flutter", "pub", "get"], cwd=SANDBOX_DIR)
    else:
        print("   [4/7] Dependencies up to date.")

    # 2. Run gen-l10n and/or build_runner if models, routes or localization changed
    needs_l10n = any(f.endswith(".arb") for f in changed_files)
    needs_codegen = any(
        k in f
        for f in dart_files
        for k in ("models/", "specs/", "cubit", "bloc", "store/", "routes/")
    )
    if needs_l10n or needs_codegen:
        print("   [5/7] Generating model/l10n code (build_runner / gen-l10n)...")
        if needs_l10n:
            run_cmd(["fvm", "flutter", "gen-l10n"], cwd=SANDBOX_DIR)
        if needs_codegen:
            run_cmd(
                [
                    "fvm",
                    "dart",
                    "run",
                    "build_runner",
                    "build",
                    "--delete-conflicting-outputs",
                ],
                cwd=SANDBOX_DIR,
            )
    else:
        print("   [5/7] No code generation required.")

    # 3. Static analysis on modified Dart files
    print("   [6/7] Running static code analysis (flutter analyze)...")
    analyze_res = run_cmd(
        ["fvm", "flutter", "analyze", "--no-pub"] + dart_files, cwd=SANDBOX_DIR
    )
    analyzer_output = (analyze_res.stdout + "\n" + analyze_res.stderr).strip()
    has_analyze_issues = analyze_res.returncode != 0

    # 4. Standard test runner check for touched test files
    test_files = [
        f
        for f in changed_files
        if f.startswith("test/")
        and f.endswith("_test.dart")
        and (SANDBOX_DIR / f).exists()
    ]
    test_output = ""
    has_test_failures = False

    if test_files:
        print(f"   [7/7] Running unit/widget tests ({len(test_files)} files)...")
        test_res = run_cmd(["fvm", "flutter", "test"] + test_files, cwd=SANDBOX_DIR)
        test_output = (test_res.stdout + "\n" + test_res.stderr).strip()
        has_test_failures = test_res.returncode != 0
        if not has_test_failures:
            print(f"   ✅ All {len(test_files)} test suite(s) passed!")
        else:
            print("   ❌ Test suite reported failures!")
    else:
        print("   [7/7] No test files modified in this PR.")

    # Determine final verdict
    combined_log = f"=== ANALYZER OUTPUT ===\n{analyzer_output or 'No issues found.'}\n"
    if test_files:
        combined_log += (
            f"\n=== TEST RUNNER OUTPUT ===\n{test_output or 'Tests ran clean.'}\n"
        )

    if has_test_failures:
        status = "❌ REBASE_CLEAN / TESTS_FAILED"
        print(f"   ❌ PR #{pr_number} failed unit/widget tests!")
    elif has_analyze_issues:
        status = "⚠️ REBASE_CLEAN / ANALYZE_ISSUES"
        print(f"   ⚠️ PR #{pr_number} finished with analyzer issues.")
    else:
        if test_files:
            status = "✅ REBASE_CLEAN & ANALYZE_OK & TESTS_PASSED"
        else:
            status = "✅ REBASE_CLEAN & ANALYZE_OK"
        print(f"   ✨ PR #{pr_number} passed all checks successfully!")

    write_pr_dossier(
        pr,
        changed_files,
        status,
        combined_log,
        risk_findings=risk_findings,
    )
    return status


def write_pr_dossier(
    pr: dict,
    changed_files: list[str],
    status: str,
    check_output: str,
    risk_findings: list[dict] | None = None,
) -> None:
    """Save a detailed per-PR Markdown file including description, risk assessment, analyzer output, and full diff."""
    PR_DOSSIERS_DIR.mkdir(parents=True, exist_ok=True)
    num = pr["number"]
    diff_res = run_cmd(["gh", "pr", "diff", str(num), "--repo", UPSTREAM_REPO])
    diff_text = diff_res.stdout if diff_res.returncode == 0 else "Could not fetch diff."

    if risk_findings is None:
        risk_findings = (
            scan_pr_risks(diff_text=diff_text) if diff_res.returncode == 0 else []
        )
    risk_section = format_risk_assessment_section(risk_findings)

    touched_files_lines = [f"- `{f}`" for f in changed_files]
    if len(changed_files) > 10:
        touched_files_block = [
            "<details>",
            f"<summary>Show all {len(changed_files)} touched files</summary>\n",
            *touched_files_lines,
            "\n</details>",
        ]
    else:
        touched_files_block = touched_files_lines

    dossier = [
        f"# PR #{num}: {pr['title']}",
        f"- **Author:** @{pr['author']['login']}",
        f"- **URL:** {pr['url']}",
        f"- **Size:** `+{pr['additions']}/-{pr['deletions']}`",
        f"- **Sandbox Result:** {status}\n",
        "## 1. PR Description",
        pr.get("body") or "*No description provided.*",
        "\n## 2. Touched Files",
        *touched_files_block,
        risk_section,
        "\n## 3. Sandbox Rebase & Analyzer Output",
        "<details>",
        "<summary>Show analyzer & test runner logs</summary>\n",
        "```text",
        check_output or "Clean (no warnings/errors).",
        "```",
        "\n</details>",
        "\n## 4. Full Diff",
        "<details>",
        f"<summary>Show full diff (+{pr['additions']}/-{pr['deletions']} across {len(changed_files)} file(s))</summary>\n",
        "```diff",
        diff_text.strip(),
        "```",
        "\n</details>",
    ]
    (PR_DOSSIERS_DIR / f"pr_{num}.md").write_text(
        "\n".join(dossier) + "\n", encoding="utf-8"
    )


def parse_iso_datetime(dt_str: str) -> datetime:
    """Parse an ISO-8601 UTC timestamp string from GitHub API."""
    return datetime.fromisoformat(dt_str.replace("Z", "+00:00"))


def strip_code_blocks(text: str) -> str:
    """Strip markdown code blocks (```...``` and ~~~...~~~) to avoid matching debug logs/headers."""
    text = re.sub(r"```[\s\S]*?```", "", text)
    text = re.sub(r"~~~[\s\S]*?~~~", "", text)
    return text


def extract_mobile_version(body: str) -> str | None:
    """Extract reported Paperless Mobile version string from issue body."""
    # 1. Search in GitHub issue form template section: ### Paperless-Mobile Version
    m = re.search(
        r"###\s*Paperless[- ]Mobile\s*Version\s*\n+([^\n\r#]+)", body, re.IGNORECASE
    )
    if m:
        val = m.group(1).strip()
        if (
            val
            and not val.lower().startswith("_no")
            and not val.lower().startswith("none")
        ):
            v_match = re.search(r"v?([0-9]+(?:\.[0-9]+)+(?:\+[0-9]+)?)", val)
            if v_match:
                return v_match.group(1)
            return val

    # 2. Fallback to App Version or Paperless Mobile Version inline patterns
    m = re.search(
        r"(?:App|Paperless[- ]Mobile)\s*Version[:\s*_-]+v?([0-9]+(?:\.[0-9]+)+(?:\+[0-9]+)?)",
        body,
        re.IGNORECASE,
    )
    if m:
        return m.group(1)

    return None


def extract_positive_reactions(issue: dict) -> int:
    """Count thumbs up reactions for an issue."""
    count = 0
    for rg in issue.get("reactionGroups") or []:
        if rg.get("content") in ("THUMBS_UP", "+1"):
            count += rg.get("users", {}).get("totalCount", 0)
    return count


def cross_reference_issues_and_prs(
    issues: list[dict], prs: list[dict]
) -> tuple[dict[int, dict], set[int], dict[int, list[dict]]]:
    """Cross-reference open issues with open PRs via explicit references and symptom matching."""
    explicit_pr_pattern = re.compile(
        r"(?:fix(?:es|ed)?|close(?:s|d)?|resolve(?:s|d)?|related to|relates to|see)\s+#(\d+)",
        re.IGNORECASE,
    )

    issue_map = {iss["number"]: iss for iss in issues}
    pr_map = {pr["number"]: pr for pr in prs}

    # Structure: pr_number -> {"pr": pr, "matches": list[{"issue": iss, "type": str, "reason": str}]}
    pr_to_issues: dict[int, dict] = {
        pr["number"]: {"pr": pr, "matches": []} for pr in prs
    }
    issue_to_prs: dict[int, list[dict]] = defaultdict(list)
    resolved_issue_numbers: set[int] = set()

    # 1. Explicit matching: PR descriptions/titles referencing issues
    for pr in prs:
        pr_text = (pr.get("title") or "") + " " + (pr.get("body") or "")
        for m in explicit_pr_pattern.finditer(pr_text):
            target_issue_num = int(m.group(1))
            if target_issue_num in issue_map:
                iss = issue_map[target_issue_num]
                matched_item = {
                    "issue": iss,
                    "type": "Explicit",
                    "reason": f"PR #{pr['number']} description explicitly references #{target_issue_num}",
                }
                if not any(
                    x["issue"]["number"] == target_issue_num
                    for x in pr_to_issues[pr["number"]]["matches"]
                ):
                    pr_to_issues[pr["number"]]["matches"].append(matched_item)
                issue_to_prs[target_issue_num].append(
                    {"pr": pr, "type": "Explicit", "reason": matched_item["reason"]}
                )
                resolved_issue_numbers.add(target_issue_num)

    # 2. Explicit matching: Issue comments referencing open PRs
    for iss in issues:
        iss_num = iss["number"]
        comments = iss.get("comments") or []
        for c in comments:
            c_body = c.get("body") or ""
            for m in explicit_pr_pattern.finditer(c_body):
                target_pr_num = int(m.group(1))
                if target_pr_num in pr_map:
                    pr = pr_map[target_pr_num]
                    matched_item = {
                        "issue": iss,
                        "type": "Explicit",
                        "reason": f"Issue comment references open PR #{target_pr_num}",
                    }
                    if not any(
                        x["issue"]["number"] == iss_num
                        for x in pr_to_issues[target_pr_num]["matches"]
                    ):
                        pr_to_issues[target_pr_num]["matches"].append(matched_item)
                    issue_to_prs[iss_num].append(
                        {"pr": pr, "type": "Explicit", "reason": matched_item["reason"]}
                    )
                    resolved_issue_numbers.add(iss_num)

    # 3. Symptom & heuristic matching to known open PRs
    heuristic_pr_rules = {
        702: {
            "name": "Pin API version for saved views on paperless-ngx 3.x",
            "regex": re.compile(
                r"(?:saved[\s_]view|_?\$?savedviewfromjson|show_on_dashboard|show_in_sidebar|views could not be loaded|(?:paperless-ngx\s*3.*views|views.*paperless-ngx\s*3))",
                re.IGNORECASE,
            ),
            "reason": "Saved views failure or API v10 crash addressed by PR #702",
        },
        693: {
            "name": "Document chat / RAG integration and DioHttpErrorInterceptor",
            "regex": re.compile(
                r"(?:document chat|\brag\b|/api/documents/chat|diohttperrorinterceptor)",
                re.IGNORECASE,
            ),
            "reason": "Document chat / RAG or DioHttpErrorInterceptor addressed by PR #693",
        },
        703: {
            "name": "Direct upload of shared files when skipping preparation",
            "regex": re.compile(
                r"(?:skip editing|skipdocumentpreprarationonupload|#624\b|(?:upload.*share.*duplicate|share.*upload.*duplicate))",
                re.IGNORECASE,
            ),
            "reason": "Direct file sharing or duplicate share dialog (#624) addressed by PR #703",
        },
        682: {
            "name": "Respect system HTTP proxy",
            "regex": re.compile(
                r"(?:system proxy|http_proxy|\bpac\b|vpn proxy)",
                re.IGNORECASE,
            ),
            "reason": "System HTTP / VPN proxy support addressed by PR #682",
        },
        679: {
            "name": "Retain keyboard focus in date input",
            "regex": re.compile(
                r"(?:date input.*focus|focus.*date input|created at.*focus|focus.*created at)",
                re.IGNORECASE,
            ),
            "reason": "Date input focus retention addressed by PR #679",
        },
        650: {
            "name": "Make camera feature optional for non-camera / e-ink devices",
            "regex": re.compile(
                r"(?:(?:f-droid.*camera|camera.*f-droid)|supernote|e-ink|#418\b)",
                re.IGNORECASE,
            ),
            "reason": "Camera optionality on F-Droid / e-ink (#418) addressed by PR #650",
        },
        622: {
            "name": "Bulk share, download, and delete actions in Documents tab",
            "regex": re.compile(
                r"(?:bulk download|bulk share|select all.*documents|documents.*select all)",
                re.IGNORECASE,
            ),
            "reason": "Bulk selection, download, or path in filenames (#261, #458) addressed by PR #622",
        },
        554: {
            "name": "Exact date filter operator",
            "regex": re.compile(
                r"(?:exact date filter|filter.*exact date|filter documents by.*day)",
                re.IGNORECASE,
            ),
            "reason": "Exact date filtering feature addressed by PR #554",
        },
        514: {
            "name": "Increase timeout on login",
            "regex": re.compile(
                r"(?:timeout on login|login.*5 seconds|login.*timeout)",
                re.IGNORECASE,
            ),
            "reason": "Login timeout increase addressed by PR #514",
        },
        281: {
            "name": "Error message for scanner upload button",
            "regex": re.compile(
                r"(?:upload button.*scanner|scanner.*upload button|#280\b)",
                re.IGNORECASE,
            ),
            "reason": "Scanner upload button hint (#280) addressed by PR #281",
        },
    }

    for iss in issues:
        iss_num = iss["number"]
        clean_text = (
            (iss.get("title") or "") + "\n" + strip_code_blocks(iss.get("body") or "")
        )
        for pr_num, rule in heuristic_pr_rules.items():
            if pr_num in pr_to_issues:
                matches_num = (
                    (pr_num == 622 and iss_num in (261, 458))
                    or (pr_num == 703 and iss_num == 624)
                    or (pr_num == 650 and iss_num == 418)
                )
                if (
                    matches_num
                    or rule["regex"].search(clean_text)
                    or rule["regex"].search(iss.get("title") or "")
                ):
                    if not any(
                        x["issue"]["number"] == iss_num
                        for x in pr_to_issues[pr_num]["matches"]
                    ):
                        matched_item = {
                            "issue": iss,
                            "type": "Symptom Match",
                            "reason": rule["reason"],
                        }
                        pr_to_issues[pr_num]["matches"].append(matched_item)
                        issue_to_prs[iss_num].append(
                            {
                                "pr": pr_map[pr_num],
                                "type": "Symptom Match",
                                "reason": matched_item["reason"],
                            }
                        )
                        resolved_issue_numbers.add(iss_num)

    return pr_to_issues, resolved_issue_numbers, issue_to_prs


def generate_report_1_resolved_by_prs(
    pr_to_issues: dict[int, dict], output_path: Path
) -> None:
    """Generate Report 1: 1_resolved_by_open_prs.md (PR-to-Issue Cross-Reference)."""
    output_path.parent.mkdir(parents=True, exist_ok=True)

    active_prs = {k: v for k, v in pr_to_issues.items() if v["matches"]}
    total_linked_issues = sum(len(v["matches"]) for v in active_prs.values())
    unique_linked_issues = len(
        {iss["issue"]["number"] for v in active_prs.values() for iss in v["matches"]}
    )

    lines = [
        "# 1. Open Issues Addressed by Currently Open Pull Requests",
        f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        f"Cross-reference status: **{unique_linked_issues}** unique open issues mapped across **{len(active_prs)}** open PRs.\n",
        "## Summary Overview",
        "| PR | PR Title | Author | Mapped Issues | Match Types |",
        "| :--- | :--- | :--- | :--- | :--- |",
    ]

    for pr_num, data in sorted(
        active_prs.items(), key=lambda x: len(x[1]["matches"]), reverse=True
    ):
        pr = data["pr"]
        matches = data["matches"]
        author = pr.get("author", {}).get("login", "unknown")
        title_clean = pr["title"].replace("|", "\\|")
        match_types = ", ".join(sorted(set(m["type"] for m in matches)))
        lines.append(
            f"| [#{pr_num}]({pr['url']}) | {title_clean} | @{author} | **{len(matches)}** issue(s) | `{match_types}` |"
        )

    lines.append("\n---")
    lines.append("\n## Detailed PR-to-Issue Breakdowns")

    for pr_num, data in sorted(active_prs.items(), key=lambda x: x[0], reverse=True):
        pr = data["pr"]
        matches = data["matches"]
        author = pr.get("author", {}).get("login", "unknown")
        lines.append(f"\n### PR [#{pr_num}]({pr['url']}): {pr['title']}")
        lines.append(f"- **Author:** @{author}")
        lines.append(f"- **Open PR URL:** {pr['url']}")
        lines.append(f"- **Total Mapped Issues:** {len(matches)}\n")

        lines.append("| Issue | Title | Match Type | Matching Reason |")
        lines.append("| :--- | :--- | :--- | :--- |")

        for m in matches:
            iss = m["issue"]
            clean_title = (
                iss["title"]
                .replace("|", "\\|")
                .replace("\n", " ")
                .replace("\r", " ")[:90]
            )
            badge = (
                "🟢 `Explicit Link`"
                if m["type"] == "Explicit"
                else "🔵 `Symptom Match`"
            )
            reason_clean = m["reason"].replace("|", "\\|")
            lines.append(
                f"| [#{iss['number']}]({iss['url']}) | {clean_title} | {badge} | {reason_clean} |"
            )

        lines.append(
            f"\n<details>\n<summary>Show ready-to-run GitHub CLI commands for PR #{pr_num}</summary>\n"
        )
        lines.append("```bash")
        lines.append(
            f"# Execute when PR #{pr_num} is merged to inform authors and close issues:"
        )
        for m in matches:
            iss = m["issue"]
            lines.append(
                f'gh issue comment {iss["number"]} --body "This issue was addressed in PR #{pr_num} (@{author})." --repo {UPSTREAM_REPO}'
            )
            lines.append(
                f'gh issue close {iss["number"]} --comment "Resolved by merged PR #{pr_num}." --repo {UPSTREAM_REPO}'
            )
        lines.append("```")
        lines.append("\n</details>")

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def cluster_issues(
    issues: list[dict], issue_to_prs: dict[int, list[dict]]
) -> list[dict]:
    """Group open issues into crash signatures, symptom clusters, and title similarity groups."""
    clusters: list[dict] = []
    seen_cluster_signatures: set[str] = set()

    # Pass A: Automated stacktrace and error signature extraction
    re_cast = re.compile(
        r"type '[^']+' is not a subtype of type '[^']+'[^\n]*", re.IGNORECASE
    )
    re_json = re.compile(r"_\$[A-Za-z0-9_]+FromJson", re.IGNORECASE)
    re_frame = re.compile(
        r"package:paperless_mobile/[a-zA-Z0-9_/]+\.dart(?::\d+)?", re.IGNORECASE
    )
    re_net = re.compile(
        r"DioException\s*\[[^\]]+\]|SocketException|HandshakeException|CERTIFICATE_VERIFY_FAILED|HTTP\s*[45]\d\d",
        re.IGNORECASE,
    )

    signature_groups: dict[str, list[dict]] = defaultdict(list)
    for iss in issues:
        full_text = (
            (iss.get("body") or "")
            + "\n"
            + "\n".join(c.get("body") or "" for c in (iss.get("comments") or []))
        )
        # Check cast errors
        for m in re_cast.findall(full_text):
            sig = f"cast:{m.strip()}"
            if iss not in signature_groups[sig]:
                signature_groups[sig].append(iss)
        # Check JSON parser crashes
        for m in re_json.findall(full_text):
            sig = f"json_parser:{m.strip()}"
            if iss not in signature_groups[sig]:
                signature_groups[sig].append(iss)
        # Check specific package frames (excluding generic helpers)
        for m in re_frame.findall(full_text):
            frame_str = m.strip()
            if any(
                k in frame_str
                for k in (
                    "scanner_page.dart",
                    "document_repository.dart",
                    "session_manager",
                )
            ):
                sig = f"frame:{frame_str.split(':')[0]}"
                if iss not in signature_groups[sig]:
                    signature_groups[sig].append(iss)

    for sig, group in signature_groups.items():
        if len(group) >= 2:
            seen_cluster_signatures.add(sig)
            clusters.append(
                {
                    "id": f"cluster:sig-{sig.replace(' ', '-').replace(':', '-')[:35]}",
                    "title": f"Stacktrace Signature: {sig}",
                    "description": f"Issues sharing identical crash trace or exception signature `{sig}`",
                    "issues": group,
                }
            )

    # Pass B: Curated symptom and feature clusters (Keyword Rules)
    curated_definitions = [
        {
            "id": "cluster:saved-views-v3",
            "title": "Saved Views Failure & Crash on API v10 / Paperless-ngx 3.x",
            "description": "Saved views failing to load ('Views could not be loaded') or crashing on API v10 show_on_dashboard/show_in_sidebar.",
            "rule": lambda t: any(
                k in t
                for k in [
                    "saved view",
                    "saved_view",
                    "_$savedviewfromjson",
                    "show_on_dashboard",
                    "views could not be loaded",
                    "gespeicherte ansichten",
                ]
            ),
        },
        {
            "id": "cluster:date-off-by-one-timezone",
            "title": "Date Off-By-One & Timezone Conversion Shifts",
            "description": "Document created/added date shifts back by one day due to UTC and local timezone conversion inconsistencies.",
            "rule": lambda t: any(k in t for k in ["date", "created", "day", "datum"])
            and any(
                k in t
                for k in [
                    "off by one",
                    "shifted",
                    "timezone",
                    "zeitzone",
                    "utc",
                    "yesterday",
                    "gestern",
                    "-1 day",
                    "one day earlier",
                    "offset by one",
                ]
            ),
        },
        {
            "id": "cluster:keyboard-autocorrect-suggestions",
            "title": "Keyboard Autocorrect, Word Suggestions & Swipe Disabled",
            "description": "Input fields (especially Document Title) deactivate keyboard autocomplete, swipe typing, or spellcheck.",
            "rule": lambda t: any(
                k in t
                for k in [
                    "keyboard",
                    "autocorrect",
                    "suggestions",
                    "spell",
                    "swipe",
                    "gboard",
                    "tastatur",
                    "autovervollständigung",
                    "autocomplete",
                ]
            )
            and any(
                k in t
                for k in [
                    "title",
                    "text field",
                    "disabled",
                    "working",
                    "deactivated",
                    "titel",
                    "eingabe",
                ]
            ),
        },
        {
            "id": "cluster:network-timeouts-slow-upload",
            "title": "Network Timeouts (10s receiveTimeout) on Slow Uplinks / Uploads",
            "description": "Large files or slow mobile connections fail silently because Dio global 10s receiveTimeout aborts active transfers.",
            "rule": lambda t: any(
                k in t
                for k in [
                    "timeout",
                    "5 seconds",
                    "10 seconds",
                    "slow",
                    "large file",
                    "/api/schema",
                    "langsam",
                ]
            )
            and any(
                k in t
                for k in [
                    "upload",
                    "login",
                    "connection",
                    "unreachable",
                    "verbindung",
                    "hochladen",
                ]
            ),
        },
        {
            "id": "cluster:filter-by-owner-permissions",
            "title": "Filter Documents by Owner & User Permissions",
            "description": "Requests and bug reports regarding document filtering by owner, assigned user, or permission rules.",
            "rule": lambda t: any(
                k in t for k in ["owner", "besitzer", "permissions", "berechtigung"]
            )
            and any(
                k in t
                for k in [
                    "filter",
                    "view",
                    "documents",
                    "filtern",
                    "dokumente",
                    "ansicht",
                ]
            ),
        },
        {
            "id": "cluster:mtls-client-certificates",
            "title": "mTLS & PKCS#12 Client Certificate Authentication",
            "description": "Issues connecting with mutual TLS, .p12/.pfx client certificate validation, or private key passphrases.",
            "rule": lambda t: any(
                k in t
                for k in [
                    "mtls",
                    "client cert",
                    "pkcs12",
                    ".p12",
                    ".pfx",
                    "client certificate",
                    "passphrase",
                ]
            ),
        },
        {
            "id": "cluster:oidc-oauth-sso",
            "title": "OIDC / OAuth2 / SSO Authentication & Reverse Proxy Redirects",
            "description": "Single Sign-On login flows (Authelia, Authentik, Keycloak, Pocket-ID) and redirect handling.",
            "rule": lambda t: any(
                k in t
                for k in [
                    "oidc",
                    "oauth",
                    "sso",
                    "authelia",
                    "authentik",
                    "keycloak",
                    "pocket-id",
                    "redirect",
                ]
            ),
        },
        {
            "id": "cluster:scanner-crop-rotation",
            "title": "Scanner Camera Edge Detection, Automatic Cropping & Rotation",
            "description": "Camera scanner usability, automatic edge detection, crop aspect ratio distortion, or flashlight toggle.",
            "rule": lambda t: any(
                k in t
                for k in [
                    "scanner",
                    "camera",
                    "kamera",
                    "crop",
                    "edge detection",
                    "rotate",
                    "torch",
                    "flashlight",
                    "zuschnitt",
                ]
            ),
        },
    ]

    for item in curated_definitions:
        matching_issues = []
        for iss in issues:
            clean_text = (
                (iss.get("title") or "")
                + "\n"
                + strip_code_blocks(iss.get("body") or "")
            ).lower()
            if item["rule"](clean_text):
                matching_issues.append(iss)
        if len(matching_issues) >= 2:
            clusters.append(
                {
                    "id": item["id"],
                    "title": item["title"],
                    "description": item["description"],
                    "issues": matching_issues,
                }
            )

    # Pass C: Title Token Similarity Fallback
    stopwords = {
        "the",
        "a",
        "an",
        "in",
        "to",
        "for",
        "of",
        "and",
        "is",
        "on",
        "bug",
        "feature",
        "paperless",
        "mobile",
        "app",
        "with",
        "from",
        "when",
        "by",
        "or",
        "as",
        "at",
        "not",
        "no",
        "der",
        "die",
        "das",
        "und",
        "in",
        "von",
        "bei",
        "mit",
        "fuer",
        "für",
        "im",
        "nicht",
    }

    def tokenize_title(title: str) -> set[str]:
        words = re.sub(r"[^\w\s]", " ", title.lower()).split()
        return {w for w in words if len(w) >= 3 and w not in stopwords}

    # Group unclustered or lightly clustered issues by title Jaccard similarity >= 0.55
    all_clustered_ids = {iss["number"] for c in clusters for iss in c["issues"]}
    candidate_issues = [i for i in issues if i["number"] not in all_clustered_ids]

    title_pairs: list[tuple[dict, dict]] = []
    for i in range(len(candidate_issues)):
        tokens_a = tokenize_title(candidate_issues[i]["title"])
        if len(tokens_a) < 2:
            continue
        for j in range(i + 1, len(candidate_issues)):
            tokens_b = tokenize_title(candidate_issues[j]["title"])
            if len(tokens_b) < 2:
                continue
            intersection = tokens_a & tokens_b
            union = tokens_a | tokens_b
            sim = len(intersection) / len(union) if union else 0.0
            if sim >= 0.55:
                title_pairs.append((candidate_issues[i], candidate_issues[j]))

    if title_pairs:
        # Build connected components for title pairs
        components: list[set[int]] = []
        for a, b in title_pairs:
            na, nb = a["number"], b["number"]
            merged = False
            for comp in components:
                if na in comp or nb in comp:
                    comp.add(na)
                    comp.add(nb)
                    merged = True
                    break
            if not merged:
                components.append({na, nb})

        iss_by_num = {i["number"]: i for i in issues}
        for idx, comp in enumerate(components, 1):
            comp_issues = [iss_by_num[n] for n in sorted(comp)]
            common_tokens = set.intersection(
                *[tokenize_title(iss["title"]) for iss in comp_issues]
            )
            title_hint = (
                "-".join(sorted(common_tokens)) if common_tokens else f"group-{idx}"
            )
            clusters.append(
                {
                    "id": f"cluster:title-sim-{title_hint}",
                    "title": f"Title Similarity Cluster: '{title_hint}'",
                    "description": f"Issues sharing high token similarity in titles: {', '.join(f'#{n}' for n in sorted(comp))}",
                    "issues": comp_issues,
                }
            )

    # Process and designate Canonical issue for each cluster
    deduped_clusters: list[dict] = []
    seen_issue_sets: list[set[int]] = []

    for c in clusters:
        iss_set = {iss["number"] for iss in c["issues"]}
        # Skip if identical issue set already registered
        if iss_set in seen_issue_sets:
            continue
        seen_issue_sets.append(iss_set)

        # Sort issues: canonical is the oldest issue (smallest issue number)
        sorted_issues = sorted(c["issues"], key=lambda x: x["number"])
        canonical = sorted_issues[0]
        duplicates = sorted_issues[1:]

        deduped_clusters.append(
            {
                "id": c["id"],
                "title": c["title"],
                "description": c["description"],
                "canonical": canonical,
                "duplicates": duplicates,
                "issues": sorted_issues,
            }
        )

    return deduped_clusters


def generate_report_2_duplicate_clusters(
    clusters: list[dict], issue_to_prs: dict[int, list[dict]], output_path: Path
) -> None:
    """Generate Report 2: 2_duplicate_and_crash_clusters.md."""
    output_path.parent.mkdir(parents=True, exist_ok=True)

    total_clusters = len(clusters)
    total_duplicate_issues = sum(len(c["duplicates"]) for c in clusters)
    unique_clustered_issues = len(
        {iss["number"] for c in clusters for iss in c["issues"]}
    )

    lines = [
        "# 2. Duplicate Issues & Crash Signature Clusters",
        f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        f"Clusters identified: **{total_clusters}** active clusters spanning **{unique_clustered_issues}** open issues (potential cleanup of **{total_duplicate_issues}** duplicate tickets).\n",
        "## Cluster Summary Table",
        "| Cluster ID | Cluster Topic | Canonical Issue | Total Issues | Duplicates |",
        "| :--- | :--- | :--- | :--- | :--- |",
    ]

    for c in clusters:
        canon = c["canonical"]
        lines.append(
            f"| `{c['id']}` | {c['title']} | [#{canon['number']}]({canon['url']}) | {len(c['issues'])} | {len(c['duplicates'])} |"
        )

    lines.append("\n---")
    lines.append("\n## Detailed Cluster Dossiers & Deduplication Commands")

    for c in clusters:
        canon = c["canonical"]
        duplicates = c["duplicates"]
        lines.append(f"\n### `{c['id']}`: {c['title']}")
        lines.append(f"- **Description:** {c['description']}")
        lines.append(
            f"- **Canonical / Master Issue:** [#{canon['number']}]({canon['url']}) - *\"{canon['title']}\"*"
        )
        lines.append(f"- **Duplicate Count:** {len(duplicates)} ticket(s)\n")

        lines.append(
            "| Role | Issue | Title | Created Date | Reactions (👍) | Open PR |"
        )
        lines.append("| :--- | :--- | :--- | :--- | :--- | :--- |")

        for iss in c["issues"]:
            is_canon = iss["number"] == canon["number"]
            role_badge = "⭐ **Canonical**" if is_canon else "Duplicate"
            clean_title = (
                iss["title"]
                .replace("|", "\\|")
                .replace("\n", " ")
                .replace("\r", " ")[:80]
            )
            created_date = iss["createdAt"][:10]
            reactions = extract_positive_reactions(iss)
            open_prs = issue_to_prs.get(iss["number"], [])
            pr_cell = (
                ", ".join(f"[#{p['pr']['number']}]({p['pr']['url']})" for p in open_prs)
                if open_prs
                else "—"
            )
            lines.append(
                f"| {role_badge} | [#{iss['number']}]({iss['url']}) | {clean_title} | {created_date} | {reactions} | {pr_cell} |"
            )

        if duplicates:
            lines.append(
                f"\n<details>\n<summary>Show ready-to-run GitHub CLI deduplication commands for {c['id']}</summary>\n"
            )
            lines.append("```bash")
            lines.append(
                f"# Link duplicates to canonical issue #{canon['number']} and close them:"
            )
            for dup in duplicates:
                lines.append(
                    f'gh issue comment {dup["number"]} --body "Marking as duplicate of #{canon["number"]}. Please track updates and discussions there." --repo {UPSTREAM_REPO}'
                )
                lines.append(
                    f'gh issue close {dup["number"]} --comment "Duplicate of #{canon["number"]}" --repo {UPSTREAM_REPO}'
                )
            lines.append("```")
            lines.append("\n</details>")

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def find_codebase_pointers(issue: dict, cluster_id: str | None = None) -> list[str]:
    """Find relevant Flutter/Dart source files in lib/ using stacktraces, cluster hints, or file references."""
    body = issue.get("body") or ""
    title = issue.get("title") or ""
    matched_files: list[str] = []

    # 1. Direct file mentions in issue body
    file_matches = re.findall(
        r"(?:package:paperless_mobile/|lib/)([a-zA-Z0-9_/]+\.dart)", body
    )
    for fm in file_matches:
        candidate = f"lib/{fm}"
        if Path(candidate).exists() and candidate not in matched_files:
            matched_files.append(candidate)

    # 2. Known high-impact symptom mappings
    cluster_file_map = {
        "cluster:network-timeouts-slow-upload": [
            "lib/core/security/session_manager_impl.dart",
            "lib/api/modules/paperless_documents_api.dart",
        ],
        "cluster:keyboard-autocorrect-suggestions": [
            "lib/features/document_edit/view/document_edit_page.dart",
            "lib/core/widgets/form_builder_fields/form_builder_color_picker.dart",
        ],
        "cluster:date-off-by-one-timezone": [
            "lib/api/converters/local_date_time_json_converter.dart",
            "lib/features/document_details/view/document_details_page.dart",
        ],
        "cluster:filter-by-owner-permissions": [
            "lib/features/filter/view/filter_page.dart",
            "lib/api/models/query_parameters/document_filter_query.dart",
        ],
        "cluster:mtls-client-certificates": [
            "lib/core/security/session_manager_impl.dart",
            "lib/features/login/services/authentication_service.dart",
        ],
        "cluster:oidc-oauth-sso": [
            "lib/features/login/services/authentication_service.dart",
            "lib/features/login/cubit/authentication_cubit.dart",
        ],
        "cluster:scanner-crop-rotation": [
            "lib/features/document_scan/view/scanner_page.dart",
            "lib/features/document_scan/cubit/document_scanner_cubit.dart",
        ],
        "cluster:saved-views-v3": [
            "lib/api/models/saved_view.dart",
            "lib/api/modules/paperless_saved_views_api.dart",
        ],
    }

    if cluster_id and cluster_id in cluster_file_map:
        for f in cluster_file_map[cluster_id]:
            if Path(f).exists() and f not in matched_files:
                matched_files.append(f)

    # Specific issue keywords to files
    text_lower = (title + " " + body).lower()
    if "archivedfilename" in text_lower or (
        "download" in text_lower and "original" in text_lower
    ):
        cand = "lib/core/repository/document_repository.dart"
        if Path(cand).exists() and cand not in matched_files:
            matched_files.append(cand)

    if "notification" in text_lower:
        cand = "lib/features/notifications/cubit/notifications_cubit.dart"
        if Path(cand).exists() and cand not in matched_files:
            matched_files.append(cand)

    if "receivetimeout" in text_lower or (
        "upload" in text_lower and "timeout" in text_lower
    ):
        cand = "lib/core/security/session_manager_impl.dart"
        if Path(cand).exists() and cand not in matched_files:
            matched_files.append(cand)

    return matched_files[:3] or ["lib/core/repository/document_repository.dart"]


def identify_quick_wins(
    issues: list[dict],
    resolved_issue_numbers: set[int],
    clusters: list[dict],
) -> tuple[list[dict], list[dict]]:
    """Identify and score top actionable bug candidates without an open PR."""
    clustered_issue_nums = set()
    candidates: list[dict] = []

    # 1. Evaluate Multi-Issue Clusters as unified candidates
    for c in clusters:
        valid_issues = [
            iss for iss in c["issues"] if iss["number"] not in resolved_issue_numbers
        ]
        if not valid_issues:
            continue
        for iss in valid_issues:
            clustered_issue_nums.add(iss["number"])

        # Select the best representative issue (prioritize bugs, then reactions, then lowest issue number)
        def bug_priority(iss: dict) -> int:
            t = iss.get("title", "").lower()
            b = iss.get("body", "").lower()
            lbls = [l["name"].lower() for l in iss.get("labels") or []]
            is_bug = (
                "bug" in lbls or t.startswith("[bug]") or "crash" in t or "error" in t
            )
            return 10 if is_bug else 0

        rep = max(
            valid_issues,
            key=lambda x: (
                bug_priority(x),
                extract_positive_reactions(x),
                -x["number"],
            ),
        )

        total_reactions = sum(extract_positive_reactions(x) for x in valid_issues)
        dupe_count = len(valid_issues) - 1

        score = 0
        score += dupe_count * 3
        score += total_reactions * 2

        has_tech = any(
            bool(
                re.search(
                    r"package:paperless_mobile|\.dart:\d+|Exception|Error|_handleFormatError|FormatException|DioException",
                    iss.get("body") or "",
                )
            )
            or bool(re.search(r"/api/[a-z0-9_/]+", iss.get("body") or ""))
            or ("steps to reproduce" in (iss.get("body") or "").lower())
            for iss in valid_issues
        )
        if has_tech:
            score += 3

        areas = infer_areas_from_text(rep["title"], rep.get("body") or "")
        primary_area = areas[0]
        if primary_area not in ("area:unclassified", "area:general"):
            score += 2

        suspected_files = find_codebase_pointers(rep, c["id"])

        candidates.append(
            {
                "issue": rep,
                "score": score,
                "reactions": total_reactions,
                "dupe_count": dupe_count,
                "cluster_id": c["id"],
                "cluster_title": c["title"],
                "primary_area": primary_area,
                "affected_issues": [x["number"] for x in valid_issues],
                "has_tech": has_tech,
                "suspected_files": suspected_files,
            }
        )

    # 2. Evaluate Standalone Bug Candidates
    for iss in issues:
        num = iss["number"]
        if num in resolved_issue_numbers or num in clustered_issue_nums:
            continue

        labels = [l["name"].lower() for l in iss.get("labels") or []]
        title = iss.get("title") or ""
        body = iss.get("body") or ""

        is_enhancement = (
            "enhancement" in labels
            or "feature" in labels
            or title.lower().startswith("[feature]")
        )
        is_bug = (
            "bug" in labels
            or title.lower().startswith("[bug]")
            or any(
                w in title.lower()
                for w in ["crash", "error", "fail", "broken", "stuck", "exception"]
            )
            or any(
                w in body.lower()
                for w in [
                    "steps to reproduce",
                    "exception caught",
                    "formaterror",
                    "typeerror",
                    "stacktrace",
                ]
            )
        )

        if is_enhancement and not is_bug:
            continue
        if not is_bug and len(body.strip()) < 150:
            continue

        reactions = extract_positive_reactions(iss)
        score = reactions * 2

        has_tech = (
            bool(
                re.search(
                    r"package:paperless_mobile|\.dart:\d+|Exception|Error|_handleFormatError|FormatException|DioException",
                    body,
                )
            )
            or bool(re.search(r"/api/[a-z0-9_/]+", body))
            or ("steps to reproduce" in body.lower() and len(body) > 200)
        )
        if has_tech:
            score += 3

        areas = infer_areas_from_text(title, body)
        primary_area = areas[0]
        if primary_area not in ("area:unclassified", "area:general"):
            score += 2

        suspected_files = find_codebase_pointers(iss, None)

        candidates.append(
            {
                "issue": iss,
                "score": score,
                "reactions": reactions,
                "dupe_count": 0,
                "cluster_id": None,
                "cluster_title": None,
                "primary_area": primary_area,
                "affected_issues": [num],
                "has_tech": has_tech,
                "suspected_files": suspected_files,
            }
        )

    # Sort descending by score, then by issue number
    candidates.sort(key=lambda x: (x["score"], -x["issue"]["number"]), reverse=True)
    top_15 = candidates[:15]
    top_5 = candidates[:5]
    return top_15, top_5


def generate_report_3_quick_wins(
    top_15: list[dict], top_5: list[dict], output_path: Path
) -> None:
    """Generate Report 3: 3_quick_win_candidates.md."""
    output_path.parent.mkdir(parents=True, exist_ok=True)

    lines = [
        "# 3. Quick-Win Bug Candidates (No Open PRs)",
        f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        "High-impact, reproducible bugs without any currently open Pull Request, prioritized by community demand and fix feasibility.\n",
        "## Methodology & Scoring Criteria",
        "- **Cluster Size (+3 pts/duplicate):** Multiple users reporting the same defect elevates priority.",
        "- **Reactions (+2 pts/👍):** Direct community upvotes on the GitHub issue.",
        "- **Technical Reproducibility (+3 pts):** Issue body includes stacktraces, Dart exceptions, API endpoints, or reproduction steps.",
        "- **Scope Clarity (+2 pts):** Issue maps cleanly to an established app domain (`area:*`).\n",
        "## Top 15 Quick-Win Candidates",
        "| Rank | Score | Issue | Title | Area | Cluster / Duplicates | 👍 Reactions | Suspected Files (`lib/`) |",
        "| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |",
    ]

    for rank, item in enumerate(top_15, 1):
        iss = item["issue"]
        clean_title = (
            iss["title"].replace("|", "\\|").replace("\n", " ").replace("\r", " ")[:80]
        )
        cluster_cell = (
            f"`{item['cluster_id']}` (+{item['dupe_count']})"
            if item["cluster_id"]
            else "Standalone"
        )
        files_cell = "<br>".join(f"`{f}`" for f in item["suspected_files"])
        lines.append(
            f"| #{rank} | **{item['score']}** | [#{iss['number']}]({iss['url']}) | {clean_title} | `{item['primary_area']}` | {cluster_cell} | {item['reactions']} | {files_cell} |"
        )

    lines.append("\n---")
    lines.append("\n## Detailed Mini-Dossiers for Top 5 Quick Wins")

    for rank, item in enumerate(top_5, 1):
        iss = item["issue"]
        num = iss["number"]
        author = iss.get("author", {}).get("login", "unknown")
        created = iss["createdAt"][:10]
        cluster_str = (
            f"`{item['cluster_id']}` ({item['dupe_count']} duplicates)"
            if item["cluster_id"]
            else "Standalone issue"
        )

        affected_list = item.get("affected_issues", [num])
        other_affected = [n for n in affected_list if n != num]
        affected_str = f"#{num}"
        if other_affected:
            formatted_dupes = ", ".join(f"#{n}" for n in other_affected[:10])
            extra_count = len(other_affected) - 10
            extra_suffix = f" (and {extra_count} more)" if extra_count > 0 else ""
            affected_str += f" (related duplicates: {formatted_dupes}{extra_suffix})"

        lines.append(f"\n### #{rank}: Issue #{num} — {iss['title']}")
        lines.append(f"- **URL:** {iss['url']}")
        lines.append(f"- **Author:** @{author} ({created})")
        lines.append(f"- **Domain Area:** `{item['primary_area']}`")
        lines.append(
            f"- **Triage Score:** **{item['score']} points** (👍 {item['reactions']} reactions, Cluster: {cluster_str})"
        )
        lines.append(f"- **Affected Issues:** {affected_str}")

        # Context-specific fix strategy & symptom summary
        symptom_summary = "*No detailed description provided.*"
        body_text = iss.get("body") or ""
        clean_body = strip_code_blocks(body_text).strip()
        if clean_body:
            first_para = clean_body.split("\n\n")[0].replace("\n", " ").strip()
            symptom_summary = first_para[:300] + (
                "..." if len(first_para) > 300 else ""
            )

        fix_strategy = "Inspect the suspected source files, reproduce with a targeted unit test, and verify error handling."
        if num == 700:
            fix_strategy = (
                "In `lib/core/repository/document_repository.dart` (`generateLocalFilePath`), prefer `originalFileName` "
                "(fallback to `mediaFilename`/`originalMimeType`) when `original == true`, instead of defaulting to `archivedFileName` (`.pdf`)."
            )
        elif (
            num == 699
            or item.get("cluster_id") == "cluster:network-timeouts-slow-upload"
        ):
            fix_strategy = (
                "In `lib/api/modules/paperless_documents_api.dart` (`uploadDocument`), explicitly increase `receiveTimeout` "
                "to `60.seconds` in the upload request `Options`, matching `sendTimeout`, and surface timeout errors in the UI."
            )
        elif num == 476 or "notification" in iss["title"].lower():
            fix_strategy = (
                "In `lib/features/notifications/` or notification service, ensure completion/error callbacks cancel the active "
                "foreground notification or update its state to completed."
            )
        elif num == 383:
            fix_strategy = (
                "In `lib/features/document_edit/` or `DocumentRepository`, verify mutation error propagation when saving document attributes "
                "and ensure payload compatibility with newer Paperless-ngx endpoints."
            )
        elif num == 286 or item.get("cluster_id") == "cluster:date-off-by-one-timezone":
            fix_strategy = (
                "In `lib/api/converters/local_date_time_json_converter.dart`, preserve the document's date without intermediate UTC conversions "
                "that cause off-by-one day regressions in timezones west of UTC."
            )
        elif (
            "keyboard" in iss["title"].lower()
            or "autocomplete" in iss["title"].lower()
            or item.get("cluster_id") == "cluster:keyboard-autocorrect-suggestions"
        ):
            fix_strategy = (
                "In `lib/features/document_edit/view/document_edit_page.dart`, ensure `autocorrect: true` and `enableSuggestions: true` "
                "are set on text form fields, avoiding restrictive password or plain-text input types."
            )
        elif item.get("cluster_id") == "cluster:scanner-crop-rotation":
            fix_strategy = (
                "In `lib/features/document_scan/view/scanner_page.dart` and `document_scanner_cubit.dart`, fix aspect ratio calculation "
                "on devices with wide sensors (e.g. Motorola/Samsung) by preserving preview camera aspect ratio during edge-detection."
            )
        elif item.get("cluster_id") == "cluster:oidc-oauth-sso":
            fix_strategy = (
                "In `lib/features/login/services/authentication_service.dart`, support OIDC authentication flows by capturing OAuth2 redirect "
                "URIs and extracting session tokens from callback headers."
            )

        lines.append(f"\n**Symptom Summary:**\n> {symptom_summary}\n")
        lines.append("**Suspected Source Files (`lib/`):**")
        for f in item["suspected_files"]:
            lines.append(f"- [`{f}`](file:///{f})")
        lines.append(f"\n**Suggested Fix Strategy:**\n{fix_strategy}\n")

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def detect_stale_and_needs_info(
    issues: list[dict],
) -> tuple[list[dict], list[dict], list[dict]]:
    """Detect outdated reported versions (<4.3), unanswered maintainer questions (>60d), and incomplete bug reports."""
    now = datetime.now(timezone.utc)
    cutoff_180 = now - timedelta(days=180)
    cutoff_60 = now - timedelta(days=60)

    outdated_version_issues = []
    unanswered_maintainer_issues = []
    incomplete_needs_info_issues = []

    for iss in issues:
        title = iss.get("title") or ""
        body = iss.get("body") or ""
        created = parse_iso_datetime(iss["createdAt"])
        updated = parse_iso_datetime(iss["updatedAt"])
        comments = iss.get("comments") or []
        labels = [l["name"].lower() for l in iss.get("labels") or []]

        # 1. Outdated app version reported (< 4.3.0 and inactive > 180 days)
        v_str = extract_mobile_version(body)
        if v_str:
            clean_v = v_str.split("+")[0].strip()
            vm = re.match(r"^(\d+)\.(\d+)", clean_v)
            if vm:
                major, minor = int(vm.group(1)), int(vm.group(2))
                if (major < 4 or (major == 4 and minor < 3)) and updated < cutoff_180:
                    outdated_version_issues.append(
                        {
                            "issue": iss,
                            "version": v_str,
                            "updated": updated.strftime("%Y-%m-%d"),
                            "inactive_days": (now - updated).days,
                        }
                    )

        # 2. Awaiting user response to maintainer question (> 60 days)
        if comments:
            last_comment = comments[-1]
            c_author = (last_comment.get("author") or {}).get("login", "")
            c_body = last_comment.get("body") or ""
            c_created = parse_iso_datetime(last_comment["createdAt"])

            is_maintainer = c_author == "astubenbord"
            has_question = "?" in c_body and any(
                w in c_body.lower()
                for w in [
                    "log",
                    "reproduce",
                    "version",
                    "still",
                    "details",
                    "could you",
                    "can you",
                    "please",
                    "screenshot",
                ]
            )

            iss_author = (iss.get("author") or {}).get("login", "")
            if (is_maintainer or has_question) and c_created < cutoff_60:
                if c_author != iss_author:
                    unanswered_maintainer_issues.append(
                        {
                            "issue": iss,
                            "last_author": c_author,
                            "last_comment_date": c_created.strftime("%Y-%m-%d"),
                            "waiting_days": (now - c_created).days,
                        }
                    )

        # 3. Incomplete bug reports (< 150 chars body and missing logs/version)
        is_bug = "bug" in labels or title.lower().startswith("[bug]")
        has_version = bool(v_str) or any(
            v in body.lower() for v in ["v4.", "v3.", "version"]
        )
        has_logs = "```" in body or "steps to reproduce" in body.lower()

        if is_bug and len(body.strip()) < 150 and not (has_version and has_logs):
            incomplete_needs_info_issues.append(
                {
                    "issue": iss,
                    "created": created.strftime("%Y-%m-%d"),
                    "reason": "Short description (<150 chars) and missing logs/steps",
                }
            )

    return (
        outdated_version_issues,
        unanswered_maintainer_issues,
        incomplete_needs_info_issues,
    )


def generate_report_4_stale_and_needs_info(
    outdated: list[dict],
    unanswered: list[dict],
    incomplete: list[dict],
    output_path: Path,
) -> None:
    """Generate Report 4: 4_stale_and_needs_info.md."""
    output_path.parent.mkdir(parents=True, exist_ok=True)

    lines = [
        "# 4. Stale, Outdated & Needs-Info Issues",
        f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        f"Backlog hygiene summary: **{len(outdated)}** outdated version tickets, **{len(unanswered)}** unanswered maintainer questions, **{len(incomplete)}** incomplete bug reports.\n",
        "## 1. Outdated App Versions (< v4.3.0 & Inactive > 180 Days)",
        f"Found **{len(outdated)}** issues reported against legacy releases (v2.x, v3.x, early v4.x) that have seen no updates in over 6 months.\n",
        "| Issue | Title | Reported Version | Last Updated | Inactive Days |",
        "| :--- | :--- | :--- | :--- | :--- |",
    ]

    for item in sorted(outdated, key=lambda x: x["inactive_days"], reverse=True):
        iss = item["issue"]
        clean_title = (
            iss["title"].replace("|", "\\|").replace("\n", " ").replace("\r", " ")[:80]
        )
        lines.append(
            f"| [#{iss['number']}]({iss['url']}) | {clean_title} | `{item['version']}` | {item['updated']} | {item['inactive_days']} days |"
        )

    lines.append(
        "\n<details>\n<summary>Show gh issue comment commands for outdated version issues</summary>\n"
    )
    lines.append("```bash")
    lines.append("# Check whether issues persist on modern v4.5+ releases:")
    for item in outdated[:20]:
        num = item["issue"]["number"]
        lines.append(
            f'gh issue comment {num} --body "Hello! This issue was reported on an older app version ({item["version"]}). Could you please check if this still occurs on the latest Paperless Mobile release (v4.5+)? If no feedback is received, this issue may be closed." --repo {UPSTREAM_REPO}'
        )
    lines.append("```")
    lines.append("\n</details>")

    lines.append("\n---")
    lines.append("\n## 2. Unanswered Maintainer Questions (> 60 Days)")
    lines.append(
        f"Found **{len(unanswered)}** issues where maintainer `@astubenbord` or another contributor requested details/logs over 60 days ago with no author reply.\n"
    )
    lines.append(
        "| Issue | Title | Last Question By | Last Question Date | Days Waiting |"
    )
    lines.append("| :--- | :--- | :--- | :--- | :--- |")

    for item in sorted(unanswered, key=lambda x: x["waiting_days"], reverse=True):
        iss = item["issue"]
        clean_title = (
            iss["title"].replace("|", "\\|").replace("\n", " ").replace("\r", " ")[:80]
        )
        lines.append(
            f"| [#{iss['number']}]({iss['url']}) | {clean_title} | @{item['last_author']} | {item['last_comment_date']} | {item['waiting_days']} days |"
        )

    lines.append(
        "\n<details>\n<summary>Show gh issue comment commands for unanswered maintainer questions</summary>\n"
    )
    lines.append("```bash")
    lines.append("# Friendly follow-up ping:")
    for item in unanswered[:20]:
        num = item["issue"]["number"]
        lines.append(
            f'gh issue comment {num} --body "Friendly ping! We are waiting for further reproduction steps or logs to investigate this. Please let us know if this is still relevant." --repo {UPSTREAM_REPO}'
        )
    lines.append("```")
    lines.append("\n</details>")

    lines.append("\n---")
    lines.append("\n## 3. Incomplete Bug Reports (`needs-info`)")
    lines.append(
        f"Found **{len(incomplete)}** bug tickets with fewer than 150 characters and missing steps/logs.\n"
    )
    lines.append("| Issue | Title | Created Date | Reason |")
    lines.append("| :--- | :--- | :--- | :--- |")

    for item in incomplete:
        iss = item["issue"]
        clean_title = (
            iss["title"].replace("|", "\\|").replace("\n", " ").replace("\r", " ")[:80]
        )
        lines.append(
            f"| [#{iss['number']}]({iss['url']}) | {clean_title} | {item['created']} | {item['reason']} |"
        )

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def generate_executive_summary(
    issues: list[dict],
    pr_to_issues: dict[int, dict],
    clusters: list[dict],
    quick_wins: list[dict],
    stale_data: tuple[list[dict], list[dict], list[dict]],
    by_area: dict[str, list[dict]],
    output_path: Path,
) -> None:
    """Generate main executive summary dashboard: .triage-tools/reports/issue_triage.md."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    outdated, unanswered, incomplete = stale_data

    active_prs = {k: v for k, v in pr_to_issues.items() if v["matches"]}
    unique_pr_resolved_issues = len(
        {iss["issue"]["number"] for v in active_prs.values() for iss in v["matches"]}
    )

    total_clusters = len(clusters)
    total_duplicate_issues = sum(len(c["duplicates"]) for c in clusters)
    total_stale_issues = len(outdated) + len(unanswered) + len(incomplete)

    lines = [
        "# Issue Triage Executive Summary (`paperless-mobile`)",
        f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        f"Total open issues analyzed: **{len(issues)}**\n",
        "## 1. Actionable Triage Dashboard",
        "| Metric / Sub-Report | Findings | Actionable Report Link |",
        "| :--- | :--- | :--- |",
        f"| **Issues Resolvable by Open PRs** | **{unique_pr_resolved_issues}** issues mapped to **{len(active_prs)}** open PRs | [Open Report: `1_resolved_by_open_prs.md`](issues/1_resolved_by_open_prs.md) |",
        f"| **Duplicate & Crash Clusters** | **{total_clusters}** clusters (**{total_duplicate_issues}** duplicate tickets) | [Open Report: `2_duplicate_and_crash_clusters.md`](issues/2_duplicate_and_crash_clusters.md) |",
        f"| **High-Priority Quick-Win Bugs** | **{len(quick_wins)}** vetted bug candidates ready for fixing | [Open Report: `3_quick_win_candidates.md`](issues/3_quick_win_candidates.md) |",
        f"| **Stale & Needs-Info Candidates** | **{total_stale_issues}** tickets (<4.3 outdated, unanswered, incomplete) | [Open Report: `4_stale_and_needs_info.md`](issues/4_stale_and_needs_info.md) |",
        "\n---",
        "\n## 2. Distribution by Area",
        "| Area Domain | Issue Count | Share (%) |",
        "| :--- | :--- | :--- |",
    ]

    total_count = max(len(issues), 1)
    for area, items in sorted(by_area.items(), key=lambda x: len(x[1]), reverse=True):
        share = (len(items) / total_count) * 100
        lines.append(f"| `{area}` | **{len(items)}** | {share:.1f}% |")

    lines.append("\n---")
    lines.append("\n## 3. Issues Grouped by Area")

    for area, items in sorted(by_area.items(), key=lambda x: len(x[1]), reverse=True):
        lines.append(f"\n### `{area}` ({len(items)} issues)")
        lines.append("<details>")
        lines.append(
            f"<summary>Show all {len(items)} issues in <code>{area}</code></summary>\n"
        )
        for iss in items:
            clean_title = (
                iss["title"]
                .replace("|", "\\|")
                .replace("\n", " ")
                .replace("\r", " ")[:95]
            )
            labels = ", ".join(l["name"] for l in iss.get("labels") or [])
            lbl_badge = f" *[{labels}]*" if labels else ""
            lines.append(
                f"- [#{iss['number']}]({iss['url']}) **{clean_title}** ({iss['createdAt'][:10]}){lbl_badge}"
            )
        lines.append("\n</details>")

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def cmd_issues(_args: argparse.Namespace) -> None:
    print(f"👉 [Issues] Starting deep issue triage for {UPSTREAM_REPO}...")

    # Step 1: Fetching issues and PRs
    print("   [1/6] Fetching open issues and open PRs via GitHub CLI...")
    issues = gh_json(
        [
            "issue",
            "list",
            "--state",
            "open",
            "--limit",
            "250",
            "--json",
            "number,title,author,createdAt,updatedAt,labels,body,comments,reactionGroups,url",
        ]
    )
    prs = gh_json(
        [
            "pr",
            "list",
            "--state",
            "open",
            "--limit",
            "100",
            "--json",
            "number,title,body,url,author",
        ]
    )

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    ISSUES_REPORTS_DIR.mkdir(parents=True, exist_ok=True)

    # Step 2: Cross-referencing issues with open PRs
    print(
        "   [2/6] Cross-referencing issues with open PRs (explicit links & symptom matching)..."
    )
    pr_to_issues, resolved_issue_numbers, issue_to_prs = cross_reference_issues_and_prs(
        issues, prs
    )

    # Step 3: Extracting stacktraces and building duplicate clusters
    print("   [3/6] Extracting stacktraces and building duplicate/symptom clusters...")
    clusters = cluster_issues(issues, issue_to_prs)

    # Step 4: Identifying quick wins and local codebase pointers
    print("   [4/6] Identifying quick-win bug candidates and locating source files...")
    top_15_quick_wins, top_5_quick_wins = identify_quick_wins(
        issues, resolved_issue_numbers, clusters
    )

    # Step 5: Detecting stale, outdated, and unanswered issues
    print(
        "   [5/6] Detecting stale issues, outdated versions, and unanswered questions..."
    )
    stale_data = detect_stale_and_needs_info(issues)

    # Area categorization
    by_area: dict[str, list[dict]] = {}
    for iss in issues:
        areas = infer_areas_from_text(iss["title"], iss.get("body") or "")
        primary_area = areas[0]
        by_area.setdefault(primary_area, []).append(iss)

    # Step 6: Writing reports
    print(
        "   [6/6] Writing summary and 4 detail reports to .triage-tools/reports/issues/..."
    )
    report_1_path = ISSUES_REPORTS_DIR / "1_resolved_by_open_prs.md"
    generate_report_1_resolved_by_prs(pr_to_issues, report_1_path)

    report_2_path = ISSUES_REPORTS_DIR / "2_duplicate_and_crash_clusters.md"
    generate_report_2_duplicate_clusters(clusters, issue_to_prs, report_2_path)

    report_3_path = ISSUES_REPORTS_DIR / "3_quick_win_candidates.md"
    generate_report_3_quick_wins(top_15_quick_wins, top_5_quick_wins, report_3_path)

    report_4_path = ISSUES_REPORTS_DIR / "4_stale_and_needs_info.md"
    generate_report_4_stale_and_needs_info(
        stale_data[0], stale_data[1], stale_data[2], report_4_path
    )

    summary_path = REPORTS_DIR / "issue_triage.md"
    generate_executive_summary(
        issues,
        pr_to_issues,
        clusters,
        top_15_quick_wins,
        stale_data,
        by_area,
        summary_path,
    )

    print(f"\n[OK] Deep issue triage complete! Executive Summary: {summary_path}")
    print(f"     Sub-reports saved to: {ISSUES_REPORTS_DIR}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="SolidCraft-style Triage CLI for paperless-mobile"
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser(
        "overview", help="Compare all upstream branches against upstream/development"
    )

    p_prs = sub.add_parser("prs", help="Triage open Pull Requests")
    p_prs.add_argument(
        "--verify",
        action="store_true",
        help="Rebase & run dart analyze in .worktrees/pr-sandbox",
    )
    p_prs.add_argument(
        "--pr",
        type=int,
        nargs="+",
        help="One or more PR numbers (e.g. --pr 703 702 695)",
    )

    sub.add_parser(
        "issues", help="Categorize open issues and generate Markdown triage report"
    )

    args = parser.parse_args()
    if args.cmd == "overview":
        cmd_overview(args)
    elif args.cmd == "prs":
        cmd_prs(args)
    elif args.cmd == "issues":
        cmd_issues(args)


if __name__ == "__main__":
    main()
