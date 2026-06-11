"""
Telemetry bound for Aspect.

These metrics are designed to tell us at a coarse grain:
- Who (organizations) is using Bazel and our rulesets
- How heavily (number of builds cf. German tank problem)
- What rules are in use
- What CI platform(s) are in use

For transparency the report data we submit is persisted
as @aspect_telemetry_report//:report.json
"""

load("//collectors:basics.bzl", register_basics="register")
load("//collectors:bazel.bzl", register_bazel="register")
load("//collectors:ci.bzl", register_ci="register")
load("//collectors:fingerprinting.bzl", register_fingerprints="register")


TELEMETRY_ENV_VAR = "ASPECT_TOOLS_TELEMETRY"
TELEMETRY_DEST_VAR = "ASPECT_TOOLS_TELEMETRY_ENDPOINT"
TELEMETRY_DEST = "https://telemetry.aspect.build/ingest?source=tools_telemetry"

# Increment when the notice should be re-broadcasted to users such as text changes or data collection changes.
_NOTICE_VERSION = 1
_NOTICE = """\
Aspect Telemetry will begin collecting usage data on the next invocation, pursuant to the https://aspect.build/privacy-policy.
See https://github.com/aspect-build/tools_telemetry for details.
"""
_NOTICE_UPLOADING = """\
Aspect Telemetry is uploading usage data now and on future builds, pursuant to the https://aspect.build/privacy-policy.
See https://github.com/aspect-build/tools_telemetry for details.
"""


def parse_opt_out(flag, default=[], groups={}):
    """
    Parse Bazel-style set semantics flags.

    - If the user specifies unqualified value(s) the default is ignored
    - If the user specifies + qualfied value(s) those should be added
    - If the user specifies - qualified value(s) those cannot occur in the output
    """

    terms = flag.split(",")
    acc = {}

    specified = []
    added = []
    removed = []

    def _handle(acc, term):
        if term in groups:
            for subterm in groups[term]:
                acc.append(subterm)
        else:
            acc.append(term)

    for term in terms:
        term = term.strip().lower()
        if not term:
            continue

        if term.startswith("-"):
            term = term[1:]
            _handle(removed, term)

        elif term.startswith("+"):
            term = term[1:]
            _handle(added, term)

        else:
            _handle(specified, term)

    if not specified:
        specified = default

    for it in specified:
        acc[it] = 1
    for it in added:
        acc[it] = 1
    for it in removed:
        acc[it] = -1

    return [k for k, v in acc.items() if v == 1]


def _tel_repository_impl(repository_ctx):
    ## Try to find a curl
    curl = repository_ctx.which("curl") or repository_ctx.which("curl.exe")

    ## Figure out where we scribe to
    # Note that this allows the endpoint to be overriden
    endpoint = repository_ctx.os.environ.get(TELEMETRY_DEST_VAR)
    if endpoint == None:
        endpoint = TELEMETRY_DEST

    ## Parse the feature flagging var
    tel_val = repository_ctx.os.environ.get(TELEMETRY_ENV_VAR)

    if repository_ctx.os.environ.get("DO_NOT_TRACK"):
        allowed_val = "-all"
    elif tel_val:
        allowed_val = tel_val
    else:
        allowed_val = "all"

    registry = (
        {}
        | register_basics()
        | register_bazel()
        | register_ci()
        | register_fingerprints()
    )

    features = registry.keys()
    groups = {
        "all": features,
    }
    allowed_telemetry = parse_opt_out(allowed_val or "all", features, groups)

    ## Collect enabled data
    telemetry = {}
    for feature, handler in registry.items():
        if feature in allowed_telemetry:
            telemetry[feature] = handler(repository_ctx)

    ## Wrap it up in the tools_telemetry envelope
    if telemetry:
        telemetry = {"tools_telemetry": telemetry}

    ## Lay down report files
    telemetry_file = repository_ctx.file(
        "report.json",
        json.encode_indent(telemetry, indent="  "),
    )

    defs_file = repository_ctx.file(
        "defs.bzl",
        """\
TELEMETRY = 1
        """
    )

    repository_ctx.file(
        "BUILD.bazel",
        """\
exports_files(["report.json", "defs.bzl"], visibility = ["//visibility:public"])
"""
    )

    # Notify and skip sending if telemetry was not explicitly configured
    # and the notice has not been seen before.
    # If MODULE.bazel.lock is absent we cannot verify whether the notice was
    # previously shown, so we skip the notice and proceed to send telemetry.
    lockfile_present = repository_ctx.workspace_root.get_child("MODULE.bazel.lock").exists
    if lockfile_present and allowed_telemetry and not repository_ctx.os.environ.get(TELEMETRY_ENV_VAR) and repository_ctx.attr.last_notice != _NOTICE_VERSION:
        # buildifier: disable=print
        print(_NOTICE)
        return

    if not lockfile_present and allowed_telemetry and not repository_ctx.os.environ.get(TELEMETRY_ENV_VAR):
        # buildifier: disable=print
        print(_NOTICE_UPLOADING)

    ## Send the report if enabled
    # Note that ANY of these things will disable telemetry
    if curl and endpoint and allowed_telemetry:
        # Note that errors are silent, no attempt is made at caching/slabbing
        repository_ctx.execute([
          curl, "--location",
                "--max-time", "1",
                "--connect-timeout", "0.5",
                "--request", "POST",
                # Persist the POST method across redirects. Maddeningly this is
                # the RFC specified behavior but almost no client originaly
                # behaved this way so cURL jumps off a cliff too like its
                # friends and we have to tell it to follow the spec. Ideally
                # we'd serve 307s instead but we may not be able to.
                "--post302",
                "--header", "Content-Type:application/json",
                "--data", "@report.json",
                endpoint],
          timeout=2
        )


tel_repository = repository_rule(
    implementation = _tel_repository_impl,
    attrs = {
        "deps": attr.string_dict(),
        "last_notice": attr.int(default = 0),
    },
)

def _tel_impl(module_ctx):
    # Use the Bazel 9 facts API to persist the last notice shown
    last_notice = _NOTICE_VERSION
    if hasattr(module_ctx, "facts"):
        last_notice = int(module_ctx.facts.get("notice_version", "0"))

    # Observed purely so tests can force extension re-evaluation by changing its value.
    if hasattr(module_ctx, "getenv"):
        module_ctx.getenv("ASPECT_TOOLS_TELEMETRY_TEST")

    tel_repository(
        name = "aspect_tools_telemetry_report",
        deps = {it.name: it.version for it in module_ctx.modules},
        last_notice = last_notice,
    )

    if hasattr(module_ctx, "facts"):
        return module_ctx.extension_metadata(
            facts = {"notice_version": str(_NOTICE_VERSION)},
        )

# TODO: Should the extension in the main module be able to set telemetry feature
# flags or do we want to stick with environment variables.
telemetry = module_extension(
    implementation = _tel_impl,
)
