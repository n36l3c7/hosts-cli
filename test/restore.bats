#!/usr/bin/env bats
#
# hosts restore.

load helper

# Leave two backups behind: the first of the original file, the second of the
# file with one line added.
two_backups() {
  make_fixture <<'EOF'
127.0.0.1 localhost
::1 localhost
EOF
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" backup
  [ "$status" -eq 0 ]

  printf '10.0.0.5 staging\n' >>"$FIXTURE"
  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" backup
  [ "$status" -eq 0 ]
}

@test "restore puts the most recent backup back by default" {
  two_backups
  printf '10.0.0.9 build\n' >>"$FIXTURE"

  hosts_run --yes restore
  [ "$status" -eq 0 ]

  run cat "$FIXTURE"
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[2]}" = '10.0.0.5 staging' ]
}

@test "restore accepts the index that backup ls shows" {
  two_backups
  hosts_run --yes restore 2
  [ "$status" -eq 0 ]
  run cat "$FIXTURE"
  [ "${#lines[@]}" -eq 2 ]
}

@test "restore accepts the identifier in full" {
  two_backups
  hosts_run backup ls
  local oldest
  oldest=$(printf '%s' "${lines[1]}" | cut -f2)

  hosts_run --yes restore "$oldest"
  [ "$status" -eq 0 ]
  run cat "$FIXTURE"
  [ "${#lines[@]}" -eq 2 ]
}

@test "restore refuses to assume an answer without a terminal" {
  two_backups
  hosts_run restore
  [ "$status" -eq 8 ]
  [[ $stderr == *'without a terminal'* ]]
  [[ $stderr == *'--yes'* ]]
}

@test "--dry-run shows the change and writes nothing" {
  two_backups
  printf '10.0.0.9 build\n' >>"$FIXTURE"
  local before
  before=$(cat "$FIXTURE")

  hosts_run --dry-run restore
  [ "$status" -eq 0 ]
  [[ $output == *'-10.0.0.9 build'* ]]
  [ "$(cat "$FIXTURE")" = "$before" ]
}

@test "the content that was there is kept before it is replaced" {
  two_backups
  printf '10.0.0.9 build\n' >>"$FIXTURE"

  hosts_run --yes restore
  [ "$status" -eq 0 ]

  # Three backups now: the two taken above and the state just replaced.
  hosts_run backup ls
  [ "${#lines[@]}" -eq 3 ]

  # And so the restore can itself be undone.
  hosts_run --yes restore 1
  [ "$status" -eq 0 ]
  run cat "$FIXTURE"
  [ "${lines[3]}" = '10.0.0.9 build' ]
}

@test "--no-backup skips keeping the content that is replaced" {
  two_backups
  printf '10.0.0.9 build\n' >>"$FIXTURE"

  hosts_run --yes --no-backup restore
  [ "$status" -eq 0 ]
  [[ $stderr == *'without a backup'* ]]

  hosts_run backup ls
  [ "${#lines[@]}" -eq 2 ]
}

@test "a backup taken from another file is never written over this one" {
  # The check the whole store rests on: a backup made with --file from a
  # scratch file must not end up over /etc/hosts.
  two_backups
  local meta
  meta=$(newest_meta)
  sed -i "s|^target=.*|target=/etc/hosts|" "$meta"

  hosts_run --yes restore
  [ "$status" -eq 7 ]
  [[ $stderr == *'was taken from /etc/hosts'* ]]
}

@test "a backup that fails its own checksum is refused" {
  two_backups
  printf 'tampered\n' >>"$(newest_copy)"

  hosts_run --yes restore
  [ "$status" -eq 7 ]
  [[ $stderr == *'does not match its own checksum'* ]]
}

@test "a refused restore leaves the file exactly as it was" {
  two_backups
  printf '10.0.0.9 build\n' >>"$FIXTURE"
  local before
  before=$(cat "$FIXTURE")

  printf 'tampered\n' >>"$(newest_copy)"
  hosts_run --yes restore
  [ "$status" -eq 7 ]
  [ "$(cat "$FIXTURE")" = "$before" ]
}

@test "an index that is not there exits 5" {
  two_backups
  hosts_run --yes restore 9
  [ "$status" -eq 5 ]
  [[ $stderr == *'no backup number 9'* ]]
}

@test "an identifier that is not there exits 5" {
  two_backups
  hosts_run --yes restore 20200101T000000.000Z
  [ "$status" -eq 5 ]
}

@test "restoring with no backup at all exits 5" {
  make_fixture <<'EOF'
127.0.0.1 localhost
EOF
  hosts_run --yes restore
  [ "$status" -eq 5 ]
  [[ $stderr == *'no backup'* ]]
}

@test "restore keeps the permissions the file has now" {
  two_backups
  chmod 0640 "$FIXTURE"
  hosts_run --yes restore 2
  [ "$status" -eq 0 ]
  run stat -c '%a' "$FIXTURE"
  [ "$output" = '640' ]
}

@test "restore leaves no temporary file behind" {
  two_backups
  hosts_run --yes restore 2
  [ "$status" -eq 0 ]

  shopt -s nullglob
  local -a leftovers=("$BATS_TEST_TMPDIR"/.hosts.*)
  shopt -u nullglob

  local path
  for path in "${leftovers[@]}"; do
    [[ $path == *.lock ]]
  done
}

@test "restore accepts at most one backup" {
  two_backups
  hosts_run --yes restore 1 2
  [ "$status" -eq 2 ]
}
