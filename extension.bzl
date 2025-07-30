load("@bazel_skylib//lib:paths.bzl", "paths")
load("//:sha1.bzl", hash="sha1")

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
    """Detect if the build is happening in 'CI'. Pretty much all the vendors set this."""

    return repository_ctx.os.environ.get("CI") != None

TELEMETRY_REGISTRY["ci"] = _is_ci

def _is_bazelisk(repository_ctx):
    """Detect if the build is using bazelisk; this persists into the repo env state."""

    return repository_ctx.os.environ.get("BAZELISK") != None or repository_ctx.os.environ.get("BAZELISK_SKIP_WRAPPER") != None

TELEMETRY_REGISTRY["bazelisk"] = _is_bazelisk

def _shell(repository_ctx):
    """Detect the shell."""

    return repository_ctx.os.environ.get("SHELL")

TELEMETRY_REGISTRY["shell"] = _shell

def _has_tools_bazel(repository_ctx):
    """Detect if the repository has a tools/bazel wrapper script."""

    return repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "tools/bazel")).exists

TELEMETRY_REGISTRY["has_bazel_tool"] = _has_tools_bazel

def _has_bazel_prelude(repository_ctx):
    """Detect if the repository has a //tools/build_rules/prelude_bazel."""

    return repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "tools/build_rules/prelude_bazel")).exists

TELEMETRY_REGISTRY["has_bazel_prelude"] = _has_bazel_prelude

def _has_workspace(repository_ctx):
    """Detect if the repository has a WORKSPACE file."""

    return repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "WORKSPACE")).exists or repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "WORKSPACE.bazel")).exists

TELEMETRY_REGISTRY["has_bazel_workspace"] = _has_workspace

def _has_module(repository_ctx):
    """Detect if the repository has a MODULE.bazel file."""

    return repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "MODULE.bazel")).exists

TELEMETRY_REGISTRY["has_bazel_module"] = _has_module

def _bazel_version(repository_ctx):
    return native.bazel_version

TELEMETRY_REGISTRY["bazel_version"] = _bazel_version

def _os(repository_ctx):
    return repository_ctx.os.name

TELEMETRY_REGISTRY["os"] = _os

def _arch(repository_ctx):
    return repository_ctx.os.arch

TELEMETRY_REGISTRY["arch"] = _arch

def _build_counter(repository_ctx):
    """Try to get a counter for the build.

    This allows estimation of rate of builds.
    """

    # Note that on GHA run numbers may be reused and there's a retry count
    # subcounter. Since that's the only platform to do so, we're going to just
    # pretend it doesn't exist.
    for counter_var in [
        "BUILDKITE_BUILD_NUMBER",  # Buildkite
        "GITHUB_RUN_NUMBER",       # Github/forgejo/gitea
        "CI_PIPELINE_IID",         # Gitlab
        "CIRCLE_BUILD_NUM",        # CircleCI
        "DRONE_BUILD_NUMBER",      # Drone
        "BUILD_NUMBER",            # Jenkins
        "CI_PIPELINE_NUMBER",      # Woodpecker?
        "TRAVIS_BUILD_NUMBER",     # Travis
    ]:
        counter = repository_ctx.os.environ.get(counter_var)
        if counter:
            return counter

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
        val = repository_ctx.os.environ.get(var)
        if val != None:
            return platform

    # Set on Woodpecker and in some other environments
    return repository_ctx.os.environ.get("CI_SYSTEM_NAME")

TELEMETRY_REGISTRY["runner"] = _build_runner


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
        repo = repository_ctx.os.environ.get(var)
        if repo:
            return repo

TELEMETRY_REGISTRY["org"] = _repo_org


def _repo_id(repository_ctx):
    """Try to extract an aggregation ID (hash) from the repo context.

    Ideally we want to use the first few (usually stable!) lines from a highly
    stable file such as the README. This will provide a consistent aggregation
    ID regardless of whether a project is checked out locally or remotely.

    Note that the project ID doesn't depend on the org name, since the org name
    cannot be determined on workstations but we do want to count CI vs
    workstation builds for a single project consistently.

    """

    readme_file = None
    for suffix in [
        "",
        "doc",
        "docs",
        ".github",
        ".gitlab",
        ".gitea",
        ".forgejo",
    ]:
        dir = repository_ctx.workspace_root
        if suffix:
            dir = paths.join(dir, suffix)
        dir = repository_ctx.path(dir)
        if dir.exists() and dir.is_dir():
            for entry in dir.listdir():
                if entry.basename.lower().find("readme") != -1:
                    readme_file = entry
                    break

        if readme_file:
            break

    if readme_file:
        return hash("\n".join(repository_ctx.read(readme_file).split("\n")[:4]))

TELEMETRY_REGISTRY["id"] = _repo_id


def _repo_user(repository_ctx):
    """Try to extract a fingerprint for the user who initiated the build.

    Note that we salt the user IDs with the identified project ID to prevent
    correllation.

    """

    user = None
    for var in [
        "BUILDKITE_BUILD_AUTHOR_EMAIL", # Buildkite
        "GITHUB_ACTOR",                 # GH/Gitea/Forgejo
        "GITLAB_USER_EMAIL",            # GL
        "CIRCLE_USERNAME",              # Circle
        # TODO: Jenkins
        "DRONE_COMMIT_AUTHOR",          # Drone
        "DRONE_COMMIT_AUTHOR_EMAIL",    # Drone
        "CI_COMMIT_AUTHOR",             # Woodpecker
        "CI_COMMIT_AUTHOR_EMAIL",       # Woodpecker
        # TODO: Travis
        "LOGNAME",                      # Generic unix
        "USER",                         # Generic unix
    ]:
        user = repository_ctx.os.environ.get(var)
        if user:
            break

    if user:
        return hash(str(_repo_id(repository_ctx)) + ";" + user)

TELEMETRY_REGISTRY["user"] = _repo_user


def _repo_bzlmod(repository_ctx):
    return repository_ctx.attr.deps

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
    endpoint = repository_ctx.os.environ.get(TELEMETRY_DEST_VAR)
    if endpoint == None:
        endpoint = TELEMETRY_DEST

    ## Parse the feature flagging var
    tel_val = repository_ctx.os.environ.get(TELEMETRY_ENV_VAR)

    allowed_val = None

    if repository_ctx.os.environ.get("DO_NOT_TRACK"):
        allowed_val = "-all"
    elif tel_val:
        allowed_val = tel_val
    else:
        allowed_val = "all"

    allowed_telemetry = parse_opt_out(allowed_val or "all", TELEMETRY_FEATURES)

    ## Collect enabled data
    telemetry = {}
    for feature, handler in TELEMETRY_REGISTRY.items():
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
