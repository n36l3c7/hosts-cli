# shellcheck shell=bash
#
# Shared setup for the test suite. Tests always run against the built script,
# never against the sources, so that what is tested is what is shipped.

# The suite uses "run --separate-stderr" and BATS_TEST_TMPDIR, both of which
# need bats 1.5 or newer.
bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOSTS_BIN="$REPO_ROOT/build/hosts"
  HOSTS_MAN="$REPO_ROOT/build/hosts.1"
  HOSTS_VERSION="$(cat "$REPO_ROOT/VERSION")"
  export REPO_ROOT HOSTS_BIN HOSTS_MAN HOSTS_VERSION
}
