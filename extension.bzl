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


TELEMETRY_CONSENT_VAR = "ASPECT_TOOLS_TELEMETRY_CONSENT"
TELEMETRY_ENV_VAR = "ASPECT_TOOLS_TELEMETRY"
TELEMETRY_DEST_VAR = "ASPECT_TOOLS_TELEMETRY_ENDPOINT"
TELEMETRY_DEST = "https://telemetry.aspect.build/ingest?source=tools_telemetry"


def parse_consent(consent_val):
    """Parse the telemetry consent flag.

    The flag must be set explicitly. Returns a struct with fields:
      - allowed: True (proceed), False (opted out), or None (error/unset)
      - error: error message string if allowed is None, else None
    """
    if consent_val == None:
        return struct(
            allowed = None,
            error = """\

Aspect Build would like to gather usage data on our rulesets.
We use this data to understand which companies are using our rulesets, how heavily,
and what features are in use so that we can prioritize our work to best support our users.

-> To allow telemetry gathering, set this flag 'allow' in .bazelrc:
    common --repo_env={var}=allow

-> To opt-out, set it to 'disallow' in .bazelrc:
    common --repo_env={var}=disallow
or set the DO_NOT_TRACK environment variable to any value.

More information is at https://github.com/aspect-build/tools_telemetry
Usage of this data is subject to our privacy policy: https://aspect.build/privacy-policy

""".format(var = TELEMETRY_CONSENT_VAR),
        )
    val = consent_val.strip().lower()
    if val == "allow":
        return struct(allowed = True, error = None)
    if val == "disallow":
        return struct(allowed = False, error = None)
    return struct(
        allowed = None,
        error = "Invalid value for {var}: '{val}'. Expected 'allow' or 'disallow'.".format(
            var = TELEMETRY_CONSENT_VAR,
            val = consent_val,
        ),
    )


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


def _write_repository_files(repository_ctx, telemetry):
    repository_ctx.file("report.json", json.encode_indent(telemetry, indent="  "))
    repository_ctx.file("defs.bzl", "TELEMETRY = 1\n")
    repository_ctx.file(
        "BUILD.bazel",
        'exports_files(["report.json", "defs.bzl"], visibility = ["//visibility:public"])\n',
    )


def _tel_repository_impl(repository_ctx):
    ## Require explicit consent before collecting anything.
    ## DO_NOT_TRACK is treated as an alias for CONSENT=disallow.
    consent_val = repository_ctx.os.environ.get(TELEMETRY_CONSENT_VAR)
    if consent_val == None and repository_ctx.os.environ.get("DO_NOT_TRACK"):
        consent_val = "disallow"
    consent = parse_consent(consent_val)
    if consent.error:
        fail(consent.error)

    if not consent.allowed:
        ## User opted out - write empty repository files and stop
        _write_repository_files(repository_ctx, {})
        return

    ## Try to find a curl
    curl = repository_ctx.which("curl") or repository_ctx.which("curl.exe")

    ## Figure out where we scribe to
    # Note that this allows the endpoint to be overriden
    endpoint = repository_ctx.os.environ.get(TELEMETRY_DEST_VAR)
    if endpoint == None:
        endpoint = TELEMETRY_DEST

    ## Parse the feature flagging var
    tel_val = repository_ctx.os.environ.get(TELEMETRY_ENV_VAR)

    allowed_val = tel_val if tel_val else "all"

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

    _write_repository_files(repository_ctx, telemetry)

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
    },
)

def _tel_impl(module_ctx):
    tel_repository(
        name = "aspect_tools_telemetry_report",
        deps = {it.name: it.version for it in module_ctx.modules}
    )

# TODO: Should the extension in the main module be able to set telemetry feature
# flags or do we want to stick with environment variables.
telemetry = module_extension(
    implementation = _tel_impl,
)
