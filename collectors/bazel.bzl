"""
Some Bazel and repository oriented collectors.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")


def _is_bazelisk(repository_ctx):
    """Detect if the build is using bazelisk; this persists into the repo env state."""

    return repository_ctx.os.environ.get("BAZELISK") != None or repository_ctx.os.environ.get("BAZELISK_SKIP_WRAPPER") != None

def _has_tools_bazel(repository_ctx):
    """Detect if the repository has a tools/bazel wrapper script."""

    return repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "tools/bazel")).exists


def _has_bazel_prelude(repository_ctx):
    """Detect if the repository has a //tools/build_rules/prelude_bazel."""

    return repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "tools/build_rules/prelude_bazel")).exists


def _has_workspace(repository_ctx):
    """Detect if the repository has a WORKSPACE file."""

    return repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "WORKSPACE")).exists or repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "WORKSPACE.bazel")).exists


def _has_module(repository_ctx):
    """Detect if the repository has a MODULE.bazel file."""

    return repository_ctx.path(paths.join(str(repository_ctx.workspace_root), "MODULE.bazel")).exists


def _bazel_version(repository_ctx):
    return native.bazel_version

def _parse_lockfile(repository_ctx, module_lock):
    lock_content = json.decode(repository_ctx.read(
        module_lock,
    ))

    raw_deps = lock_content.get("registryFileHashes", {})
    registries = [
        it.replace("/bazel_registry.json", "/modules/") for it in raw_deps.keys()
        if it.endswith("/bazel_registry.json")
    ]
    deps = {}
    for url, _sha in raw_deps.items():
        if not url.endswith("/source.json"):
            continue

        # https://bcr.bazel.build/modules/jsoncpp/1.9.5/source.json

        url = url.replace("/source.json", "")

        # https://bcr.bazel.build/modules/jsoncpp/1.9.5

        for registry in registries:
            url = url.replace(registry, "")

        # jsoncpp/1.9.5

        if "/" in url:
            pkg, rev = url.split("/", 1)
            deps[pkg] = rev

    return deps

def _repo_deps(repository_ctx):
    module_lock = repository_ctx.path(str(repository_ctx.workspace_root) + "/MODULE.bazel.lock")
    if module_lock.exists:
        return _parse_lockfile(repository_ctx, module_lock)
    else:
        return repository_ctx.attr.deps


def register():
    return {
        "bazelisk": _is_bazelisk,
        "has_bazel_tool": _has_tools_bazel,
        "has_bazel_prelude": _has_bazel_prelude,
        "has_bazel_workspace": _has_workspace,
        "has_bazel_module": _has_module,
        "bazel_version": _bazel_version,
        "deps": _repo_deps,
    }
