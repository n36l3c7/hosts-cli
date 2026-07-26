#!/usr/bin/env bats
#
# The atomic write engine.
#
# The property being defended is that the file ends up holding either the
# whole of the old content or the whole of the new one, and that nothing at
# all is written when the result cannot be trusted.

load helper

# Drive the engine directly, which is the only way to reach the failure paths
# that the commands are built to avoid.
in_engine() {
  run --separate-stderr bash -c "source '$HOSTS_BIN'
OPT_FORCE=0
OPT_DRY_RUN=0
$1"
}

@test "a committed write replaces the content" {
  printf 'old\n' >"$FIXTURE"
  in_engine "
    atomic_begin '$FIXTURE'
    printf 'new\n' >\"\$ATOMIC_TMP\"
    file_sha256 \"\$ATOMIC_TMP\"
    atomic_commit \"\$FILE_SHA256\"
  "
  [ "$status" -eq 0 ]
  [ "$(cat "$FIXTURE")" = 'new' ]
}

@test "a write whose content does not match what was intended is abandoned" {
  printf 'old\n' >"$FIXTURE"
  in_engine "
    atomic_begin '$FIXTURE'
    printf 'truncated' >\"\$ATOMIC_TMP\"
    atomic_commit 0000000000000000000000000000000000000000000000000000000000000000
  "
  [ "$status" -eq 7 ]
  [[ $stderr == *'does not match what was intended'* ]]
  [ "$(cat "$FIXTURE")" = 'old' ]
}

@test "an abandoned write leaves no temporary file behind" {
  printf 'old\n' >"$FIXTURE"
  in_engine "
    atomic_begin '$FIXTURE'
    printf 'truncated' >\"\$ATOMIC_TMP\"
    atomic_commit 0000000000000000000000000000000000000000000000000000000000000000
  " || true

  shopt -s nullglob
  local -a leftovers=("$BATS_TEST_TMPDIR"/.hosts.*)
  shopt -u nullglob
  [ "${#leftovers[@]}" -eq 0 ]
}

@test "the temporary file is removed when the process is interrupted" {
  printf 'old\n' >"$FIXTURE"
  in_engine "
    atomic_begin '$FIXTURE'
    printf 'half' >\"\$ATOMIC_TMP\"
    exit 1
  " || true

  shopt -s nullglob
  local -a leftovers=("$BATS_TEST_TMPDIR"/.hosts.*)
  shopt -u nullglob
  [ "${#leftovers[@]}" -eq 0 ]
  [ "$(cat "$FIXTURE")" = 'old' ]
}

@test "the temporary file sits beside the target, not in /tmp" {
  # Only then is the final move a rename inside one filesystem, which is the
  # operation the kernel makes atomic; across filesystems it becomes a copy,
  # and a copy can be interrupted halfway.
  printf 'old\n' >"$FIXTURE"
  in_engine "
    atomic_begin '$FIXTURE'
    printf '%s\n' \"\$ATOMIC_TMP\"
    atomic_abort
  "
  [ "$status" -eq 0 ]
  [[ $output == "$BATS_TEST_TMPDIR/"* ]]
}

@test "the permissions of the target are preserved" {
  printf 'old\n' >"$FIXTURE"
  chmod 0600 "$FIXTURE"
  in_engine "
    atomic_begin '$FIXTURE'
    printf 'new\n' >\"\$ATOMIC_TMP\"
    file_sha256 \"\$ATOMIC_TMP\"
    atomic_commit \"\$FILE_SHA256\"
  "
  [ "$status" -eq 0 ]
  run stat -c '%a' "$FIXTURE"
  [ "$output" = '600' ]
}

@test "a new file is created with sensible permissions" {
  local target="$BATS_TEST_TMPDIR/fresh"
  in_engine "
    atomic_begin '$target'
    printf 'new\n' >\"\$ATOMIC_TMP\"
    file_sha256 \"\$ATOMIC_TMP\"
    atomic_commit \"\$FILE_SHA256\"
  "
  [ "$status" -eq 0 ]
  run stat -c '%a' "$target"
  [ "$output" = '644' ]
}

@test "a directory that cannot be written to fails with the permission code" {
  if [ "$(id -u)" -eq 0 ]; then
    skip 'running as root, which can write anything'
  fi
  mkdir -p "$BATS_TEST_TMPDIR/locked"
  printf 'old\n' >"$BATS_TEST_TMPDIR/locked/hosts"
  chmod 500 "$BATS_TEST_TMPDIR/locked"

  in_engine "atomic_begin '$BATS_TEST_TMPDIR/locked/hosts'"
  local seen=$status
  chmod 755 "$BATS_TEST_TMPDIR/locked"

  [ "$seen" -eq 3 ]
}

@test "a symbolic link is followed, not replaced" {
  # Renaming onto the link would turn it into a regular file and quietly undo
  # an arrangement the machine may depend on.
  local real="$BATS_TEST_TMPDIR/real-hosts"
  local link="$BATS_TEST_TMPDIR/link-hosts"
  printf '127.0.0.1 localhost\n' >"$real"
  ln -s "$real" "$link"

  run --separate-stderr "$HOSTS_BIN" --file "$link" backup
  [ "$status" -eq 0 ]
  printf '10.0.0.5 staging\n' >>"$real"
  run --separate-stderr "$HOSTS_BIN" --file "$link" --yes restore
  [ "$status" -eq 0 ]

  [ -L "$link" ]
  [ "$(cat "$real")" = '127.0.0.1 localhost' ]
}

@test "an extended ACL is refused, and --force goes ahead" {
  if ! command -v setfacl >/dev/null 2>&1; then
    skip 'setfacl is not installed'
  fi
  if [ "$(id -u)" -eq 0 ]; then
    skip 'running as root'
  fi

  printf 'old\n' >"$FIXTURE"
  if ! setfacl -m u:"$(id -un)":rw "$FIXTURE" 2>/dev/null; then
    skip 'the filesystem does not carry ACLs'
  fi

  in_engine "atomic_begin '$FIXTURE'"
  [ "$status" -eq 6 ]
  [[ $stderr == *'extended ACL'* ]]

  in_engine "
    OPT_FORCE=1
    atomic_begin '$FIXTURE'
    atomic_abort
  "
  [ "$status" -eq 0 ]
}
