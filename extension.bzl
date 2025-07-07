load("@bazel_skylib//lib:paths.bzl", "paths")
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

TELEMETRY_REGISTRY = {}

def _is_ci(repository_ctx):
    """Detect if the build is hppening in 'CI'. Pretty much all the vendors set this."""

    return repository_ctx.getenv("CI") != None

TELEMETRY_REGISTRY["ci"] = _is_ci

def _build_counter(repository_ctx):
    """Try to get a counter for the build.

    This allows estimation of rate of builds.
    """

    for big_var, small_var in [
        ("BUILDKITE_BUILD_NUMBER", None),               # Buildkite
        ("GITHUB_RUN_NUMBER", "GITHUB_ATTEMPT_NUMBER"), # Github/forgejo/gitea
        ("CI_PIPELINE_IID", None),                      # Gitlab
        ("CIRCLE_BUILD_NUM", None),                     # CircleCI
        ("DRONE_BUILD_NUMBER", None),                   # Drone
        ("BUILD_NUMBER", None),                         # Jenkins
        ("CI_PIPELINE_NUMBER", None),                   # Woodpecker?
        ("TRAVIS_BUILD_NUMBER", None),                  # Travis
    ]:
        big = repository_ctx.getenv(big_var)
        small = "0"
        if small_var:
            small = repository_ctx.getenv(small_var)
        if big != None:
            return [big, small]

TELEMETRY_REGISTRY["counter"] = _build_counter

def _build_runner(repository_ctx):
    """Try to identify the runner environment.

    """
    for var, platform in [
        ("BUILDKITE_BUILD_NUMBER", "buildkite"),
        ("FORGEJO_TOKEN", "forgejo"),  # FIXME: This value is a secret, avoid
        ("GITEA_ACTIONS", "gitea"),
        ("GITHUB_RUN_NUMBER", "github-actions"),
        ("GITLAB_CI", "gitlab"),
        ("CIRCLE_BUILD_NUM", "circleci"),
        ("DRONE_BUILD_NUMBER", "drone"),
        ("BUILD_NUMBER", "jenkins"),
        ("TRAVIS", "travis")
    ]:
        val = repository_ctx.getenv(var)
        if val != None:
            return platform

    # Set on Woodpecker and in some other environments
    return repository_ctx.getenv("CI_SYSTEM_NAME")

TELEMETRY_REGISTRY["runner"] = _build_runner


def _repo_id(repository_ctx):
    """Try to extract an aggregation ID (hash) from the repo context.

    If there's a well known repo URL, strip user details from that and use it.
    Otherwise use the name of the repo directory.
    """

    repo = None
    for var in [
        "BUILDKITE_REPO",        # Buildkite
        "GITHUB_REPOSITORY",     # GH/Gitea/Forgejo
        "CI_REPOSITORY_URL",     # GL
        "CIRCLE_REPOSITORY_URL", # CircleCI
        "GIT_URL",               # Jenkins
        "GIT_URL_1",             # Jenkins
        "DRONE_REPO_LINK",       # Drone
        "CI_REPO",               # Woodpecker
        "TRAVIS_REPO_SLUG",      # Travis
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
    return hex(hash(repo))[3:]

TELEMETRY_REGISTRY["id"] = _repo_id

def _repo_org(repository_ctx):
    """Try to extract the organization name.

    """

    repo = None
    for var in [
        "BUILDKITE_ORGANIZATION_SLUG", # Buildkite
        "GITHUB_REPOSITORY_OWNER",     # GH/Gitea/Forgejo
        "CI_PROJECT_NAMESPACE",        # GL
        "CIRCLE_PROJECT_USERNAME",     # Circle
        # TODO: Jenkins only has the fetch URL which seems excessively sensitive
        "DRONE_REPO_NAMESPACE",        # Drone
        "CI_REPO_OWNER",               # Woodpecker
        "TRAVIS_REPO_SLUG",            # Travis
    ]:
        repo = repository_ctx.getenv(var)
        if repo:
            return repo

TELEMETRY_REGISTRY["org"] = _repo_org

def _repo_bzlmod(repository_ctx):
    """Extract the installed Aspect libraries and versions.

    Note that in order to protect the privacy of internal modules and internal
    registries we only look at BCR sourced stuff.
    """

    lockfile_path = repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "MODULE.bazel.lock"))
    # Since this is a bzlmod-only telemetry package this should always hold but to be safe
    if lockfile_path.exists:
        # The lockfile's registry file hashes contain a few things:
        # - The `bazel_registry.json` (if any) from the registry
        # - A `MODULE.bazel` for every module version considered during resolution
        # - A `source.json` for the _selected_ version
        #
        # Since we're trying to collect the selected dep versions, we can just
        # look for the source lists.
        source_json = "/source.json"
        bcr = "https://bcr.bazel.build/modules/"
        lockfile_content = json.decode(repository_ctx.read(lockfile_path))
        selected_module_source_urls = [it for it in lockfile_content["registryFileHashes"].keys() if it.endswith(source_json) and it.startswith(bcr)]
        return dict([it[len(bcr):][:0-len(source_json)].split("/") for it in selected_module_source_urls])

