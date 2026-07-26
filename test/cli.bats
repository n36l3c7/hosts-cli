#!/usr/bin/env bats
#
# Global command line surface: version, help, dispatch and global options.

load helper

@test "--version prints the program name and version on stdout" {
  run --separate-stderr "$HOSTS_BIN" --version
  [ "$status" -eq 0 ]
  [ "$output" = "hosts $HOSTS_VERSION" ]
  [ -z "$stderr" ]
}

@test "-V is an alias of --version" {
  run --separate-stderr "$HOSTS_BIN" -V
  [ "$status" -eq 0 ]
  [ "$output" = "hosts $HOSTS_VERSION" ]
}

@test "--help lists the commands on stdout" {
  run --separate-stderr "$HOSTS_BIN" --help
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  for command in ls get search check export; do
    [[ $output == *"  $command"* ]]
  done
}

@test "--help names the file it works on by default" {
  run --separate-stderr "$HOSTS_BIN" --help
  [ "$status" -eq 0 ]
  [[ $output == *'/etc/hosts'* ]]
}

@test "-h is an alias of --help" {
  run --separate-stderr "$HOSTS_BIN" -h
  [ "$status" -eq 0 ]
  [[ $output == *'Usage:'* ]]
}

@test "no argument is a usage error and writes usage to stderr" {
  run --separate-stderr "$HOSTS_BIN"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ $stderr == *'Usage:'* ]]
}

@test "an unknown command is a usage error" {
  run --separate-stderr "$HOSTS_BIN" frobnicate
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ $stderr == *'unknown command: frobnicate'* ]]
}

@test "an unknown global option is a usage error" {
  run --separate-stderr "$HOSTS_BIN" --nope
  [ "$status" -eq 2 ]
  [[ $stderr == *'unknown option: --nope'* ]]
}

@test "every command has its own help, on stdout" {
  for command in ls get search check export; do
    run --separate-stderr "$HOSTS_BIN" "$command" --help
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
    [[ $output == "Usage: hosts $command"* ]]
  done
}

@test "-h after a command shows that command's help, not the general one" {
  run --separate-stderr "$HOSTS_BIN" check -h
  [ "$status" -eq 0 ]
  [[ $output == 'Usage: hosts check'* ]]
}

@test "--file is accepted before and after the command" {
  make_fixture <<'EOF'
10.0.0.5 staging
EOF
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" ls
  [ "$status" -eq 0 ]
  local before=$output

  run --separate-stderr "$HOSTS_BIN" ls --file "$FIXTURE"
  [ "$status" -eq 0 ]
  [ "$output" = "$before" ]
}

@test "--file accepts the joined form" {
  make_fixture <<'EOF'
10.0.0.5 staging
EOF
  run --separate-stderr "$HOSTS_BIN" "--file=$FIXTURE" ls
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'10.0.0.5\tstaging\ton\t' ]
}

@test "--file without a path is a usage error" {
  run --separate-stderr "$HOSTS_BIN" --file
  [ "$status" -eq 2 ]
  [[ $stderr == *'--file requires a path'* ]]
}

@test "a file that is not there is a generic error, not a missing hostname" {
  # get exits 5 for a hostname that is absent; a missing file has to be told
  # apart from that, or a script would read one as the other.
  run --separate-stderr "$HOSTS_BIN" --file "$BATS_TEST_TMPDIR/nowhere" get staging
  [ "$status" -eq 1 ]
  [[ $stderr == *'no such file'* ]]
}

@test "a directory is not a regular file" {
  run --separate-stderr "$HOSTS_BIN" --file "$BATS_TEST_TMPDIR" ls
  [ "$status" -eq 1 ]
  [[ $stderr == *'not a regular file'* ]]
}

@test "a file that cannot be read exits 3" {
  if [ "$(id -u)" -eq 0 ]; then
    skip 'running as root, which can read anything'
  fi
  make_fixture <<'EOF'
127.0.0.1 localhost
EOF
  chmod 000 "$FIXTURE"
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" ls
  chmod 644 "$FIXTURE"
  [ "$status" -eq 3 ]
  [[ $stderr == *'permission denied'* ]]
}

@test "--verbose adds diagnostics on stderr and leaves stdout alone" {
  make_fixture <<'EOF'
10.0.0.5 staging
EOF
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" ls
  local quiet_output=$output

  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" --verbose ls
  [ "$status" -eq 0 ]
  [ "$output" = "$quiet_output" ]
  [[ $stderr == *'read 1 lines'* ]]
}

@test "--quiet silences diagnostics but never the data" {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
999.1.1.1 bogus
EOF
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" --quiet check
  [ "$status" -eq 4 ]
  [[ $output == *'invalid-ip'* ]]
  [ -z "$stderr" ]
}

@test "sourcing the script does not run main" {
  run --separate-stderr bash -c "source '$HOSTS_BIN'; version"
  [ "$status" -eq 0 ]
  [ "$output" = "hosts $HOSTS_VERSION" ]
}
