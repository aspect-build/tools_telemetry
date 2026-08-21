#!/usr/bin/env bash
# Integration test: telemetry notice is shown on first invocation, curl is called on
# second, and a repository without a lockfile gets the louder uploading notice and a
# curl call on every invocation (the record that the notice was shown persists via the
# lockfile, so without one every evaluation is a first evaluation).
# Requires Bazel 8.5+ (facts API needed to persist notice_version across invocations).
#
# ASPECT_TOOLS_TELEMETRY_TEST is observed by the extension via module_ctx.getenv(), so
# changing its value between runs forces Bazel to re-evaluate the extension. On re-evaluation
# the extension reads notice_version from the stored facts and the repo rule proceeds to call
# curl.
set -o errexit -o nounset -o pipefail

EXAMPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORK_DIR="$(mktemp -d)"
restore_lockfile() {
    git -C "$EXAMPLE_DIR" restore MODULE.bazel.lock
}
trap 'restore_lockfile; rm -rf "$WORK_DIR"' EXIT
CURL_LOG="$WORK_DIR/curl_calls.log"
FAKE_CURL_DIR="$WORK_DIR/bin"
mkdir -p "$FAKE_CURL_DIR"
cat > "$FAKE_CURL_DIR/curl" <<EOF
#!/usr/bin/env bash
echo "invoked: \$*" >> "$CURL_LOG"
EOF
chmod +x "$FAKE_CURL_DIR/curl"

restore_lockfile

OUTPUT_BASE="$WORK_DIR/output"
REPO_ENV_PATH="${FAKE_CURL_DIR}:${PATH}"

cd "$EXAMPLE_DIR"

RUN1_LOG="$WORK_DIR/run1.log"
RUN2_LOG="$WORK_DIR/run2.log"

echo "=== Run 1: expect notice printed, NO curl call (first invocation) ==="
ASPECT_TOOLS_TELEMETRY_TEST=1 USE_BAZEL_VERSION=9.x bazel --output_base="$OUTPUT_BASE" build //:report \
    --lockfile_mode=update \
    --repo_env "PATH=${REPO_ENV_PATH}" \
    2>&1 | tee "$RUN1_LOG"

if ! grep -q "Aspect Telemetry will begin collecting" "$RUN1_LOG"; then
    echo "FAIL: notice was not printed on first run (expected notice)"
    exit 1
fi
echo "PASS: notice printed on first run"

if [[ -f "$CURL_LOG" ]]; then
    echo "FAIL: curl was called on first run (expected no call)"
    exit 1
fi
echo "PASS: curl not called on first run"

echo "=== Run 2: expect NO notice printed, curl IS called (notice already shown) ==="
# Changing ASPECT_TOOLS_TELEMETRY_TEST forces extension re-evaluation. This time the extension
# should invoke curl to upload telemetry data.
ASPECT_TOOLS_TELEMETRY_TEST=2 USE_BAZEL_VERSION=9.x bazel --output_base="$OUTPUT_BASE" build //:report \
    --lockfile_mode=update \
    --repo_env "PATH=${REPO_ENV_PATH}" \
    2>&1 | tee "$RUN2_LOG"

if grep -q "Aspect Telemetry will begin collecting" "$RUN2_LOG"; then
    echo "FAIL: notice was printed on second run (expected no notice)"
    exit 1
fi
echo "PASS: notice not printed on second run"

if [[ ! -f "$CURL_LOG" ]]; then
    echo "FAIL: curl was not called on second run (expected a call)"
    exit 1
fi
echo "PASS: curl called on second run"
echo "curl args: $(cat "$CURL_LOG")"

echo "=== Runs 3 and 4: no lockfile; expect the uploading notice AND a curl call every run ==="
# Without MODULE.bazel.lock the shown-notice record cannot persist, so every
# evaluation is a first evaluation. --lockfile_mode=off keeps Bazel from
# recreating the file between runs, and each run gets a fresh output base to
# model the realistic lockfile-less case: ephemeral CI, where the repository
# rule runs every job.
rm -f "$EXAMPLE_DIR/MODULE.bazel.lock"

for run in 3 4; do
    RUN_LOG="$WORK_DIR/run$run.log"
    ASPECT_TOOLS_TELEMETRY_TEST="$run" USE_BAZEL_VERSION=9.x bazel --output_base="$WORK_DIR/output-nolock-$run" build //:report \
        --lockfile_mode=off \
        --repo_env "PATH=${REPO_ENV_PATH}" \
        2>&1 | tee "$RUN_LOG"

    if ! grep -q "Aspect Telemetry is uploading" "$RUN_LOG"; then
        echo "FAIL: uploading notice was not printed on lockfile-less run $run (expected every run)"
        exit 1
    fi
    echo "PASS: uploading notice printed on lockfile-less run $run"

    if [[ ! -f "$CURL_LOG" ]]; then
        echo "FAIL: curl was not called on lockfile-less run $run (expected a call every run)"
        exit 1
    fi
    echo "PASS: curl called on lockfile-less run $run"
    rm -f "$CURL_LOG"
done
