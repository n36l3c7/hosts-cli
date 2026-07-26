#!/usr/bin/env bats
#
# hosts ls.

load helper

standard_fixture() {
  make_fixture <<'EOF'
# Static table lookup for hostnames.
127.0.0.1 localhost
::1 localhost ip6-localhost

10.0.0.5 staging staging.local # staging box
192.168.1.9 printer
# 192.168.1.40 old-nas
EOF
}

@test "ls lists the active entries in file order" {
  standard_fixture
  hosts_run ls
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "${lines[0]}" = $'127.0.0.1\tlocalhost\ton\t' ]
  [ "${lines[1]}" = $'::1\tlocalhost ip6-localhost\ton\t' ]
  [ "${lines[2]}" = $'10.0.0.5\tstaging staging.local\ton\tstaging box' ]
  [ "${lines[3]}" = $'192.168.1.9\tprinter\ton\t' ]
}

@test "ls writes nothing to stderr" {
  standard_fixture
  hosts_run ls
  [ -z "$stderr" ]
}

assert_four_fields() {
  local line
  for line in "${lines[@]}"; do
    # Stripping everything that is not a tab must leave exactly three of them,
    # which is what a fixed count of four fields means.
    [ "${line//[^$'\t']/}" = $'\t\t\t' ]
  done
}

@test "the field count is the same whatever the options" {
  standard_fixture

  hosts_run ls
  assert_four_fields

  hosts_run ls --all
  assert_four_fields

  hosts_run ls --disabled
  assert_four_fields

  hosts_run ls 'local*'
  assert_four_fields
}

@test "ls filters on a glob over the names" {
  standard_fixture
  hosts_run ls '*.local'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = $'10.0.0.5\tstaging staging.local\ton\tstaging box' ]
}

@test "the glob ignores case" {
  standard_fixture
  hosts_run ls 'LOCALHOST'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "a glob matching nothing produces no output and succeeds" {
  standard_fixture
  hosts_run ls 'nothing-like-this'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ls --disabled lists only the commented out entries" {
  standard_fixture
  hosts_run ls --disabled
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = $'192.168.1.40\told-nas\toff\t' ]
}

@test "ls --all lists both states" {
  standard_fixture
  hosts_run ls --all
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
  [ "${lines[4]}" = $'192.168.1.40\told-nas\toff\t' ]
}

@test "-a is an alias of --all" {
  standard_fixture
  hosts_run ls -a
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
}

@test "an empty file produces no output and succeeds" {
  : >"$FIXTURE"
  hosts_run ls
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a file of only comments produces no output" {
  make_fixture <<'EOF'
# nothing to see
# here either
EOF
  hosts_run ls
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "more than one pattern is a usage error" {
  standard_fixture
  hosts_run ls one two
  [ "$status" -eq 2 ]
  [[ $stderr == *'at most one pattern'* ]]
}

@test "an unknown option is a usage error naming the command" {
  standard_fixture
  hosts_run ls --nope
  [ "$status" -eq 2 ]
  [[ $stderr == *"unknown option for 'ls': --nope"* ]]
  [[ $stderr == *"hosts ls --help"* ]]
}

@test "-- ends option parsing so a pattern may start with a hyphen" {
  make_fixture <<'EOF'
10.0.0.1 -weird
EOF
  hosts_run ls -- '-weird'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'10.0.0.1\t-weird\ton\t' ]
}

@test "ls --json emits the agreed document" {
  make_fixture <<'EOF'
10.0.0.5 staging staging.local # staging box
EOF
  hosts_run --json ls
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = '{' ]
  [ "${lines[1]}" = '  "version": 1,' ]
  [ "${lines[2]}" = "  \"file\": \"$FIXTURE\"," ]
  [ "${lines[3]}" = '  "entries": [' ]
  [ "${lines[4]}" = '    {' ]
  [ "${lines[5]}" = '      "line": 1,' ]
  [ "${lines[6]}" = '      "kind": "entry",' ]
  [ "${lines[7]}" = '      "enabled": true,' ]
  [ "${lines[8]}" = '      "ip": "10.0.0.5",' ]
  [ "${lines[9]}" = '      "family": "inet",' ]
  [ "${lines[10]}" = '      "canonical": "staging",' ]
  [ "${lines[11]}" = '      "aliases": ["staging.local"],' ]
  [ "${lines[12]}" = '      "comment": "staging box",' ]
  [ "${lines[13]}" = '      "raw": "10.0.0.5 staging staging.local # staging box"' ]
  [ "${lines[14]}" = '    }' ]
  [ "${lines[15]}" = '  ]' ]
  [ "${lines[16]}" = '}' ]
}

@test "a missing comment is null and an empty one is a string" {
  make_fixture <<'EOF'
10.0.0.1 one
10.0.0.2 two #
EOF
  hosts_run --json ls
  [ "$status" -eq 0 ]
  [[ $output == *'"comment": null,'* ]]
  [[ $output == *'"comment": "",'* ]]
}

@test "ls --json on no match emits an empty array" {
  standard_fixture
  hosts_run --json ls 'nothing-like-this'
  [ "$status" -eq 0 ]
  [[ $output == *'"entries": []'* ]]
}
