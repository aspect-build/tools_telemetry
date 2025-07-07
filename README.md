# aspect_tools_telemetry

Aspect's ruleset telemetry Bazel module.

This package defines a bzlmod extension which allows for rulesets to report usage to Aspect, allowing us to estimate the install base of Bazel, rulesets, and monitor trends in the ecosystem.

Telemetry is enabled by default, but prompts the user opt in/out as part of the build configuration.

## Usage

```
# ruleset MODULE.bazel
bazel_dep(name = "aspect_telemetry", version = "0.1.0")

tel = use_extension("@aspect_telemetry//:extension.bzl", "telemetry")
tel.report()
use_repo(tel, "aspect_tools_telemetry_report")

# ruleset defs.bzl
load("@aspect_tools_telemetry_report//:defs.bzl", "TELEMETRY") # buildifier: disable=load
```

## When reporting occurs

`aspect_tools_telemetry` is implemented as a Bazel module which performs side-effects.
This means that telemetry is collected at repository granularity only when Bazel modules are invalidated and re-evaluated.

Examples:
- A user adding a new Bazel dependency will invalidate modules and trigger reporting
- A user making a local code change and performing a build will not trigger reporting

## Controlling reporting

The telemetry module honors `$DO_NOT_TRACK` and will disable itself if this variable is set.

The telemetry module can be controlled at a finer granularity by setting the `$ASPECT_TOOLS_TELEMETRY` environment variable.
`ASPECT_TOOLS_TELEMETRY` is a comma joined list of reporting features using Bazel's set notation.

### Example configurations

``` shell
--repo_env=ASPECT_TOOLS_TELEMETRY=all  # enabled (default)
--repo_env=ASPECT_TOOLS_TELEMETRY=deps # only report aspect deps

--repo_env=ASPECT_TOOLS_TELEMETRY=     # disabled
--repo_env=ASPECT_TOOLS_TELEMETRY=-all # also disabled
--repo_env=ASPECT_TOOLS_TELEMETRY=-org # just disable org name reporting
```

We suggest setting one of these options in your `.bazelrc`

## Reporting features

- `id`: A hash of the repo is used as a stable pseudononymous ID
- `user`: A hash of the commit author or build user's name
- `ci`: Is the build occurring in CI/CD or locally
- `runner`: The CI/CD system being used if any
- `counter`: The build counter if available
- `deps`: The active set of bzlmod modules from the public registry
- `org`: A human readable organization name string

### Example report

```json
{
  "ci": true,
  "counter": [
    "678",
    "0"
  ],
  "deps": {
    "abseil-cpp": "20240116.1",
    "aspect_bazel_lib": "2.19.4",
    "bazel_features": "1.30.0",
    "bazel_skylib": "1.8.0",
    "buildozer": "7.1.2",
    "googletest": "1.14.0.bcr.1",
    "jq.bzl": "0.1.0",
    "jsoncpp": "1.9.5",
    "package_metadata": "0.0.2",
    "platforms": "0.0.11",
    "protobuf": "29.0",
    "pybind11_bazel": "2.11.1",
    "re2": "2023-09-01",
    "rules_android": "0.1.1",
    "rules_cc": "0.1.1",
    "rules_fuzzing": "0.5.2",
    "rules_java": "8.12.0",
    "rules_jvm_external": "6.3",
    "rules_kotlin": "1.9.6",
    "rules_license": "1.0.0",
    "rules_pkg": "1.0.1",
    "rules_proto": "7.0.2",
    "rules_python": "0.40.0",
    "rules_shell": "0.4.1",
    "stardoc": "0.7.1",
    "tar.bzl": "0.2.1",
    "yq.bzl": "0.1.1",
    "zlib": "1.3.1.bcr.5"
  },
  "id": "32faf8f6",
  "runner": "jenkins",
  "org": "aspect-build",
  "user": "53fe1df5"
}
```

## Example exploration

The included examples/simple submodule provides a sandbox for easily testing the telemetry module's behavior.

