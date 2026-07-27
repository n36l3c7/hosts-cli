# shellcheck shell=bash
#
# Shared setup for the test suite. Tests always run against the built script,
# never against the sources, so that what is tested is what is shipped, and
# always against a fixture passed with --file, so that they need no privilege
# and never touch the real /etc/hosts.

# The suite uses "run --separate-stderr" and BATS_TEST_TMPDIR, both of which
# need bats 1.5 or newer.
bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOSTS_BIN="$REPO_ROOT/build/hosts"
  HOSTS_MAN="$REPO_ROOT/build/hosts.1"
  HOSTS_VERSION="$(cat "$REPO_ROOT/VERSION")"
  FIXTURE="$BATS_TEST_TMPDIR/hosts"

  # Every test gets its own stores inside its temporary directory, so that the
  # suite can never write into /var/backups or /var/lib.
  HOSTS_BACKUP_DIR="$BATS_TEST_TMPDIR/backups"
  HOSTS_PROFILE_DIR="$BATS_TEST_TMPDIR/profiles"

  export REPO_ROOT HOSTS_BIN HOSTS_MAN HOSTS_VERSION FIXTURE
  export HOSTS_BACKUP_DIR HOSTS_PROFILE_DIR
}

# The directory the backups of the fixture end up in.
fixture_backup_dir() {
  local -a matches
  shopt -s nullglob
  matches=("$HOSTS_BACKUP_DIR"/*/)
  shopt -u nullglob
  printf '%s' "${matches[0]:-}"
}

# The sidecar of the most recent backup of the fixture.
newest_meta() {
  local -a matches
  shopt -s nullglob
  matches=("$(fixture_backup_dir)"hosts.*.meta)
  shopt -u nullglob
  printf '%s' "${matches[${#matches[@]} - 1]:-}"
}

# The copy of the most recent backup of the fixture.
newest_copy() {
  local meta
  meta=$(newest_meta)
  printf '%s' "${meta%.meta}.bak"
}

# Write the fixture file from standard input.
make_fixture() {
  cat >"$FIXTURE"
}

# Run the program against the fixture.
hosts_run() {
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" "$@"
}

# Source the built script in a subshell and run the given code against its
# internal functions. The main guard keeps sourcing from running main.
in_script() {
  run --separate-stderr bash -c "source '$HOSTS_BIN'
$1"
}
