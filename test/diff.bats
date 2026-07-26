#!/usr/bin/env bats
#
# hosts diff.

load helper

backed_up_fixture() {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
EOF
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" backup
  [ "$status" -eq 0 ]
}

@test "diff shows what the file has gained and lost since the backup" {
  backed_up_fixture
  printf '10.0.0.5 staging\n' >>"$FIXTURE"
  sed -i '1d' "$FIXTURE"

  hosts_run diff
  [ "$status" -eq 0 ]
  [[ $output == *'-127.0.0.1 localhost'* ]]
  [[ $output == *'+10.0.0.5 staging'* ]]
}

@test "diff succeeds when there is nothing to show" {
  # A difference is not a failure: the exit code is about whether the
  # comparison could be made.
  backed_up_fixture
  hosts_run diff
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "diff succeeds when there is something to show" {
  backed_up_fixture
  printf '10.0.0.5 staging\n' >>"$FIXTURE"
  hosts_run diff
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "diff compares against the most recent backup by default" {
  backed_up_fixture
  printf '10.0.0.5 staging\n' >>"$FIXTURE"
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" backup
  [ "$status" -eq 0 ]

  hosts_run diff
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "diff accepts an index" {
  backed_up_fixture
  printf '10.0.0.5 staging\n' >>"$FIXTURE"
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" backup

  hosts_run diff 2
  [ "$status" -eq 0 ]
  [[ $output == *'+10.0.0.5 staging'* ]]
}

@test "diff with no backup at all exits 5" {
  make_fixture <<'EOF'
127.0.0.1 localhost
EOF
  hosts_run diff
  [ "$status" -eq 5 ]
}

@test "diff accepts at most one backup" {
  backed_up_fixture
  hosts_run diff 1 2
  [ "$status" -eq 2 ]
}
