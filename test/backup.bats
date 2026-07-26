#!/usr/bin/env bats
#
# hosts backup and hosts backup ls.

load helper

standard_fixture() {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
10.0.0.5 staging
EOF
}

@test "backup prints the identifier of the copy it took" {
  standard_fixture
  hosts_run backup
  [ "$status" -eq 0 ]
  [[ $output =~ ^[0-9]{8}T[0-9]{6}\.[0-9]{3}Z$ ]]
}

@test "the copy is byte for byte identical to the file" {
  standard_fixture
  hosts_run backup
  [ "$status" -eq 0 ]
  run cmp -- "$FIXTURE" "$(newest_copy)"
  [ "$status" -eq 0 ]
}

@test "the sidecar records where the backup came from and what it holds" {
  standard_fixture
  hosts_run backup
  [ "$status" -eq 0 ]

  run cat "$(newest_meta)"
  [[ $output == *"target=$FIXTURE"* ]]
  [[ $output == *'mode=644'* ]]
  [[ $output == *"owner=$(id -un)"* ]]
  [[ $output == *'sha256='* ]]
  [[ $output == *'time='* ]]

  run bash -c "grep '^sha256=' '$(newest_meta)' | cut -d= -f2"
  local recorded=$output
  run bash -c "sha256sum '$FIXTURE' | cut -d' ' -f1"
  [ "$output" = "$recorded" ]
}

@test "an unchanged file is not backed up twice" {
  # Without this, a run of writes that change nothing would push every backup
  # that matters out of the rotation window.
  standard_fixture
  hosts_run backup
  [ "$status" -eq 0 ]
  hosts_run backup
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  hosts_run backup ls
  [ "${#lines[@]}" -eq 1 ]
}

@test "the reason a backup was skipped is said under --verbose" {
  standard_fixture
  hosts_run backup
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" --verbose backup
  [ "$status" -eq 0 ]
  [[ $stderr == *'unchanged since the backup'* ]]
}

@test "a changed file is backed up again" {
  standard_fixture
  hosts_run backup
  printf '10.0.0.9 build\n' >>"$FIXTURE"
  hosts_run backup
  [ "$status" -eq 0 ]
  hosts_run backup ls
  [ "${#lines[@]}" -eq 2 ]
}

@test "backup ls has four tab separated fields, newest first" {
  standard_fixture
  hosts_run backup
  printf '10.0.0.9 build\n' >>"$FIXTURE"
  hosts_run backup

  hosts_run backup ls
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]

  local line
  for line in "${lines[@]}"; do
    [ "${line//[^$'\t']/}" = $'\t\t\t' ]
  done

  [[ ${lines[0]} == '1'$'\t'* ]]
  [[ ${lines[1]} == '2'$'\t'* ]]

  local first_size second_size
  first_size=$(printf '%s' "${lines[0]}" | cut -f4)
  second_size=$(printf '%s' "${lines[1]}" | cut -f4)
  [ "$first_size" -gt "$second_size" ]
}

@test "backup ls on an empty store produces no output and succeeds" {
  standard_fixture
  hosts_run backup ls
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "two different files get separate stores" {
  standard_fixture
  hosts_run backup

  local other="$BATS_TEST_TMPDIR/other"
  printf '10.0.0.1 other\n' >"$other"
  run --separate-stderr "$HOSTS_BIN" --file "$other" backup
  [ "$status" -eq 0 ]

  run --separate-stderr "$HOSTS_BIN" --file "$other" backup ls
  [ "${#lines[@]}" -eq 1 ]

  hosts_run backup ls
  [ "${#lines[@]}" -eq 1 ]
}

@test "a copy without its sidecar is an interrupted backup and is ignored" {
  standard_fixture
  hosts_run backup
  rm -f -- "$(newest_meta)"
  hosts_run backup ls
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "rotation keeps only what it was told to keep" {
  standard_fixture
  local i
  for i in 1 2 3 4 5; do
    printf '10.0.0.%d host%d\n' "$i" "$i" >>"$FIXTURE"
    HOSTS_KEEP_BACKUPS=2 run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" backup
    [ "$status" -eq 0 ]
  done

  HOSTS_KEEP_BACKUPS=2 run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" backup ls
  [ "${#lines[@]}" -eq 2 ]
}

@test "rotation never removes the last backup" {
  standard_fixture
  HOSTS_KEEP_BACKUPS=0 run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" backup
  [ "$status" -eq 0 ]
  HOSTS_KEEP_BACKUPS=0 run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" backup ls
  [ "${#lines[@]}" -eq 1 ]
}

@test "--dry-run takes no backup" {
  standard_fixture
  hosts_run --dry-run backup
  [ "$status" -eq 0 ]
  hosts_run backup ls
  [ -z "$output" ]
}

@test "backup ls --json reports the store and every copy" {
  standard_fixture
  hosts_run backup
  hosts_run --json backup ls
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = '{' ]
  [ "${lines[1]}" = '  "version": 1,' ]
  [ "${lines[2]}" = "  \"file\": \"$FIXTURE\"," ]
  [[ ${lines[3]} == '  "directory": "'* ]]
  [ "${lines[4]}" = '  "backups": [' ]
  [[ $output == *'"index": 1,'* ]]
  [[ $output == *'"sha256": "'* ]]
  [[ $output == *'"owner": "'* ]]
}

@test "backup ls --json on an empty store emits an empty array" {
  standard_fixture
  hosts_run --json backup ls
  [ "$status" -eq 0 ]
  [[ $output == *'"backups": []'* ]]
}

@test "an unknown subcommand is a usage error" {
  standard_fixture
  hosts_run backup nonsense
  [ "$status" -eq 2 ]
  [[ $stderr == *"unknown subcommand for 'backup': nonsense"* ]]
}

@test "taking a backup needs no permission on the file itself" {
  # It only reads the file; what it needs is somewhere to write the copy.
  if [ "$(id -u)" -eq 0 ]; then
    skip 'running as root, which can write anything'
  fi
  standard_fixture
  chmod 0444 "$FIXTURE"
  hosts_run backup
  chmod 0644 "$FIXTURE"
  [ "$status" -eq 0 ]
}

@test "an unwritable store fails with the variable to set" {
  if [ "$(id -u)" -eq 0 ]; then
    skip 'running as root, which can write anything'
  fi
  standard_fixture
  mkdir -p "$BATS_TEST_TMPDIR/locked"
  chmod 000 "$BATS_TEST_TMPDIR/locked"
  HOSTS_BACKUP_DIR="$BATS_TEST_TMPDIR/locked/store" \
    run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" backup
  chmod 755 "$BATS_TEST_TMPDIR/locked"
  [ "$status" -eq 3 ]
  [[ $stderr == *'HOSTS_BACKUP_DIR'* ]]
}
