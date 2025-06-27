# aspect_tools_telemetry

Aspect's ruleset telemetry Bazel module.

This package defines a bzlmod extension which allows for rulesets to report useage to Aspect, which allows us to estimate the install base of our rulesets and monitor trends in the ecosystem.

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
This means that telemetry is collected at repository granularity only when Bazel modules are invalidated and re-evaluate.

Examples:
- A user adding a new Bazel dependency will invalidate modules and trigger reporting
- A user making a local code change and performing a build will not trigger reporting

## Controlling reporting
The telemetry module honors `$DO_NOT_TRACK` and will disable itself if this variable is set.

The telemetry module can be controlled at a finer grain by setting the `$ASPECT_TOOLS_TELEMETRY` environment variable.
`ASPECT_TOOLS_TELEMETRY` is a comma joined list of reporting features using Bazel's set notation.

### Example configurations

``` shell
--repo_env=ASPECT_TOOLS_TELEMETRY=     # disabled
--repo_env=ASPECT_TOOLS_TELEMETRY=-all # also disabled
--repo_env=ASPECT_TOOLS_TELEMETRY=all  # enabled (default)
--repo_env=ASPECT_TOOLS_TELEMETRY=-org # just disable org name reporting
--repo_env=ASPECT_TOOLS_TELEMETRY=deps # only report aspect deps
```

## Reporting features
- `id`: A hash of the repo is used as a stable anonymous ID
- `org`: An organization name string is reported if available
- `ci`: Is the build occurring in CI/CD or locally
- `runner`: The CI/CD system being used if any
- `counter`: The build counter if available
- `deps`: The Aspect rulesets and their versions which are in use

### Example report

```json
{
  "ci": true,
  "counter": [
    "678",
    "0"
  ],
  "deps": [
    [
      "simple-example",
      "0.0.0"
    ],
    [
      "aspect_tools_telemetry",
      "0.0.0"
    ]
  ],
  "id": "x32faf8f6",
  "org": "aspect-build",
  "runner": "buildkite"
}
```

## Example exploration

The included examples/simple submodule provides a sandbox for easily testing the temeletry module's behavior.

``` shellsession
❯ cd examples/simple
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

For transparency reports are persisted into the Bazel configuration and can be inspected as `@aspect_tools_telemetry_report//:report.json`

## Privacy policy

https://www.aspect.build/privacy
