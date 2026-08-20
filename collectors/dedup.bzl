"""
Machinery for computing anonymous, day-scoped deduplication IDs.

The stable on-device repository ID computed here never leaves the machine.
The only ID that is reported is `id_day`, a hash of the on-device
repository ID together with the current UTC date: reports from the same
repository can be deduplicated and counted uniquely within a single day,
and cannot be linked across days from the reported data.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(":utils.bzl", "hash")


def _repo_id(repository_ctx):
    """Try to extract a stable on-device repository ID from the repo context.

    Only used on-device as an input to the day-scoped ID below; never
    reported directly.

    This strategy scans for a README-like file in some known locations and known
    formats and hashes the first few lines if we can find one. The intuition
    here is that README files in general are highly stable and in common README
    structures the first few lines especially contain an extremely stable title
    and summary only.

    As a fallback we go to the first few lines of the MODULE.bazel file. This is
    expected to be less stable than a README file generally because a
    MODULE.bazel could be a simple listing of dependencies with nothing else. In
    practice the first several lines are likely a comment or a `module()`
    invocation which will be highly stable.

    We consider other possible sources of stable identifiers such as a version
    control remote URL out of bounds because they may contain secrets and
    because accessing them without invoking commands is challenging.

    """

    readme_file = None

    for prefix in [
        "",
        "doc",
        "docs",
        "Doc",
        "Docs",
    ]:
        for base in [
            "README",
            "readme",
            "Readme",
            "index",
        ]:
            # Alphabetically
            for ext in [
                "",
                ".adoc",
                ".asc",
                ".asciidoc",
                ".markdown",
                ".md",
                ".mdown",
                ".mkdk",
                ".org",
                ".rdoc",
                ".rst",
                ".textile",
                ".txt",
                ".wiki",
            ]:
                dir = repository_ctx.workspace_root
                if prefix:
                    dir = paths.join(str(dir), prefix)
                file = repository_ctx.path(paths.join(str(dir), base + ext))
                if file.exists:
                    readme_file = file
                    break

            if readme_file:
                break

        if readme_file:
            break

    if not readme_file:
        readme_file = repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "MODULE.bazel"))

    content = "\n".join(repository_ctx.read(readme_file).split("\n")[:4])
    return hash(repository_ctx, content)


def _utc_date(repository_ctx):
    """Get the current UTC date (YYYY-MM-DD) via the system date binary.

    Returns None when unavailable so that the id_day field is simply omitted
    rather than computed against a bogus date.
    """

    result = repository_ctx.execute(["date", "-u", "+%Y-%m-%d"])
    if result.return_code != 0:
        return None
    date = result.stdout.strip()
    if len(date) != 10:
        return None
    return date


def _repo_id_day(repository_ctx):
    """Compute the day-scoped repo deduplication ID; see the module docstring."""

    date = _utc_date(repository_ctx)
    if not date:
        return None
    return hash(repository_ctx, str(_repo_id(repository_ctx)) + ";" + date)


def register():
    return {
        "id_day": _repo_id_day,
    }
