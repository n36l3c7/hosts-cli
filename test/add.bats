#!/usr/bin/env bats
#
# hosts add.

load helper

standard_fixture() {
  {
    printf '# Static table lookup for hostnames.\n'
    printf '127.0.0.1\tlocalhost\n'
    printf '::1\t\tlocalhost ip6-localhost\n'
    printf '\n'
    printf '10.0.0.5    staging   staging.local\t# staging box\n'
    printf '# 192.168.1.40 old-nas\n'
  } >"$FIXTURE"
}

@test "an address that is nowhere yet goes on a new line at the end" {
  standard_fixture
  hosts_run --yes add 10.0.0.9 build
  [ "$status" -eq 0 ]

  run tail -1 "$FIXTURE"
  [ "$output" = "$(printf '10.0.0.9\tbuild')" ]
}

@test "the lines it did not touch stay byte for byte the same" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  hosts_run --yes add 10.0.0.9 build
  [ "$status" -eq 0 ]

  run bash -c "head -6 '$FIXTURE' | cmp - '$BATS_TEST_TMPDIR/before'"
  [ "$status" -eq 0 ]
}

@test "adding what is already there changes nothing and succeeds" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  hosts_run --yes add 10.0.0.5 staging
  [ "$status" -eq 0 ]

  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "a missing name joins the line that already has the others" {
  standard_fixture
  hosts_run --yes add 10.0.0.5 staging api
  [ "$status" -eq 0 ]

  run sed -n 5p "$FIXTURE"
  [ "$output" = "$(printf '10.0.0.5    staging   staging.local api\t# staging box')" ]
}

@test "a name pointing elsewhere in the same family is refused" {
  standard_fixture
  hosts_run --yes add 10.0.0.9 staging
  [ "$status" -eq 6 ]
  [[ $stderr == *'already points at 10.0.0.5'* ]]
  [[ $stderr == *'--force'* ]]
}

@test "a refused add leaves the file alone" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  hosts_run --yes add 10.0.0.9 staging
  [ "$status" -eq 6 ]
  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "--force changes the address on the line, keeping its layout" {
  # The line is about those names and nothing else, so retargeting it in place
  # is both what updating means and the smallest possible diff.
  standard_fixture
  hosts_run --yes --force add 10.0.0.9 staging staging.local
  [ "$status" -eq 0 ]

  run sed -n 5p "$FIXTURE"
  [ "$output" = "$(printf '10.0.0.9    staging   staging.local\t# staging box')" ]
}

@test "--force moves a name off a line that carries others" {
  standard_fixture
  hosts_run --yes --force add 10.0.0.9 staging
  [ "$status" -eq 0 ]

  run sed -n 5p "$FIXTURE"
  [ "$output" = "$(printf '10.0.0.5    staging.local\t# staging box')" ]
  run tail -1 "$FIXTURE"
  [ "$output" = "$(printf '10.0.0.9\tstaging')" ]
}

@test "the same name on the other address family is not a clash" {
  # Without this, adding an IPv6 entry beside an IPv4 one would be refused on
  # every machine that has both.
  standard_fixture
  hosts_run --yes add fd00::5 staging
  [ "$status" -eq 0 ]
  run tail -1 "$FIXTURE"
  [ "$output" = "$(printf 'fd00::5\tstaging')" ]
}

@test "a disabled entry for the name is refused, pointing at on" {
  standard_fixture
  hosts_run --yes add 192.168.1.40 old-nas
  [ "$status" -eq 6 ]
  [[ $stderr == *'disabled entry'* ]]
  [[ $stderr == *'hosts on'* ]]
}

@test "--force brings a disabled entry back instead of duplicating it" {
  standard_fixture
  hosts_run --yes --force add 192.168.1.40 old-nas
  [ "$status" -eq 0 ]
  run sed -n 6p "$FIXTURE"
  [ "$output" = '192.168.1.40 old-nas' ]
  run wc -l <"$FIXTURE"
  [ "$output" -eq 6 ]
}

@test "names already there on different lines are left as they are" {
  # The state asked for already holds, so there is nothing to decide and
  # nothing to do.
  standard_fixture
  printf '10.0.0.5\tapi\n' >>"$FIXTURE"
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  hosts_run --yes add 10.0.0.5 staging api
  [ "$status" -eq 0 ]
  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "a name to place, with the others spread over several lines, is refused" {
  # Now there is something to add and no obvious line to add it to, and
  # merging lines is a decision for the user to make.
  standard_fixture
  printf '10.0.0.5\tapi\n' >>"$FIXTURE"
  hosts_run --yes add 10.0.0.5 staging api web
  [ "$status" -eq 6 ]
  [[ $stderr == *'spread over lines 5 7'* ]]
}

@test "an address that does not parse is rejected before anything is read" {
  standard_fixture
  hosts_run --yes add 999.1.1.1 nope
  [ "$status" -eq 4 ]
  [[ $stderr == *'not a valid IPv4 or IPv6 address'* ]]
}

@test "a name that breaks RFC 1123 is rejected" {
  standard_fixture
  hosts_run --yes add 10.0.0.9 bad..name
  [ "$status" -eq 4 ]
  [[ $stderr == *'not a valid hostname'* ]]
}

@test "a name starting with a hyphen needs -- and is then rejected" {
  standard_fixture
  hosts_run --yes add 10.0.0.9 -bad
  [ "$status" -eq 2 ]

  hosts_run --yes add -- 10.0.0.9 -bad
  [ "$status" -eq 4 ]
  [[ $stderr == *'not a valid hostname'* ]]
}

@test "an underscore is accepted with a warning, as check judges it" {
  standard_fixture
  hosts_run --yes add 10.0.0.9 build_two
  [ "$status" -eq 0 ]
  [[ $stderr == *'outside RFC 1123'* ]]
}

@test "add takes an address and at least one name" {
  standard_fixture
  hosts_run --yes add 10.0.0.9
  [ "$status" -eq 2 ]
}

@test "--dry-run shows the change and writes nothing" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  hosts_run --dry-run add 10.0.0.9 build
  [ "$status" -eq 0 ]
  [[ $output == *'+10.0.0.9'* ]]

  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "a backup is taken before the file is changed" {
  standard_fixture
  hosts_run --yes add 10.0.0.9 build
  [ "$status" -eq 0 ]
  hosts_run backup ls
  [ "${#lines[@]}" -eq 1 ]
}

@test "a file without a final newline gains one when appended to" {
  printf '127.0.0.1 localhost' >"$FIXTURE"
  hosts_run --yes --verbose add 10.0.0.9 build
  [ "$status" -eq 0 ]
  [[ $stderr == *'did not end with a newline'* ]]

  run bash -c "tail -c1 '$FIXTURE' | od -An -c | tr -d ' '"
  [ "$output" = '\n' ]
}

@test "several names go on one line, canonical first" {
  standard_fixture
  hosts_run --yes add 10.0.0.9 build build.local ci
  [ "$status" -eq 0 ]
  run tail -1 "$FIXTURE"
  [ "$output" = "$(printf '10.0.0.9\tbuild build.local ci')" ]
}
