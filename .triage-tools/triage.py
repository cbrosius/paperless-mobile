#!/usr/bin/env python3
"""
Local Triage & PR Verification Tool for paperless-mobile (SolidCraft-inspired).
Supports multi-PR verification, non-destructive report updates, and per-PR diff dossiers.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

UPSTREAM_REPO = "astubenbord/paperless-mobile"
SANDBOX_DIR = Path(".worktrees/pr-sandbox")
REPORTS_DIR = Path(".triage-tools/reports")
PR_DOSSIERS_DIR = REPORTS_DIR / "prs"

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


def cmd_issues(_args: argparse.Namespace) -> None:
    issues = gh_json(
        [
            "issue",
            "list",
            "--state",
            "open",
            "--limit",
            "200",
            "--json",
            "number,title,author,createdAt,updatedAt,labels,body,comments,url",
        ]
    )
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)

    by_area: dict[str, list[dict]] = {}
    needs_info_candidates = []

    for iss in issues:
        body = iss.get("body") or ""
        areas = infer_areas_from_text(iss["title"], body)
        primary_area = areas[0]
        by_area.setdefault(primary_area, []).append(iss)

        has_version = any(
            v in body.lower()
            for v in ["v4.", "v3.", "4.5.0", "paperless-ngx", "version"]
        )
        if len(body.strip()) < 120 or not has_version:
            needs_info_candidates.append(iss)

    lines = [
        "# Issue Triage Report (`paperless-mobile`)",
        f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        f"Total open issues analyzed: **{len(issues)}**\n",
        "## 1. Distribution by Area",
    ]
    for area, items in sorted(by_area.items(), key=lambda x: len(x[1]), reverse=True):
        lines.append(f"- **`{area}`**: {len(items)} issues")

    shown_needs_info = needs_info_candidates[:30]
    lines.append(
        f"\n## 2. `needs-info` Candidates ({len(needs_info_candidates)} issues missing version/details)"
    )
    lines.append("<details>")
    lines.append(
        f"<summary>Show {len(shown_needs_info)} <code>needs-info</code> candidates (of {len(needs_info_candidates)} total)</summary>\n"
    )
    lines.append("| Issue | Title | Created | Reason |")
    lines.append("| :--- | :--- | :--- | :--- |")
    for iss in shown_needs_info:
        clean_title = iss["title"].replace("\n", " ").replace("\r", " ")[:90]
        lines.append(
            f"| [#{iss['number']}]({iss['url']}) | {clean_title} | {iss['createdAt'][:10]} | Short description or missing version |"
        )
    lines.append("\n</details>")

    lines.append("\n## 3. Issues Grouped by Area")
    for area, items in sorted(by_area.items(), key=lambda x: len(x[1]), reverse=True):
        lines.append(f"\n### `{area}` ({len(items)})")
        lines.append("<details>")
        lines.append(
            f"<summary>Show all {len(items)} issues in <code>{area}</code></summary>\n"
        )
        for iss in items:
            clean_title = iss["title"].replace("\n", " ").replace("\r", " ")[:100]
            existing_labels = ", ".join(l["name"] for l in iss.get("labels", []))
            lbl_str = f" *[{existing_labels}]*" if existing_labels else ""
            lines.append(
                f"- [#{iss['number']}]({iss['url']}) **{clean_title}** ({iss['createdAt'][:10]}){lbl_str}"
            )
        lines.append("\n</details>")

    report_path = REPORTS_DIR / "issue_triage.md"
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[OK] Full issue report saved to: {report_path}")


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
