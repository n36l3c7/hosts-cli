#!/usr/bin/env bats
#
# hosts check.

load helper

# A file that must produce no finding at all.
clean_fixture() {
  make_fixture <<'EOF'
# Static table lookup for hostnames.
127.0.0.1 localhost
::1 localhost ip6-localhost

10.0.0.5 staging staging.local # staging box
EOF
}

# Assert that a rule fired on a given line.
assert_finding() {
  local severity=$1 rule=$2 line=$3
  [[ $output == *"$FIXTURE:$line: $severity: $rule: "* ]]
}

# Assert that a rule fired about the file as a whole.
assert_file_finding() {
  local severity=$1 rule=$2
  [[ $output == *"$FIXTURE: $severity: $rule: "* ]]
}

@test "a clean file produces no output and succeeds" {
  clean_fixture
  hosts_run check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the same name on IPv4 and on IPv6 is normal dual stack" {
  # The correct hosts file of every Linux machine maps localhost to both
  # 127.0.0.1 and ::1: a rule that ignored the address family would report an
  # error on every healthy system.
  clean_fixture
  hosts_run check
  [ "$status" -eq 0 ]
  [[ $output != *conflicting-ip* ]]
}

@test "findings go to stdout, because they are the data of this command" {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
999.1.1.1 bogus
EOF
  hosts_run check
  [ "$status" -eq 4 ]
  [[ $output == *invalid-ip* ]]
  [ -z "$stderr" ]
}

@test "a line that is not an address followed by a name is an error" {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
203.0.113.7
EOF
  hosts_run check
  [ "$status" -eq 4 ]
  assert_finding error invalid-line 3
}

@test "an address that does not parse is an error naming it" {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
999.1.1.1 bogus
EOF
  hosts_run check
  [ "$status" -eq 4 ]
  assert_finding error invalid-ip 3
  [[ $output == *'999.1.1.1'* ]]
}

@test "a name breaking RFC 1123 is an error" {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
10.0.0.11 -badname
EOF
  hosts_run check
  [ "$status" -eq 4 ]
  assert_finding error invalid-hostname 3
}

@test "an underscore in a name is only a warning" {
  # Container and orchestration tooling generates these by the thousand;
  # treating them as errors would make check useless on real files.
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
192.168.1.9 printer_two
EOF
  hosts_run check
  [ "$status" -eq 0 ]
  assert_finding warning nonstandard-hostname 3
}

@test "a control character in a line is an error" {
  printf '127.0.0.1 localhost\n::1 localhost\n10.0.0.5 stag\ring\n' >"$FIXTURE"
  hosts_run check
  [ "$status" -eq 4 ]
  assert_finding error control-character 3
}

@test "a tab is not a control character, it is the usual separator" {
  printf '127.0.0.1\tlocalhost\n::1\tlocalhost\n' >"$FIXTURE"
  hosts_run check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an identical entry on a later line is an error" {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
10.0.0.5 staging staging.local
10.0.0.5 staging staging.local
EOF
  hosts_run check
  [ "$status" -eq 4 ]
  assert_finding error duplicate-entry 4
  [[ $output == *'line 3'* ]]
}

