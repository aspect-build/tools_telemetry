load("@bazel_skylib//lib:unittest.bzl", "unittest", "asserts")
load("//:extension.bzl", "parse_opt_out", "TELEMETRY_FEATURES")

def _parse_opt_out_test(ctx):
  env = unittest.begin(ctx)

  asserts.equals(env, TELEMETRY_FEATURES, parse_opt_out("all", TELEMETRY_FEATURES), "all should mean all")
  asserts.equals(env, TELEMETRY_FEATURES, parse_opt_out("", TELEMETRY_FEATURES), "empty string is also all")
  asserts.equals(env, [], parse_opt_out("-all", TELEMETRY_FEATURES), "-all disables all features")
  asserts.equals(env, ["id"], parse_opt_out("id", TELEMETRY_FEATURES), "An unqualified term masks defaults")
  asserts.equals(env, [], parse_opt_out("all,+all,-all", TELEMETRY_FEATURES), "Removals win")

  return unittest.end(env)

parse_opt_out_test = unittest.make(_parse_opt_out_test)

def test_suite():
  unittest.suite(
      "test_suite",
      parse_opt_out_test,
  )
