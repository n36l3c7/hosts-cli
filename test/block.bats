#!/usr/bin/env bats
#
# hosts block, and the way the rest of the program treats its section.

load helper

standard_fixture() {
  {
    printf '127.0.0.1\tlocalhost\n'
    printf '::1\t\tlocalhost\n'
    printf '10.0.0.5\tstaging\n'
  } >"$FIXTURE"
}

@test "the first block opens the section at the end of the file" {
  standard_fixture
  hosts_run --yes block ads.example.com
  [ "$status" -eq 0 ]

  run cat "$FIXTURE"
  [ "${lines[3]}" = '# >>> hosts block >>>' ]
  [[ ${lines[4]} == '# Managed by hosts(1)'* ]]
  [ "${lines[5]}" = "$(printf '0.0.0.0\tads.example.com')" ]
  [ "${lines[6]}" = "$(printf '::\tads.example.com')" ]
  [ "${lines[7]}" = '# <<< hosts block <<<' ]
}

@test "both address families are used" {
  # On a machine with IPv6 a block that only covers IPv4 blocks nothing at
  # all, which is the mistake most blocklist tools make.
  standard_fixture
  hosts_run --yes block ads.example.com
  [ "$status" -eq 0 ]
  run grep -c 'ads.example.com' "$FIXTURE"
  [ "$output" -eq 2 ]
}

@test "--ipv4-only uses one address" {
  standard_fixture
  hosts_run --yes block --ipv4-only ads.example.com
  [ "$status" -eq 0 ]
  run grep -c 'ads.example.com' "$FIXTURE"
  [ "$output" -eq 1 ]
  [[ $(cat "$FIXTURE") == *'0.0.0.0'* ]]
}

@test "--to picks the sinkhole address" {
  standard_fixture
  hosts_run --yes block --to 127.0.0.1 ads.example.com
  [ "$status" -eq 0 ]
  run grep -c '127.0.0.1.*ads.example.com' "$FIXTURE"
  [ "$output" -eq 1 ]
}

@test "--to with something that is not an address is rejected" {
  standard_fixture
  hosts_run --yes block --to nonsense ads.example.com
  [ "$status" -eq 4 ]
}

@test "a later block goes inside the section that is already there" {
  standard_fixture
  hosts_run --yes block ads.example.com
  hosts_run --yes block tracker.example.com
  [ "$status" -eq 0 ]

  run cat "$FIXTURE"
  [ "${lines[9]}" = '# <<< hosts block <<<' ]
  [ "${#lines[@]}" -eq 10 ]
}

@test "blocking the same domain again changes nothing" {
  standard_fixture
  hosts_run --yes block ads.example.com
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  hosts_run --yes block ads.example.com
  [ "$status" -eq 0 ]
  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "a domain with an entry outside the section is skipped, not fatal" {
  # A command handed many domains should not give up at the first obstacle.
  standard_fixture
  hosts_run --yes block staging ads.example.com
  [ "$status" -eq 0 ]
  [[ $stderr == *'already has an entry outside the block section'* ]]

  run grep -c 'ads.example.com' "$FIXTURE"
  [ "$output" -eq 2 ]
  run grep -c '0.0.0.0.*staging' "$FIXTURE"
  [ "$status" -ne 0 ]
}

@test "ls leaves the block section out, --blocked puts it back" {
  standard_fixture
  hosts_run --yes block ads.example.com

  hosts_run ls
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]

  hosts_run ls --blocked
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
}

@test "get still resolves a blocked domain" {
  standard_fixture
  hosts_run --yes block ads.example.com

  hosts_run get ads.example.com
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = '0.0.0.0' ]
  [ "${lines[1]}" = '::' ]
}

@test "search still finds a blocked domain" {
  standard_fixture
  hosts_run --yes block ads.example.com
  hosts_run search ads.example
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "check does not compare the lines of the section with each other" {
  # Thousands of near identical names written by a script would be nothing
  # but noise.
  standard_fixture
  hosts_run --yes block a.example.com
  hosts_run --yes block b.example.com

  hosts_run check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check still applies the per line rules inside the section" {
  standard_fixture
  hosts_run --yes block ads.example.com
  printf '0.0.0.0\t-bad\n' >>"$FIXTURE"
  # Move the bad line inside the section.
  run bash -c "sed -i '\$d' '$FIXTURE'; sed -i 's|^# <<< hosts block <<<|0.0.0.0\t-bad\n# <<< hosts block <<<|' '$FIXTURE'"
  [ "$status" -eq 0 ]

  hosts_run check
  [ "$status" -eq 4 ]
  [[ $output == *'invalid-hostname'* ]]
}

@test "rm unblocks a domain like any other entry" {
  standard_fixture
  hosts_run --yes block ads.example.com tracker.example.com
  hosts_run --yes rm ads.example.com
  [ "$status" -eq 0 ]
  run grep -c 'ads.example.com' "$FIXTURE"
  [ "$status" -ne 0 ]
  run grep -c 'tracker.example.com' "$FIXTURE"
  [ "$output" -eq 2 ]
}

@test "emptying the section takes the markers with it" {
  standard_fixture
  hosts_run --yes block ads.example.com
  hosts_run --yes rm ads.example.com
  [ "$status" -eq 0 ]

  run cat "$FIXTURE"
  [ "${#lines[@]}" -eq 3 ]
  [[ $output != *'hosts block'* ]]
}

@test "domains are read from standard input when none are given" {
  # A real blocklist has tens of thousands of domains, which do not fit on a
  # command line.
  standard_fixture
  run --separate-stderr bash -c "printf '# a comment\n\nads.example.com\ntracker.example.com\n' | '$HOSTS_BIN' --file '$FIXTURE' --yes block"
  [ "$status" -eq 0 ]

  run grep -c 'example.com' "$FIXTURE"
  [ "$output" -eq 4 ]
}

@test "a domain that is not a hostname is rejected" {
  standard_fixture
  hosts_run --yes block 'not a domain'
  [ "$status" -eq 4 ]
}

@test "block with no domain and a terminal is a usage error" {
  standard_fixture
  hosts_run --yes block </dev/null
  [ "$status" -eq 2 ]
}

@test "--dry-run shows the change and writes nothing" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  hosts_run --dry-run block ads.example.com
  [ "$status" -eq 0 ]
  [[ $output == *'+# >>> hosts block >>>'* ]]
  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}
