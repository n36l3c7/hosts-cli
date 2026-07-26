#!/usr/bin/env bats
#
# hosts on and hosts off.

load helper

standard_fixture() {
  {
    printf '127.0.0.1\tlocalhost\n'
    printf '::1\t\tlocalhost ip6-localhost\n'
    printf '10.0.0.5    staging   staging.local\t# staging box\n'
    printf '# 192.168.1.40 old-nas\n'
  } >"$FIXTURE"
}

@test "off comments the entry out without deleting it" {
  standard_fixture
  hosts_run --yes off staging
  [ "$status" -eq 0 ]
  run sed -n 3p "$FIXTURE"
  [ "$output" = "$(printf '# 10.0.0.5    staging   staging.local\t# staging box')" ]
}

@test "a disabled entry no longer resolves" {
  standard_fixture
  hosts_run --yes off staging
  [ "$status" -eq 0 ]
  hosts_run get staging
  [ "$status" -eq 5 ]
}

@test "on brings it back" {
  standard_fixture
  hosts_run --yes off staging
  hosts_run --yes on staging
  [ "$status" -eq 0 ]
  hosts_run get staging
  [ "$status" -eq 0 ]
  [ "$output" = '10.0.0.5' ]
}

@test "off then on gives back exactly the line that was there" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  hosts_run --yes off staging
  [ "$status" -eq 0 ]
  hosts_run --yes on staging
  [ "$status" -eq 0 ]

  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "off acts on every line carrying the name" {
  # Turning off half of a dual stack pair would leave the name resolving on
  # the other family, which is a command doing half its job.
  standard_fixture
  hosts_run --yes off localhost
  [ "$status" -eq 0 ]

  run sed -n 1p "$FIXTURE"
  [ "$output" = "$(printf '# 127.0.0.1\tlocalhost')" ]
  run sed -n 2p "$FIXTURE"
  [ "$output" = "$(printf '# ::1\t\tlocalhost ip6-localhost')" ]

  hosts_run get localhost
  [ "$status" -eq 5 ]
}

@test "on enables a line that was commented out by hand" {
  standard_fixture
  hosts_run --yes on old-nas
  [ "$status" -eq 0 ]
  run sed -n 4p "$FIXTURE"
  [ "$output" = '192.168.1.40 old-nas' ]
}

@test "asking for a state that already holds changes nothing and succeeds" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  hosts_run --yes --verbose on staging
  [ "$status" -eq 0 ]
  [[ $stderr == *'already on'* ]]

  hosts_run --yes --verbose off old-nas
  [ "$status" -eq 0 ]
  [[ $stderr == *'already off'* ]]

  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "a name that is nowhere exits 5" {
  standard_fixture
  hosts_run --yes off nowhere
  [ "$status" -eq 5 ]
  hosts_run --yes on nowhere
  [ "$status" -eq 5 ]
}

@test "the untouched lines stay byte for byte the same" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  hosts_run --yes off staging
  [ "$status" -eq 0 ]

  run bash -c "head -2 '$FIXTURE' | cmp - <(head -2 '$BATS_TEST_TMPDIR/before')"
  [ "$status" -eq 0 ]
  run bash -c "tail -1 '$FIXTURE' | cmp - <(tail -1 '$BATS_TEST_TMPDIR/before')"
  [ "$status" -eq 0 ]
}

@test "a change reaching several lines asks first" {
  standard_fixture
  hosts_run off localhost
  [ "$status" -eq 8 ]
}

@test "on and off take exactly one hostname" {
  standard_fixture
  hosts_run --yes off
  [ "$status" -eq 2 ]
  hosts_run --yes on one two
  [ "$status" -eq 2 ]
}

@test "--dry-run shows the change and writes nothing" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  hosts_run --dry-run off staging
  [ "$status" -eq 0 ]
  [[ $output == *'+# 10.0.0.5'* ]]
  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "a disabled entry is still listed by ls --all" {
  standard_fixture
  hosts_run --yes off staging
  hosts_run ls --disabled
  [ "$status" -eq 0 ]
  [[ $output == *$'10.0.0.5\tstaging staging.local\toff'* ]]
}
