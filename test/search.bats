#!/usr/bin/env bats
#
# hosts search.

load helper

standard_fixture() {
  make_fixture <<'EOF'
127.0.0.1 localhost
10.0.0.5 staging staging.local # the staging box
10.0.0.9 build
# 192.168.1.40 old-nas # decommissioned
EOF
}

@test "search matches on a name" {
  standard_fixture
  hosts_run search staging
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = $'10.0.0.5\tstaging staging.local\ton\tthe staging box' ]
}

@test "search matches on an address" {
  standard_fixture
  hosts_run search 10.0.0
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "search matches on a comment" {
  standard_fixture
  hosts_run search decommissioned
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = $'192.168.1.40\told-nas\toff\tdecommissioned' ]
}

@test "search includes disabled entries" {
  standard_fixture
  hosts_run search old-nas
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ ${lines[0]} == *$'\toff\t'* ]]
}

@test "matching is on substrings and ignores case" {
  standard_fixture
  hosts_run search STAG
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "a pattern matching nothing produces no output and succeeds" {
  standard_fixture
  hosts_run search nothing-like-this
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "search without an argument is a usage error" {
  standard_fixture
  hosts_run search
  [ "$status" -eq 2 ]
  [[ $stderr == *'exactly one pattern'* ]]
}

@test "search --json reports the pattern" {
  standard_fixture
  hosts_run --json search build
  [ "$status" -eq 0 ]
  [[ $output == *'"pattern": "build",'* ]]
}
