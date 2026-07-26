#!/usr/bin/env bats
#
# hosts edit.

load helper

standard_fixture() {
  {
    printf '127.0.0.1\tlocalhost\n'
    printf '::1\t\tlocalhost\n'
  } >"$FIXTURE"
}

# Install a scripted editor and run edit with it. The editor is handed the
# copy, exactly as a real one would be.
with_editor() {
  local script=$1
  shift
  EDITOR_SCRIPT="$BATS_TEST_TMPDIR/editor"
  printf '#!/bin/bash\n%s\n' "$script" >"$EDITOR_SCRIPT"
  chmod +x "$EDITOR_SCRIPT"
  run --separate-stderr env EDITOR="$EDITOR_SCRIPT" \
    "$HOSTS_BIN" --file "$FIXTURE" "$@"
}

@test "what the editor wrote is installed" {
  standard_fixture
  with_editor 'printf "10.0.0.5\tstaging\n" >>"$1"' --yes edit
  [ "$status" -eq 0 ]

  run tail -1 "$FIXTURE"
  [ "$output" = "$(printf '10.0.0.5\tstaging')" ]
}

@test "the editor works on a copy, not on the file itself" {
  standard_fixture
  with_editor 'printf "%s\n" "$1" >"'"$BATS_TEST_TMPDIR"'/seen"' --yes edit
  [ "$status" -eq 0 ]

  run cat "$BATS_TEST_TMPDIR/seen"
  [ "$output" != "$FIXTURE" ]
}

@test "an editor that changes nothing leaves the file alone" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  with_editor ':' --yes --verbose edit
  [ "$status" -eq 0 ]
  [[ $stderr == *'unchanged'* ]]

  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "an edit that leaves errors is not installed, and the work is kept" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  with_editor 'printf "999.1.1.1\tbogus\n" >>"$1"' --yes edit
  [ "$status" -eq 4 ]
  [[ $stderr == *'invalid-ip'* ]]
  [[ $stderr == *'kept there'* ]]

  # Taken out now, before the next run replaces $stderr. The findings printed
  # before this message end in "hosts:3:", with no space, so the last
  # "hosts: " in the output is where the message starts.
  local kept=${stderr##*hosts: }
  kept=${kept%% has *}

  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]

  [ -n "$kept" ]
  [ -f "$kept" ]
  run grep -c 'bogus' "$kept"
  [ "$output" -eq 1 ]
}

@test "a warning does not stop the file being installed" {
  # The same judgement check makes without --strict.
  standard_fixture
  with_editor 'printf "192.168.1.9\tprinter_two\n" >>"$1"' --yes edit
  [ "$status" -eq 0 ]
  [[ $stderr == *'nonstandard-hostname'* ]]
  run grep -c 'printer_two' "$FIXTURE"
  [ "$output" -eq 1 ]
}

@test "a backup is taken before the edit is installed" {
  standard_fixture
  with_editor 'printf "10.0.0.5\tstaging\n" >>"$1"' --yes edit
  [ "$status" -eq 0 ]

  hosts_run backup ls
  [ "${#lines[@]}" -eq 1 ]
}

@test "an editor that fails is reported and nothing is written" {
  standard_fixture
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  with_editor 'exit 1' --yes edit
  [ "$status" -eq 1 ]
  [[ $stderr == *'editor exited with an error'* ]]

  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "the editor runs with the locale of the user, not the one used to parse" {
  # LC_ALL=C is right for matching character ranges and wrong to hand to an
  # editor about to be shown someone else's text.
  standard_fixture
  with_editor 'printf "%s\n" "${LC_ALL:-unset}" >"'"$BATS_TEST_TMPDIR"'/locale"' --yes edit

  run cat "$BATS_TEST_TMPDIR/locale"
  [ "$output" != 'C' ]
}

@test "VISUAL wins over EDITOR" {
  standard_fixture
  local visual="$BATS_TEST_TMPDIR/visual"
  printf '#!/bin/bash\nprintf "10.0.0.7\\tvisual\\n" >>"$1"\n' >"$visual"
  chmod +x "$visual"

  local editor="$BATS_TEST_TMPDIR/editor"
  printf '#!/bin/bash\nprintf "10.0.0.8\\teditor\\n" >>"$1"\n' >"$editor"
  chmod +x "$editor"

  run --separate-stderr env VISUAL="$visual" EDITOR="$editor" \
    "$HOSTS_BIN" --file "$FIXTURE" --yes edit
  [ "$status" -eq 0 ]

  run grep -c 'visual' "$FIXTURE"
  [ "$output" -eq 1 ]
  run grep -c 'editor' "$FIXTURE"
  [ "$status" -ne 0 ]
}

@test "edit takes no argument and has nothing to preview" {
  standard_fixture
  hosts_run --yes edit something
  [ "$status" -eq 2 ]

  hosts_run --dry-run edit
  [ "$status" -eq 2 ]
}

@test "a file that cannot be written fails before the editor opens" {
  if [ "$(id -u)" -eq 0 ]; then
    skip 'running as root, which can write anything'
  fi
  mkdir -p "$BATS_TEST_TMPDIR/locked"
  printf '127.0.0.1 localhost\n' >"$BATS_TEST_TMPDIR/locked/hosts"
  chmod 500 "$BATS_TEST_TMPDIR/locked"

  local marker="$BATS_TEST_TMPDIR/opened"
  local script="$BATS_TEST_TMPDIR/editor"
  printf '#!/bin/bash\ntouch "%s"\n' "$marker" >"$script"
  chmod +x "$script"

  run --separate-stderr env EDITOR="$script" \
    "$HOSTS_BIN" --file "$BATS_TEST_TMPDIR/locked/hosts" --yes edit
  local seen=$status
  chmod 755 "$BATS_TEST_TMPDIR/locked"

  [ "$seen" -eq 3 ]
  [ ! -e "$marker" ]
}
