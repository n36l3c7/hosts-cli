#!/usr/bin/env bats
#
# Command line surface of the scaffolding release.

load helper

@test "--version prints the program name and version on stdout" {
  run --separate-stderr "$HOSTS_BIN" --version
  [ "$status" -eq 0 ]
  [ "$output" = "hosts $HOSTS_VERSION" ]
  [ -z "$stderr" ]
}

@test "-V is an alias of --version" {
  run --separate-stderr "$HOSTS_BIN" -V
  [ "$status" -eq 0 ]
  [ "$output" = "hosts $HOSTS_VERSION" ]
}

@test "--help prints usage on stdout and succeeds" {
  run --separate-stderr "$HOSTS_BIN" --help
  [ "$status" -eq 0 ]
  [[ $output == *"Usage:"* ]]
  [ -z "$stderr" ]
}

@test "-h is an alias of --help" {
  run --separate-stderr "$HOSTS_BIN" -h
  [ "$status" -eq 0 ]
  [[ $output == *"Usage:"* ]]
}

@test "no argument is a usage error and writes usage to stderr" {
  run --separate-stderr "$HOSTS_BIN"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ $stderr == *"Usage:"* ]]
}

@test "an unknown command is a usage error" {
  run --separate-stderr "$HOSTS_BIN" frobnicate
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ $stderr == *"unknown command or option: frobnicate"* ]]
}

@test "an unknown option is a usage error" {
  run --separate-stderr "$HOSTS_BIN" --nope
  [ "$status" -eq 2 ]
  [[ $stderr == *"unknown command or option: --nope"* ]]
}

@test "sourcing the script does not run main" {
  run --separate-stderr bash -c "source '$HOSTS_BIN'; version"
  [ "$status" -eq 0 ]
  [ "$output" = "hosts $HOSTS_VERSION" ]
}
