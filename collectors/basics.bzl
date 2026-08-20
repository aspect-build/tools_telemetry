"""
Some basic collectors.
"""


def _os(repository_ctx):
    return repository_ctx.os.name


def _arch(repository_ctx):
    return repository_ctx.os.arch


def register():
    return {
        "os": _os,
        "arch": _arch,
    }