TELEMETRY_REGISTRY["deps"] = _repo_bzlmod


TELEMETRY_ENV_VAR = "ASPECT_TOOLS_TELEMETRY"
TELEMETRY_DEST_VAR = "ASPECT_TOOLS_TELEMETRY_ENDPOINT"
TELEMETRY_DEST = "https://telemetry.aspect.build/ingest"
TELEMETRY_FEATURES = list(TELEMETRY_REGISTRY.keys())


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
    ## Try to find a curl
    curl = repository_ctx.which("curl") or repository_ctx.which("curl.exe")

    ## Figure out where we scribe to
    # Note that this allows the endpoint to be overriden
    endpoint = repository_ctx.getenv(TELEMETRY_DEST_VAR)
    if endpoint == None:
        endpoint = TELEMETRY_DEST

    ## Parse the feature flagging var
    tel_val = repository_ctx.getenv(TELEMETRY_ENV_VAR)

    allowed_val = None

    if repository_ctx.getenv("DO_NOT_TRACK"):
        allowed_val = "-all"
    elif tel_val:
        allowed_val = tel_val
    else:
        print("""
\033[36maspect_tools_telemetry\033[0m is loaded but not configured.

Telemetry reporting is enabled by default.

To accept telemetry and silence this warning, add this entry to your .bazelrc
    common --repo_env=ASPECT_TOOLS_TELEMETRY=all

For more details and configuration options please see
    \033[36m\033[4mhttps://github.com/aspect-build/tools_telemetry\033[0m

""")
        allowed_val = "all"

    allowed_telemetry = parse_opt_out(allowed_val or "all", TELEMETRY_FEATURES)

    ## Collect enabled data
    telemetry = {}
    for feature, handler in TELEMETRY_REGISTRY.items():
        if feature in allowed_telemetry:
            telemetry[feature] = handler(repository_ctx)

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
        """
exports_files(["report.json", "defs.bzl"], visibility = ["//visibility:public"])
"""
    )

    ## Send the report if enabled
    # Note that ANY of these things will disable telemetry
    if curl and endpoint and allowed_telemetry:
        # Note that errors are silent, no attempt is made at caching/slabbing
        repository_ctx.execute([
          curl, "--max-time", "1",
                "--connect-timeout", "0.5",
                "--request", "POST",
                "--header", "Content-Type:application/json",
                "--data", "@report.json",
                endpoint],
          timeout=2
        )


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

# TODO: Should the extension in the main module be able to set telemetry feature
# flags or do we want to stick with environment variables.
telemetry = module_extension(
    implementation = _tel_impl,
)
