#!/usr/bin/env bash
# Integration test: telemetry notice is shown on first invocation, curl is called on second.
# Requires Bazel 9+ (facts API needed to persist notice_version across invocations).
#
# ASPECT_TOOLS_TELEMETRY_TEST is observed by the extension via module_ctx.getenv(), so
# changing its value between runs forces Bazel to re-evaluate the extension. On re-evaluation
# the extension reads notice_version from the stored facts and the repo rule proceeds to call
# curl.
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

rm -f "$EXAMPLE_DIR/MODULE.bazel.lock"

OUTPUT_BASE="$WORK_DIR/output"
REPO_ENV_PATH="${FAKE_CURL_DIR}:${PATH}"

cd "$EXAMPLE_DIR"

echo "=== Run 1: expect NO curl call (first invocation shows notice, skips send) ==="
ASPECT_TOOLS_TELEMETRY_TEST=1 USE_BAZEL_VERSION=9.x bazel --output_base="$OUTPUT_BASE" build //:report \
    --lockfile_mode=update \
    --repo_env "PATH=${REPO_ENV_PATH}"

if [[ -f "$CURL_LOG" ]]; then
    echo "FAIL: curl was called on first run (expected no call)"
    exit 1
fi
echo "PASS: curl not called on first run"

echo "=== Run 2: expect curl IS called (notice already shown, data may be sent) ==="
# Changing ASPECT_TOOLS_TELEMETRY_TEST forces extension re-evaluation. This time the extension
# should invoke curl to upload telemetry data.
ASPECT_TOOLS_TELEMETRY_TEST=2 USE_BAZEL_VERSION=9.x bazel --output_base="$OUTPUT_BASE" build //:report \
    --lockfile_mode=update \
    --repo_env "PATH=${REPO_ENV_PATH}"

if [[ ! -f "$CURL_LOG" ]]; then
    echo "FAIL: curl was not called on second run (expected a call)"
    exit 1
fi
echo "PASS: curl called on second run"
echo "curl args: $(cat "$CURL_LOG")"
