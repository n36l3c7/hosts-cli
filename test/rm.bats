#!/usr/bin/env bats
#
# hosts rm.

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

@test "a name is taken off the line, leaving the layout alone" {
  standard_fixture
  hosts_run --yes rm staging.local
  [ "$status" -eq 0 ]
  run sed -n 5p "$FIXTURE"
  [ "$output" = "$(printf '10.0.0.5    staging\t# staging box')" ]
}

@test "removing the canonical name promotes the next one" {
  standard_fixture
  hosts_run --yes rm staging
  [ "$status" -eq 0 ]
  run sed -n 5p "$FIXTURE"
  [ "$output" = "$(printf '10.0.0.5    staging.local\t# staging box')" ]
}

@test "a line left with nothing but its address is dropped" {
  standard_fixture
  hosts_run --yes rm staging
  [ "$status" -eq 0 ]
  hosts_run --yes rm staging.local
  [ "$status" -eq 0 ]

  run grep -c '10.0.0.5' "$FIXTURE"
  [ "$status" -ne 0 ]
  run wc -l <"$FIXTURE"
  [ "$output" -eq 5 ]
}

@test "the name goes from every line carrying it" {
  standard_fixture
  hosts_run --yes rm localhost
  [ "$status" -eq 0 ]

  # The IPv4 line carried nothing else and is gone; the IPv6 line keeps its
  # remaining alias, and with it the layout it had.
  run sed -n 2p "$FIXTURE"
  [ "$output" = "$(printf '::1\t\tip6-localhost')" ]
  run grep -c 'localhost' "$FIXTURE"
  [ "$output" -eq 1 ]
}

@test "a disabled entry loses the name too" {
  standard_fixture
  hosts_run --yes rm old-nas
  [ "$status" -eq 0 ]
  run grep -c 'old-nas' "$FIXTURE"
  [ "$status" -ne 0 ]
}

@test "an address removes every line pointing at it" {
  standard_fixture
  printf '10.0.0.5\tapi\n' >>"$FIXTURE"
  hosts_run --yes rm 10.0.0.5
  [ "$status" -eq 0 ]
  run grep -c '10.0.0.5' "$FIXTURE"
  [ "$status" -ne 0 ]
}

@test "the untouched lines stay byte for byte the same" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  hosts_run --yes rm staging.local
  [ "$status" -eq 0 ]

  run bash -c "head -4 '$FIXTURE' | cmp - <(head -4 '$BATS_TEST_TMPDIR/before')"
  [ "$status" -eq 0 ]
  run bash -c "tail -1 '$FIXTURE' | cmp - <(tail -1 '$BATS_TEST_TMPDIR/before')"
  [ "$status" -eq 0 ]
}

@test "a name that is nowhere exits 5, so a typo is not taken for success" {
  standard_fixture
  hosts_run --yes rm nowhere
  [ "$status" -eq 5 ]
  [[ $stderr == *'no entry carries the name nowhere'* ]]
}

@test "an address that is nowhere exits 5" {
  standard_fixture
  hosts_run --yes rm 203.0.113.7
  [ "$status" -eq 5 ]
  [[ $stderr == *'no entry points at'* ]]
}

@test "a failed rm leaves the file alone" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  hosts_run --yes rm nowhere
  [ "$status" -eq 5 ]
  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "a removal that reaches several lines asks first" {
  standard_fixture
  hosts_run rm localhost
  [ "$status" -eq 8 ]
  [[ $stderr == *'2 lines'* ]]
}

@test "a removal on one line does not ask" {
  standard_fixture
  hosts_run rm staging.local
  [ "$status" -eq 0 ]
}

@test "rm takes exactly one argument" {
  standard_fixture
  hosts_run --yes rm one two
  [ "$status" -eq 2 ]
}

@test "--dry-run shows the change and writes nothing" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  hosts_run --dry-run rm staging.local
  [ "$status" -eq 0 ]
  [[ $output == *'-10.0.0.5'* ]]
  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}
