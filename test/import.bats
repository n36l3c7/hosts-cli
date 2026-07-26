#!/usr/bin/env bats
#
# hosts import.

load helper

standard_fixture() {
  {
    printf '127.0.0.1\tlocalhost\n'
    printf '::1\t\tlocalhost\n'
    printf '10.0.0.5\tstaging\n'
  } >"$FIXTURE"
}

source_file() {
  SOURCE="$BATS_TEST_TMPDIR/source"
  cat >"$SOURCE"
}

@test "entries that are not there are added at the end" {
  standard_fixture
  source_file <<'EOF'
10.0.0.9	build
192.168.1.9	printer
EOF
  hosts_run --yes import "$SOURCE"
  [ "$status" -eq 0 ]

  run cat "$FIXTURE"
  [ "${#lines[@]}" -eq 5 ]
  [ "${lines[3]}" = "$(printf '10.0.0.9\tbuild')" ]
}

@test "the comment of an imported entry comes with it" {
  standard_fixture
  source_file <<'EOF'
10.0.0.9	build	# build box
EOF
  hosts_run --yes import "$SOURCE"
  [ "$status" -eq 0 ]
  run tail -1 "$FIXTURE"
  [ "$output" = "$(printf '10.0.0.9\tbuild\t# build box')" ]
}

@test "an entry that is already there is left alone" {
  standard_fixture
  source_file <<'EOF'
10.0.0.5	staging
EOF
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  hosts_run --yes --verbose import "$SOURCE"
  [ "$status" -eq 0 ]
  [[ $stderr == *'1 already there'* ]]
  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "an entry pointing somewhere else is skipped and reported" {
  standard_fixture
  source_file <<'EOF'
10.0.0.9	staging
EOF
  hosts_run --yes import "$SOURCE"
  [ "$status" -eq 0 ]
  [[ $stderr == *'skipped'* ]]
  run grep -c '10.0.0.9' "$FIXTURE"
  [ "$status" -ne 0 ]
}

@test "an entry that only partly overlaps is skipped whole" {
  # A line half imported would put a name on two lines at once, which is not
  # something the file can express.
  standard_fixture
  source_file <<'EOF'
10.0.0.5	staging build
EOF
  hosts_run --yes import "$SOURCE"
  [ "$status" -eq 0 ]
  run grep -c 'build' "$FIXTURE"
  [ "$status" -ne 0 ]
}

@test "only active entries are taken" {
  standard_fixture
  source_file <<'EOF'
# a note to myself
# 10.0.0.9	build
192.168.1.9	printer
EOF
  hosts_run --yes import "$SOURCE"
  [ "$status" -eq 0 ]
  run wc -l <"$FIXTURE"
  [ "$output" -eq 4 ]
  run grep -c 'build' "$FIXTURE"
  [ "$status" -ne 0 ]
}

@test "one bad line makes the whole import fail" {
  # Importing half of a broken file leaves a machine in a state nobody can
  # explain later.
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  source_file <<'EOF'
10.0.0.9	build
999.1.1.1	bogus
192.168.1.9	printer
EOF
  hosts_run --yes import "$SOURCE"
  [ "$status" -eq 4 ]
  [[ $stderr == *'invalid-ip'* ]]
  [[ $stderr == *'check'* ]]

  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "the source is read from standard input when no file is given" {
  standard_fixture
  run --separate-stderr bash -c "printf '10.0.0.9\tbuild\n' | '$HOSTS_BIN' --file '$FIXTURE' --yes import"
  [ "$status" -eq 0 ]
  run tail -1 "$FIXTURE"
  [ "$output" = "$(printf '10.0.0.9\tbuild')" ]
}

@test "a dash means standard input too" {
  standard_fixture
  run --separate-stderr bash -c "printf '10.0.0.9\tbuild\n' | '$HOSTS_BIN' --file '$FIXTURE' --yes import -"
  [ "$status" -eq 0 ]
  run grep -c 'build' "$FIXTURE"
  [ "$output" -eq 1 ]
}

@test "a source that is not there is a plain error" {
  standard_fixture
  hosts_run --yes import "$BATS_TEST_TMPDIR/nowhere"
  [ "$status" -eq 1 ]
  [[ $stderr == *'no such file'* ]]
}

@test "importing nothing changes nothing" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  source_file <<'EOF'
# only a comment
EOF
  hosts_run --yes import "$SOURCE"
  [ "$status" -eq 0 ]
  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "import takes one file at most" {
  standard_fixture
  hosts_run --yes import one two
  [ "$status" -eq 2 ]
}

@test "--dry-run shows the change and writes nothing" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  source_file <<'EOF'
10.0.0.9	build
EOF
  hosts_run --dry-run import "$SOURCE"
  [ "$status" -eq 0 ]
  [[ $output == *'+10.0.0.9'* ]]
  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "a backup is taken before the file is changed" {
  standard_fixture
  source_file <<'EOF'
10.0.0.9	build
EOF
  hosts_run --yes import "$SOURCE"
  [ "$status" -eq 0 ]
  hosts_run backup ls
  [ "${#lines[@]}" -eq 1 ]
}
