load("@aspect_bazel_lib//lib:strings.bzl", "hex")

"""
Telemtry bound for Aspect.

These metrics are designed to tell us at a coarse grain:
- Who (organizations) is using Bazel and our rulesets
- How heavily (number of builds cf. German tank problem)
- What rules are in use
- What CI platform(s) are in use

For transparency the report data we submit is persisted
as @aspect_telemetry_report//:report.json
"""

TELEMETRY_ENV_VAR = "ASPECT_TOOLS_TELEMETRY"
TELEMETRY_DEST = "https://telemetry.aspect.build/api/v0/ingest"
TELEMETRY_FEATURES = ["id", "org", "buildnum", "buildci", "deps"]

def _is_ci(repository_ctx):
    """Detect if the build is hppening in 'CI'. Pretty much all the vendors set this."""

    return repository_ctx.getenv("CI") != None


def _build_stamp(repository_ctx):
    """Try to get a counter for the build.

    This allows estimation of rate of builds.
    """

    for big_var, small_var in [
        ("BUILDKITE_BUILD_NUMBER", None),               # Buildkite
        ("GITHUB_RUN_NUMBER", "GITHUB_ATTEMPT_NUMBER"), # Github
        ("CIRCLE_BUILD_NUM", None),                     # CircleCI
        ("BUILD_NUMBER", None),                         # Jenkins
        ("DRONE_BUILD_NUMBER", None),                   # Drone
    ]:
        big = repository_ctx.getenv(big_var)
        small = "0"
        if small_var:
            small = repository_ctx.getenv(small_var)
        if small:
            small = "+" + small
        if big != None:
            return big + small


def _repo_id(repository_ctx):
    """Try to extract an aggregation ID (hash) from the repo context.

    If there's a well known repo URL, strip user details from that and use it.
    Otherwise use the name of the repo directory.
    """

    repo = None
    for var in [
        "BUILDKITE_REPO",        # Buildkite
        "GITHUB_REPOSITORY",     # GH
        "CI_REPOSITORY_URL",     # GL
        "CIRCLE_REPOSITORY_URL", # CircleCI
        "GIT_URL",               # Jenkins
        "GIT_URL_1",             # Jenkins
        "DRONE_REPO_LINK"        # Drone
    ]:
        repo = repository_ctx.getenv(var)
        if repo:
            break

    if not repo:
        repo = repository_ctx.workspace_root.basename

    # Could have a user:secret@ prefix; strip that
    at = repo.find("@")
    if at != -1:
        repo = repo[at+1:]

    # Could have a ?secret= suffix; strip that
    qmark = repo.find("?")
    if qmark != -1:
        repo = repo[:qmark]

    # FIXME: Use a better hashcode?
    return hex(hash(repo))[2:]


def _repo_org(repository_ctx):
    """Try to extract the organization name.

    """

    repo = None
    for var in [
        "BUILDKITE_ORGANIZATION_SLUG", # Buildkite
        "GITHUB_REPOSITORY_OWNER",     # GH
        "CI_PROJECT_NAMESPACE",        # GL
        "CIRCLE_PROJECT_USERNAME",     # Circle
        "DRONE_REPO_NAMESPACE",        # Drone
        # TODO: Jenkins only has the fetch URL which seems excessively sensitive
    ]:
        repo = repository_ctx.getenv(var)
        if repo:
            return repo


def parse_opt_out(flag, default=[]):
    """
    Parse Bazel-style set semantics flags.

    - If the user specifies unqualified value(s) the default is ignored
    - If the user specifies + qualfied value(s) those should be added
    - If the user specifies - qualified value(s) those cannot occur in the output
    """

    terms = flag.split(",")
    groups = {
        "all": TELEMETRY_FEATURES,
    }
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
    curl = repository_ctx.which("curl") or repository_ctx.which("curl.exe")

    allowed_val = repository_ctx.getenv(TELEMETRY_ENV_VAR)
    allowed_telemetry = parse_opt_out(allowed_val or "all", TELEMETRY_FEATURES)

    id = repository_ctx.getenv(TELEMETRY_ENV_VAR)

    telemetry = {}
    if "id" in allowed_telemetry:
        telemetry["id"] = _repo_id(repository_ctx)

    if "org" in allowed_telemetry:
        telemetry["org"] = _repo_org(repository_ctx)

    if "buildnum" in allowed_telemetry:
        telemetry["build"] = _build_stamp(repository_ctx)

    if "buildci" in allowed_telemetry:
        telemetry["ci"] = _is_ci(repository_ctx)

    if "deps" in allowed_telemetry:
        telemetry["deps"] = repository_ctx.attr.install_reports

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
        """
exports_files(["report.json", "defs.bzl"], visibility = ["//visibility:public"])
"""
    )

    report_content = "\nreport_id = None\n"
    if not allowed_telemetry:
        # User has opted out, no telemetry is allowed
        pass

    elif curl:
        # Happy path. Curl is pretty universal.
        # Note that we're setting pretty aggressive timeouts here.
        res = repository_ctx.execute([
          curl, "--quiet",
                "--max-time=1",
                "--connect-timeout=0.5",
                "--request", "POST",
                "--header", "Content-Type:application/json",
                "--data", "@report.json",
                TELEMETRY_DEST],
          timeout=1
        )
        if res.return_code == 0:
            resp = json.decode(res.stdout)
            report_content = """\
report_id = {}
""".format(repr(resp["id"]))


tel_repository = repository_rule(
  implementation = _tel_repository_impl,
  attrs = {
     "install_reports": attr.string_dict(
       doc = "Mapping of ruleset to version",
     ),
  },
)


def _tel_impl(module_ctx):
    tel_repository(
        name = "aspect_tools_telemetry_report",
        install_reports = {
            report.name: report.version
            for report in module_ctx.modules
        },
    )


telemetry = module_extension(
    implementation = _tel_impl,
)
