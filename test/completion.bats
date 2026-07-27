#!/usr/bin/env bats
#
# The bash completion.
#
# The completion function is driven the way bash drives it, by setting
# COMP_WORDS and COMP_CWORD and reading COMPREPLY back.

load helper

# Put the built script on PATH under the name the completion calls, so that
# the parts that ask the program for values work.
setup_path() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nexec %s "$@"\n' "$HOSTS_BIN" >"$BATS_TEST_TMPDIR/bin/hosts"
  chmod +x "$BATS_TEST_TMPDIR/bin/hosts"
}

# Complete the given command line. The last word is the one being completed;
# end the line with an empty argument to complete a fresh word.
complete_line() {
  local -a words=("$@")
  local quoted='' word

  for word in "${words[@]}"; do
    quoted+=" $(printf '%q' "$word")"
  done

  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
    HOSTS_BACKUP_DIR="$HOSTS_BACKUP_DIR" \
    HOSTS_PROFILE_DIR="$HOSTS_PROFILE_DIR" \
    bash -c "
      source '$REPO_ROOT/completions/hosts.bash'
      COMP_WORDS=($quoted)
      COMP_CWORD=$((${#words[@]} - 1))
      _hosts_completions
      printf '%s\n' \"\${COMPREPLY[@]}\"
    "
}

standard_fixture() {
  {
    printf '127.0.0.1\tlocalhost\n'
    printf '10.0.0.5\tstaging staging.local\n'
    printf '10.0.0.9\tbuild\n'
  } >"$FIXTURE"
}

@test "the commands are offered first" {
  setup_path
  complete_line hosts ''
  [ "$status" -eq 0 ]
  [[ $output == *'ls'* ]]
  [[ $output == *'profile'* ]]
  [[ $output == *'flush'* ]]
}

@test "a partial command is narrowed down" {
  setup_path
  complete_line hosts 'pro'
  [ "$status" -eq 0 ]
  [ "$output" = 'profile' ]
}

@test "a leading hyphen offers the global options" {
  setup_path
  complete_line hosts '--'
  [ "$status" -eq 0 ]
  [[ $output == *'--file'* ]]
  [[ $output == *'--dry-run'* ]]
}

@test "the options of a command are offered after it" {
  setup_path
  complete_line hosts ls '--'
  [ "$status" -eq 0 ]
  [[ $output == *'--blocked'* ]]
  [[ $output == *'--disabled'* ]]
}

@test "hostnames are offered for the commands that take one" {
  setup_path
  standard_fixture
  complete_line hosts --file "$FIXTURE" get ''
  [ "$status" -eq 0 ]
  [[ $output == *'localhost'* ]]
  [[ $output == *'staging'* ]]
  [[ $output == *'staging.local'* ]]
  [[ $output == *'build'* ]]
}

@test "hostnames are narrowed down by what is typed" {
  setup_path
  standard_fixture
  complete_line hosts --file "$FIXTURE" rm 'stag'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ $output == *'staging'* ]]
}

@test "the joined form of --file is followed too" {
  setup_path
  standard_fixture
  complete_line hosts "--file=$FIXTURE" on 'buil'
  [ "$status" -eq 0 ]
  [ "$output" = 'build' ]
}

@test "hostnames are not offered once the file is large" {
  # Offering them means parsing the file, which on a blocklist takes seconds
  # and would leave the shell looking hung.
  setup_path
  {
    printf '10.0.0.5\tstaging\n'
    local i
    for ((i = 0; i < 50; i++)); do
      printf '0.0.0.0\tads-%d.example.com\n' "$i"
    done
  } >"$FIXTURE"

  HOSTS_COMPLETION_MAX_LINES=10 run --separate-stderr env \
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" HOSTS_COMPLETION_MAX_LINES=10 \
    bash -c "
      source '$REPO_ROOT/completions/hosts.bash'
      COMP_WORDS=(hosts --file '$FIXTURE' get '')
      COMP_CWORD=4
      _hosts_completions
      printf '%s\n' \"\${COMPREPLY[@]}\"
    "
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # Below the threshold the same line completes normally.
  HOSTS_COMPLETION_MAX_LINES=100 run --separate-stderr env \
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" HOSTS_COMPLETION_MAX_LINES=100 \
    bash -c "
      source '$REPO_ROOT/completions/hosts.bash'
      COMP_WORDS=(hosts --file '$FIXTURE' get 'stag')
      COMP_CWORD=4
      _hosts_completions
      printf '%s\n' \"\${COMPREPLY[@]}\"
    "
  [ "$output" = 'staging' ]
}

@test "the subcommands of profile are offered" {
  setup_path
  standard_fixture
  complete_line hosts --file "$FIXTURE" profile ''
  [ "$status" -eq 0 ]
  [[ $output == *'save'* ]]
  [[ $output == *'load'* ]]
  [[ $output == *'ls'* ]]
  [[ $output == *'rm'* ]]
}

@test "profile names are offered for load and rm, and cost no parsing" {
  setup_path
  standard_fixture
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" profile save work
  [ "$status" -eq 0 ]

  complete_line hosts --file "$FIXTURE" profile load ''
  [ "$status" -eq 0 ]
  [ "$output" = 'work' ]
}

@test "backup identifiers are offered for restore and diff" {
  setup_path
  standard_fixture
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" backup
  [ "$status" -eq 0 ]
  local id=$output

  complete_line hosts --file "$FIXTURE" restore ''
  [ "$status" -eq 0 ]
  [ "$output" = "$id" ]
}

@test "backup offers its only subcommand" {
  setup_path
  standard_fixture
  complete_line hosts --file "$FIXTURE" backup ''
  [ "$status" -eq 0 ]
  [ "$output" = 'ls' ]
}

@test "a command that takes no value offers nothing" {
  setup_path
  standard_fixture
  complete_line hosts --file "$FIXTURE" flush ''
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
