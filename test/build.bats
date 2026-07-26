#!/usr/bin/env bats
#
# The build assembles the sources into a single shipped script and injects the
# version from the VERSION file. Both must hold for every release artifact.

load helper

@test "the built script is executable" {
  [ -x "$HOSTS_BIN" ]
}

@test "the built script carries no unsubstituted placeholder" {
  run grep -q '@VERSION@' "$HOSTS_BIN"
  [ "$status" -eq 1 ]
}

@test "the built man page carries no unsubstituted placeholder" {
  run grep -q '@VERSION@' "$HOSTS_MAN"
  [ "$status" -eq 1 ]
}

@test "the built man page declares the current version" {
  run grep -q "hosts $HOSTS_VERSION" "$HOSTS_MAN"
  [ "$status" -eq 0 ]
}

@test "install and uninstall place and remove both artifacts" {
  local prefix="$BATS_TEST_TMPDIR/prefix"

  run env -u MAKEFLAGS make -C "$REPO_ROOT" install PREFIX="$prefix"
  [ "$status" -eq 0 ]
  [ -x "$prefix/bin/hosts" ]
  [ -f "$prefix/share/man/man1/hosts.1" ]

  run env -u MAKEFLAGS make -C "$REPO_ROOT" uninstall PREFIX="$prefix"
  [ "$status" -eq 0 ]
  [ ! -e "$prefix/bin/hosts" ]
  [ ! -e "$prefix/share/man/man1/hosts.1" ]
}
