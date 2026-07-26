#!/usr/bin/env bats
#
# hosts get.

load helper

standard_fixture() {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost ip6-localhost
10.0.0.5 staging staging.local
# 192.168.1.40 old-nas
EOF
}

@test "get prints the address and nothing else" {
  standard_fixture
  hosts_run get staging
  [ "$status" -eq 0 ]
  [ "$output" = '10.0.0.5' ]
  [ -z "$stderr" ]
}

@test "get resolves an alias as well as the canonical name" {
  standard_fixture
  hosts_run get staging.local
  [ "$status" -eq 0 ]
  [ "$output" = '10.0.0.5' ]
}

@test "the match ignores case" {
  standard_fixture
  hosts_run get STAGING
  [ "$status" -eq 0 ]
  [ "$output" = '10.0.0.5' ]
}

@test "a dual stack name prints both addresses, in file order" {
  standard_fixture
  hosts_run get localhost
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = '127.0.0.1' ]
  [ "${lines[1]}" = '::1' ]
}

@test "a name that is not there exits 5 with no output" {
  standard_fixture
  hosts_run get nosuch
  [ "$status" -eq 5 ]
  [ -z "$output" ]
}

@test "a disabled entry does not resolve" {
  # A commented out entry takes no part in name resolution, so reporting its
  # address would be a lie.
  standard_fixture
  hosts_run get old-nas
  [ "$status" -eq 5 ]
  [ -z "$output" ]
}

@test "the match is exact, not a substring or a glob" {
  standard_fixture
  hosts_run get stag
  [ "$status" -eq 5 ]
  hosts_run get 'stag*'
  [ "$status" -eq 5 ]
}

@test "get without an argument is a usage error" {
  standard_fixture
  hosts_run get
  [ "$status" -eq 2 ]
  [[ $stderr == *'exactly one hostname'* ]]
}

@test "get with two arguments is a usage error" {
  standard_fixture
  hosts_run get one two
  [ "$status" -eq 2 ]
}

@test "get --json reports the hostname it was asked about" {
  standard_fixture
  hosts_run --json get staging
  [ "$status" -eq 0 ]
  [[ $output == *'"hostname": "staging",'* ]]
  [[ $output == *'"ip": "10.0.0.5",'* ]]
}

@test "get --json on a missing name emits an empty array and still exits 5" {
  standard_fixture
  hosts_run --json get nosuch
  [ "$status" -eq 5 ]
  [[ $output == *'"entries": []'* ]]
}
