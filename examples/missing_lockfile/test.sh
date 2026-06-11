#!/usr/bin/env bash
# Integration test: behaviour when MODULE.bazel.lock is absent on the first build.
# Requires Bazel 9+ (facts API needed to persist notice_version across invocations).
#
# Run 1 (no lockfile): the extension cannot verify whether the notice was previously
# shown, so it uploads telemetry immediately and prints a one-time notice.
# Run 2 (lockfile created by run 1): notice already acknowledged; telemetry is sent
# silently with no message printed.
#
# ASPECT_TOOLS_TELEMETRY_TEST is observed by the extension via module_ctx.getenv(), so
# changing its value between runs forces Bazel to re-evaluate the extension.
set -o errexit -o nounset -o pipefail

EXAMPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
CURL_LOG="$WORK_DIR/curl_calls.log"
FAKE_CURL_DIR="$WORK_DIR/bin"
mkdir -p "$FAKE_CURL_DIR"
cat > "$FAKE_CURL_DIR/curl" <<EOF
#!/usr/bin/env bash
echo "invoked: \$*" >> "$CURL_LOG"
EOF
chmod +x "$FAKE_CURL_DIR/curl"

OUTPUT_BASE="$WORK_DIR/output"
REPO_ENV_PATH="${FAKE_CURL_DIR}:${PATH}"

cd "$EXAMPLE_DIR"

RUN1_LOG="$WORK_DIR/run1.log"
RUN2_LOG="$WORK_DIR/run2.log"

echo "=== Run 1: no lockfile present, expect uploading notice and curl IS called ==="
rm -f "$EXAMPLE_DIR/MODULE.bazel.lock"
ASPECT_TOOLS_TELEMETRY_TEST=1 USE_BAZEL_VERSION=9.x bazel --output_base="$OUTPUT_BASE" build //:report \
    --lockfile_mode=update \
    --repo_env "PATH=${REPO_ENV_PATH}" \
    2>&1 | tee "$RUN1_LOG"

if ! grep -q "now and on future builds" "$RUN1_LOG"; then
    echo "FAIL: uploading notice was not printed on first run (expected notice)"
    exit 1
fi
echo "PASS: uploading notice printed on first run"

if [[ ! -f "$CURL_LOG" ]]; then
    echo "FAIL: curl was not called on first run (expected a call)"
    exit 1
fi
echo "PASS: curl called on first run"
rm -f "$CURL_LOG"

echo "=== Run 2: lockfile now present, expect no notice and curl IS called ==="
# Do NOT delete the lockfile — run 1 created it with notice_version stored in facts.
ASPECT_TOOLS_TELEMETRY_TEST=2 USE_BAZEL_VERSION=9.x bazel --output_base="$OUTPUT_BASE" build //:report \
    --lockfile_mode=update \
    --repo_env "PATH=${REPO_ENV_PATH}" \
    2>&1 | tee "$RUN2_LOG"

if grep -q "Aspect Telemetry" "$RUN2_LOG"; then
    echo "FAIL: telemetry notice was printed on second run (expected no message)"
    exit 1
fi
echo "PASS: no telemetry notice on second run"

if [[ ! -f "$CURL_LOG" ]]; then
    echo "FAIL: curl was not called on second run (expected a call)"
    exit 1
fi
echo "PASS: curl called on second run"
echo "curl args: $(cat "$CURL_LOG")"
