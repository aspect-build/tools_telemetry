"""
Machinery for computing anonymous aggregation IDs.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(":utils.bzl", "hash")


def _repo_id(repository_ctx):
    """Try to extract an aggregation ID from the repo context.

    Ideally we want to use the first few (usually stable!) lines from a highly
    stable file such as the README. This will provide a consistent aggregation
    ID regardless of whether a project is checked out locally or remotely.

    Note that the repo ID doesn't depend on the org name, since the org name
    cannot be determined on workstations but we do want to count CI vs
    workstation builds for a single repo consistently.

    """

    readme_file = None
    for suffix in [
        "",
        # Github allows the README to be squirreled away, so we may need to
        # check subdirs. Assume that gitlab et all allow the same.
        "doc",
        "docs",
        ".github",
        ".gitlab",
        ".gitea",
        ".forgejo",
    ]:
        dir = repository_ctx.workspace_root
        if suffix:
            dir = paths.join(str(dir), suffix)
        dir = repository_ctx.path(dir)
        if dir.exists and dir.is_dir:
            for entry in dir.readdir():
                if entry.basename.lower().find("readme") != -1:
                    readme_file = entry
                    break

        if readme_file:
            break

    # As a fallback use the top of the MODULE.bazel file
    if not readme_file:
        readme_file = repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "MODULE.bazel"))

    return hash(repository_ctx, "\n".join(repository_ctx.read(readme_file).split("\n")[:4]))


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
        return hash(repository_ctx, str(_repo_id(repository_ctx)) + ";" + user)


def register():
    return {
        "id": _repo_id,
        "user": _repo_user,
    }
