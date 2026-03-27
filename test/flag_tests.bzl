load("@bazel_skylib//lib:unittest.bzl", "unittest", "asserts")
load("//:extension.bzl", "parse_consent", "parse_opt_out")

def _parse_opt_out_test(ctx):
  env = unittest.begin(ctx)

  features = ["id", "user", "shell"]
  groups = {"all": features}

  asserts.equals(env, features, parse_opt_out("all", features, groups), "all should mean all")
  asserts.equals(env, features, parse_opt_out("", features, groups), "empty string is also all")
  asserts.equals(env, [], parse_opt_out("-all", features, groups), "-all disables all features")
  asserts.equals(env, ["id"], parse_opt_out("id", features, groups), "An unqualified term masks defaults")
  asserts.equals(env, [], parse_opt_out("all,+all,-all", features, groups), "Removals win")

  return unittest.end(env)

parse_opt_out_test = unittest.make(_parse_opt_out_test)


def _parse_consent_test(ctx):
    env = unittest.begin(ctx)

    result = parse_consent(None)
    asserts.equals(env, None, result.allowed, "unset consent should have allowed=None")
    asserts.true(env, bool(result.error), "unset consent should produce an error message")

    result = parse_consent("allow")
    asserts.true(env, result.allowed, "allow should be permitted")
    asserts.equals(env, None, result.error, "allow should produce no error")

    result = parse_consent("ALLOW")
    asserts.true(env, result.allowed, "allow should be case-insensitive")

    result = parse_consent("disallow")
    asserts.false(env, result.allowed, "disallow should not be permitted")
    asserts.equals(env, None, result.error, "disallow should produce no error")

    result = parse_consent("DISALLOW")
    asserts.false(env, result.allowed, "disallow should be case-insensitive")

    result = parse_consent("invalid")
    asserts.equals(env, None, result.allowed, "invalid value should have allowed=None")
    asserts.true(env, bool(result.error), "invalid value should produce an error message")

    return unittest.end(env)


parse_consent_test = unittest.make(_parse_consent_test)


def test_suite():
    unittest.suite(
        "flag_suite",
        parse_opt_out_test,
        parse_consent_test,
    )
