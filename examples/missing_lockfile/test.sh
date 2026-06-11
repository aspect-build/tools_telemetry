#!/usr/bin/env bash
# Integration test: telemetry is sent on BOTH invocations when no lockfile is present.
# Requires Bazel 9+ (facts API needed to persist notice_version across invocations).
#
# Without a lockfile the facts API has no stored notice_version, so the extension
# cannot know whether the notice was previously shown. We therefore expect curl to
# be called on every build in this scenario.
#
# NOTE: This test is expected to FAIL until the extension is updated to handle the
# missing-lockfile case by sending telemetry regardless.
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

echo "=== Run 1: no lockfile present, expect curl IS called ==="
rm -f "$EXAMPLE_DIR/MODULE.bazel.lock"
ASPECT_TOOLS_TELEMETRY_TEST=1 USE_BAZEL_VERSION=9.x bazel --output_base="$OUTPUT_BASE" build //:report \
    --lockfile_mode=update \
    --repo_env "PATH=${REPO_ENV_PATH}" \
    2>&1 | tee "$RUN1_LOG"

if [[ ! -f "$CURL_LOG" ]]; then
    echo "FAIL: curl was not called on first run (expected a call)"
    exit 1
fi
echo "PASS: curl called on first run"
rm -f "$CURL_LOG"

echo "=== Run 2: no lockfile present, expect curl IS called ==="
rm -f "$EXAMPLE_DIR/MODULE.bazel.lock"
ASPECT_TOOLS_TELEMETRY_TEST=2 USE_BAZEL_VERSION=9.x bazel --output_base="$OUTPUT_BASE" build //:report \
    --lockfile_mode=update \
    --repo_env "PATH=${REPO_ENV_PATH}" \
    2>&1 | tee "$RUN2_LOG"

if [[ ! -f "$CURL_LOG" ]]; then
    echo "FAIL: curl was not called on second run (expected a call)"
    exit 1
fi
echo "PASS: curl called on second run"
echo "curl args: $(cat "$CURL_LOG")"
