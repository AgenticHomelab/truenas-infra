#!/usr/bin/env bash
# Offline publication CI only. Reports stay in RUNNER_TEMP and are never uploaded.
set -euo pipefail
python3 -m venv "$RUNNER_TEMP/security-venv"
"$RUNNER_TEMP/security-venv/bin/pip" install --disable-pip-version-check detect-secrets==1.5.0
mkdir -p "$RUNNER_TEMP/public-tools"
GOBIN="$RUNNER_TEMP/public-tools" go install github.com/zricethezav/gitleaks/v8@v8.24.2
cd "$RUNNER_TEMP/public-candidate"
test ! -e .git
# OpenTofu init created disposable provider caches after export validation.
# Remove only these caches inside RUNNER_TEMP so scanners see export bytes.
for root in acme identities storage; do
  rm -rf -- "$root/.terraform"
  test ! -e "$root/.terraform"
done
set +e
"$RUNNER_TEMP/public-tools/gitleaks" dir . --redact --report-format json --report-path "$RUNNER_TEMP/gitleaks-public.json" > /dev/null 2>&1
gitleaks_rc=$?
"$RUNNER_TEMP/security-venv/bin/detect-secrets" scan --all-files . > "$RUNNER_TEMP/detect-public.json" 2> /dev/null
detect_rc=$?
set -e
"$RUNNER_TEMP/security-venv/bin/python" - "$RUNNER_TEMP/gitleaks-public.json" "$RUNNER_TEMP/detect-public.json" "$gitleaks_rc" "$detect_rc" <<'PY'
import json
from pathlib import Path
import sys

gitleaks_report = Path(sys.argv[1])
detect_report = Path(sys.argv[2])
gitleaks_rc, detect_rc = map(int, sys.argv[3:])
try:
    gitleaks_findings = len(json.loads(gitleaks_report.read_text())) if gitleaks_report.exists() else 0
    detect_findings = sum(len(hits) for hits in json.loads(detect_report.read_text())["results"].values())
except (OSError, ValueError, KeyError, TypeError):
    print("Secret scanner failed to produce a parseable private report")
    sys.exit(1)
print(f"Gitleaks: {gitleaks_findings} potential findings; detect-secrets: {detect_findings} potential findings")
if gitleaks_findings:
    for finding in json.loads(gitleaks_report.read_text()):
        path = Path(finding.get("File", "")).as_posix()
        print("Gitleaks candidate location:", path, "rule:", finding.get("RuleID", "?"), "line:", finding.get("StartLine", "?"))
if detect_findings:
    for filename, items in json.loads(detect_report.read_text())["results"].items():
        for finding in items:
            print("detect-secrets candidate location:", filename, "type:", finding.get("type", "?"), "line:", finding.get("line_number", "?"))
if gitleaks_rc not in (0, 1) or detect_rc != 0 or gitleaks_findings or detect_findings or gitleaks_rc:
    sys.exit(1)
PY
