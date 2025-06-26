# aspect_tools_telemetry

Aspect's ruleset useage telemetry Bazel module.

This package defines a bzlmod extension which allows for Aspect rulesets to report useage to Aspect, which allows us to estimate the install base of our rulesets and monitor version skew in the ecosystem.

## Usage

```
# MODULE.bazel
bazel_dep(name = "aspect_telemetry", version = "0.1.0")

tel = use_extension("@aspect_telemetry//:extension.bzl", "telemetry")
tel.report()
use_repo(tel, "aspect_tools_telemetry_report")

# ruleset defs.bzl
load("@aspect_tools_telemetry_report//:defs.bzl", "TELEMETRY") # buildifier: disable=load
```

## When reporting occurs
`tools_telemetry` is implemented as a Bazel module which performs side-effects.
This means that telemetry is collected at repository granularity when Bazel modules are invalidated and re-evaluate.

Examples:
- A user adding a new Bazel dependency will invalidate modules and trigger reporting
- A user making a local code change and performing a build will not trigger reporting

## Controlling reporting
The telemetry module can be controlled by setting the `ASPECT_TOOLS_TELEMETRY` environment variable.
`ASPECT_TOOLS_TELEMETRY` is a comma joined list of reporting features using Bazel's set notation.
If `ASPECT_TOOLS_TELEMETRY` is not set, a warning that telemetry is being collected will be generated and data will be reported.
If `ASPECT_TOOLS_TELEMETRY` is set to the empty string, no data will be reported.

## Reporting features
- `id`: A hash of the repo is used as a stable anonymous ID
- `org`: An organization name string is reported if available
- `buildci`: Is the build occurring in CI or locally
- `buildnum`: The build counter if available
- `deps`: The Aspect rulesets and their versions which are in use

## Example configurations

``` shell
--repo_env=ASPECT_TOOLS_TELEMETRY=     # disabled
--repo_env=ASPECT_TOOLS_TELEMETRY=-all # also disabled
--repo_env=ASPECT_TOOLS_TELEMETRY=all  # enabled (default)
--repo_env=ASPECT_TOOLS_TELEMETRY=-org # just disable org name reporting
--repo_env=ASPECT_TOOLS_TELEMETRY=deps # only report aspect deps
```

## Report inspection

For transparency reports are persisted into the Bazel configuration and can be inspected as `@aspect_tools_telemetry_report//:report.json`