``` shellsession
❯ cd examples/simple

# Default unconfigured behavior
❯ bazel build \
    --repo_env=CI=1 \
    --repo_env=DRONE_BUILD_NUMBER=678 \
    --repo_env=GIT_URL=http://github.com/aspect-build/tools_telemetry.git \
    //:report.json && cat bazel-bin/report.json
DEBUG: /private/var/tmp/_bazel_arrdem/26bdb308fe44511193031a4146df0d52/external/aspect_tools_telemetry+/extension.bzl:246:14:
\x1B[36maspect_tools_telemetry\x1B[0m is loaded but not configured.

Telemtry is enabled by default.

To accept diagnostic telemetry, add this entry to your .bazelrc
    common --repo_env=ASPECT_TOOLS_TELEMETRY=all

For more details and configuration options please see
    https://github.com/aspect-build/tools_telemetry

INFO: Analyzed target //:report.json (7 packages loaded, 10 targets configured).
INFO: Found 1 target...
Target //:report.json up-to-date:
  bazel-bin/report.json
INFO: Elapsed time: 0.300s, Critical Path: 0.03s
INFO: 2 processes: 1 internal, 1 darwin-sandbox.
INFO: Build completed successfully, 2 total actions
{
  "ci": true,
  "counter": [
    "678",
    "0"
  ],
  "deps": {
    "abseil-cpp": "20240116.1",
    "aspect_bazel_lib": "2.19.4",
    "bazel_features": "1.30.0",
    "bazel_skylib": "1.8.0",
    "buildozer": "7.1.2",
    "googletest": "1.14.0.bcr.1",
    "jq.bzl": "0.1.0",
    "jsoncpp": "1.9.5",
    "package_metadata": "0.0.2",
    "platforms": "0.0.11",
    "protobuf": "29.0",
    "pybind11_bazel": "2.11.1",
    "re2": "2023-09-01",
    "rules_android": "0.1.1",
    "rules_cc": "0.1.1",
    "rules_fuzzing": "0.5.2",
    "rules_java": "8.12.0",
    "rules_jvm_external": "6.3",
    "rules_kotlin": "1.9.6",
    "rules_license": "1.0.0",
    "rules_pkg": "1.0.1",
    "rules_proto": "7.0.2",
    "rules_python": "0.40.0",
    "rules_shell": "0.4.1",
    "stardoc": "0.7.1",
    "tar.bzl": "0.2.1",
    "yq.bzl": "0.1.1",
    "zlib": "1.3.1.bcr.5"
  },
  "id": "32faf8f6",
  "org": null,
  "runner": "drone",
  "user": "53fe1df5"
}%

# Enabled behavior
❯ bazel build \
    --repo_env=ASPECT_TOOLS_TELEMETRY=all \
    --repo_env=CI=1 --repo_env=DRONE_BUILD_NUMBER=678 \
    --repo_env=GIT_URL=http://github.com/aspect-build/tools_telemetry.git \
    //:report.json && cat bazel-bin/report.json
INFO: Analyzed target //:report.json (7 packages loaded, 10 targets configured).
INFO: Found 1 target...
Target //:report.json up-to-date:
  bazel-bin/report.json
INFO: Elapsed time: 0.103s, Critical Path: 0.02s
INFO: 2 processes: 1 internal, 1 darwin-sandbox.
INFO: Build completed successfully, 2 total actions
{
  "ci": true,
  "counter": [
    "678",
    "0"
  ],
  "deps": {
    "abseil-cpp": "20240116.1",
    "aspect_bazel_lib": "2.19.4",
    "bazel_features": "1.30.0",
    "bazel_skylib": "1.8.0",
    "buildozer": "7.1.2",
    "googletest": "1.14.0.bcr.1",
    "jq.bzl": "0.1.0",
    "jsoncpp": "1.9.5",
    "package_metadata": "0.0.2",
    "platforms": "0.0.11",
    "protobuf": "29.0",
    "pybind11_bazel": "2.11.1",
    "re2": "2023-09-01",
    "rules_android": "0.1.1",
    "rules_cc": "0.1.1",
    "rules_fuzzing": "0.5.2",
    "rules_java": "8.12.0",
    "rules_jvm_external": "6.3",
    "rules_kotlin": "1.9.6",
    "rules_license": "1.0.0",
    "rules_pkg": "1.0.1",
    "rules_proto": "7.0.2",
    "rules_python": "0.40.0",
    "rules_shell": "0.4.1",
    "stardoc": "0.7.1",
    "tar.bzl": "0.2.1",
    "yq.bzl": "0.1.1",
    "zlib": "1.3.1.bcr.5"
  },
  "id": "32faf8f6",
  "runner": "drone"
  "org": null,
  "user": "53fe1df5"
}%

# Disabled behavior
❯ bazel build \
    --repo_env=CI=1 \
    --repo_env=BUILD_NUMBER=678 \
    --repo_env=JENKINS_HOME=$HOME \
    --repo_env=GIT_URL=http://github.com/aspect-build/tools_telemetry.git \
    --repo_env=DO_NOT_TRACK=1 //:report.json \
    && cat bazel-bin/report.json
INFO: Analyzed target //:report.json (7 packages loaded, 10 targets configured).
INFO: Found 1 target...
Target //:report.json up-to-date:
  bazel-bin/report.json
INFO: Elapsed time: 0.071s, Critical Path: 0.00s
INFO: 1 process: 1 action cache hit, 1 internal.
INFO: Build completed successfully, 1 total action
{}%
```

## Report inspection

For transparency reports are persisted into the Bazel configuration and can be inspected as `@aspect_tools_telemetry_report//:report.json`.

``` shellsession
❯ cat $(bazel query --output=location @aspect_tools_telemetry_report//:report.json | cut -d: -f1)
```

## Privacy policy

https://www.aspect.build/privacy-policy