@test "a repeated entry is reported once, not once per name" {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
10.0.0.5 a b c
10.0.0.5 a b c
EOF
  hosts_run check
  [ "$status" -eq 4 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "a name repeated on the same address with a different line is a warning" {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
10.0.0.5 staging staging.local
10.0.0.5 staging other
EOF
  hosts_run check
  [ "$status" -eq 0 ]
  assert_finding warning duplicate-name 4
}

@test "a name pointing elsewhere in the same family is a warning" {
  # Some resolver configurations aggregate every matching address, so this can
  # be a deliberate round robin rather than a mistake.
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
10.0.0.5 staging
10.0.0.9 staging
EOF
  hosts_run check
  [ "$status" -eq 0 ]
  assert_finding warning conflicting-ip 4
}

@test "--strict turns warnings into a failure" {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
10.0.0.5 staging
10.0.0.9 staging
EOF
  hosts_run check
  [ "$status" -eq 0 ]
  hosts_run check --strict
  [ "$status" -eq 4 ]
}

@test "a disabled entry neither duplicates nor conflicts" {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
10.0.0.5 staging
# 10.0.0.9 staging
EOF
  hosts_run check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a disabled entry is still checked for name validity" {
  # The defect is still there the day the entry is switched back on.
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
# 192.168.1.9 printer_two
EOF
  hosts_run check
  [ "$status" -eq 0 ]
  assert_finding warning nonstandard-hostname 3
}

@test "a commented line whose names are not hostnames stays a comment" {
  # Recognising a disabled entry means recognising its names; when they are
  # not even plausible hostnames the line is prose, and prose is not linted.
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
# 10.0.0.11 -badname
EOF
  hosts_run check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a missing IPv4 loopback entry is a warning about the file" {
  make_fixture <<'EOF'
::1 localhost
10.0.0.5 staging
EOF
  hosts_run check
  [ "$status" -eq 0 ]
  assert_file_finding warning missing-loopback
}

@test "a missing IPv6 loopback entry is a warning about the file" {
  make_fixture <<'EOF'
127.0.0.1 localhost
EOF
  hosts_run check
  [ "$status" -eq 0 ]
  assert_file_finding warning missing-loopback6
}

@test "a commented out loopback entry does not count as present" {
  make_fixture <<'EOF'
# 127.0.0.1 localhost
::1 localhost
EOF
  hosts_run check
  [ "$status" -eq 0 ]
  assert_file_finding warning missing-loopback
}

@test "a file not ending with a newline is a warning" {
  printf '127.0.0.1 localhost\n::1 localhost' >"$FIXTURE"
  hosts_run check
  [ "$status" -eq 0 ]
  assert_file_finding warning missing-trailing-newline
}

@test "an empty file reports the two missing loopback entries and nothing else" {
  : >"$FIXTURE"
  hosts_run check
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  assert_file_finding warning missing-loopback
  assert_file_finding warning missing-loopback6
}

@test "findings come out ordered by line, with file level ones last" {
  make_fixture <<'EOF'
999.1.1.1 bogus
203.0.113.7
10.0.0.11 -badname
EOF
  hosts_run check
  [ "$status" -eq 4 ]
  [[ ${lines[0]} == "$FIXTURE:1: "* ]]
  [[ ${lines[1]} == "$FIXTURE:2: "* ]]
  [[ ${lines[2]} == "$FIXTURE:3: "* ]]
  [[ ${lines[3]} == "$FIXTURE: "* ]]
  [[ ${lines[4]} == "$FIXTURE: "* ]]
}

@test "check --json emits the agreed document" {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
10.0.0.5 staging
10.0.0.5 staging
EOF
  hosts_run --json check
  [ "$status" -eq 4 ]
  [ "${lines[0]}" = '{' ]
  [ "${lines[1]}" = '  "version": 1,' ]
  [ "${lines[2]}" = "  \"file\": \"$FIXTURE\"," ]
  [ "${lines[3]}" = '  "summary": { "errors": 1, "warnings": 0 },' ]
  [ "${lines[4]}" = '  "findings": [' ]
  [ "${lines[5]}" = '    {' ]
  [ "${lines[6]}" = '      "rule": "duplicate-entry",' ]
  [ "${lines[7]}" = '      "severity": "error",' ]
  [ "${lines[8]}" = '      "line": 4,' ]
  [ "${lines[9]}" = '      "related": [3],' ]
  [ "${lines[10]}" = '      "subject": "staging",' ]
  [ "${lines[11]}" = '      "message": "identical to the entry on line 3"' ]
  [ "${lines[12]}" = '    }' ]
  [ "${lines[13]}" = '  ]' ]
  [ "${lines[14]}" = '}' ]
}

@test "a file level finding has a null line and no related lines" {
  make_fixture <<'EOF'
127.0.0.1 localhost
EOF
  hosts_run --json check
  [ "$status" -eq 0 ]
  [[ $output == *'"line": null,'* ]]
  [[ $output == *'"related": [],'* ]]
}

@test "check --json on a clean file emits an empty findings array" {
  clean_fixture
  hosts_run --json check
  [ "$status" -eq 0 ]
  [[ $output == *'"summary": { "errors": 0, "warnings": 0 },'* ]]
  [[ $output == *'"findings": []'* ]]
}

@test "check takes no argument" {
  clean_fixture
  hosts_run check something
  [ "$status" -eq 2 ]
  [[ $stderr == *'takes no argument'* ]]
}
