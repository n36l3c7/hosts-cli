#!/usr/bin/env bats
#
# hosts profile.

load helper

standard_fixture() {
  {
    printf '127.0.0.1\tlocalhost\n'
    printf '::1\t\tlocalhost\n'
    printf '10.0.0.5\tstaging\n'
  } >"$FIXTURE"
}

@test "save keeps the file under a name" {
  standard_fixture
  hosts_run profile save work
  [ "$status" -eq 0 ]

  hosts_run profile ls
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ ${lines[0]} == 'work'$'\t'* ]]
}

@test "the copy is byte for byte identical to the file" {
  standard_fixture
  hosts_run profile save work
  [ "$status" -eq 0 ]

  shopt -s nullglob
  local -a copies=("$HOSTS_PROFILE_DIR"/*/work.bak)
  shopt -u nullglob

  [ "${#copies[@]}" -eq 1 ]
  run cmp -- "$FIXTURE" "${copies[0]}"
  [ "$status" -eq 0 ]
}

@test "load brings the state back" {
  standard_fixture
  hosts_run profile save work
  printf '10.0.0.9\tbuild\n' >>"$FIXTURE"

  hosts_run --yes profile load work
  [ "$status" -eq 0 ]

  run wc -l <"$FIXTURE"
  [ "$output" -eq 3 ]
  run grep -c 'build' "$FIXTURE"
  [ "$status" -ne 0 ]
}

@test "a load can be undone, because what it replaced was kept" {
  standard_fixture
  hosts_run profile save work
  printf '10.0.0.9\tbuild\n' >>"$FIXTURE"
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  hosts_run --yes profile load work
  [ "$status" -eq 0 ]

  hosts_run --yes restore
  [ "$status" -eq 0 ]
  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]
}

@test "profiles and backups are kept apart" {
  standard_fixture
  hosts_run profile save work
  [ "$status" -eq 0 ]

  # A saved profile is not history, so it does not show up as a backup.
  hosts_run backup ls
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a profile is never rotated away" {
  standard_fixture
  hosts_run profile save keep-me

  local i
  for i in 1 2 3; do
    printf '10.0.0.%d\thost%d\n' "$i" "$i" >>"$FIXTURE"
    HOSTS_KEEP_BACKUPS=1 run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" backup
    [ "$status" -eq 0 ]
  done

  hosts_run profile ls
  [ "${#lines[@]}" -eq 1 ]
  [[ ${lines[0]} == 'keep-me'$'\t'* ]]
}

@test "saving over a name that exists is refused" {
  standard_fixture
  hosts_run profile save work
  [ "$status" -eq 0 ]

  printf '10.0.0.9\tbuild\n' >>"$FIXTURE"
  hosts_run profile save work
  [ "$status" -eq 6 ]
  [[ $stderr == *'already exists'* ]]

  # And the profile still holds what it held.
  hosts_run --yes profile load work
  run wc -l <"$FIXTURE"
  [ "$output" -eq 3 ]
}

@test "--force replaces it" {
  standard_fixture
  hosts_run profile save work
  printf '10.0.0.9\tbuild\n' >>"$FIXTURE"

  hosts_run --force profile save work
  [ "$status" -eq 0 ]

  hosts_run --yes profile load work
  run wc -l <"$FIXTURE"
  [ "$output" -eq 4 ]
}

@test "a profile saved from another file is never loaded over this one" {
  standard_fixture
  hosts_run profile save work

  shopt -s nullglob
  local -a metas=("$HOSTS_PROFILE_DIR"/*/work.meta)
  shopt -u nullglob
  sed -i "s|^target=.*|target=/etc/hosts|" "${metas[0]}"

  hosts_run --yes profile load work
  [ "$status" -eq 7 ]
  [[ $stderr == *'saved from /etc/hosts'* ]]
}

@test "a profile that fails its own checksum is refused" {
  standard_fixture
  hosts_run profile save work

  shopt -s nullglob
  local -a copies=("$HOSTS_PROFILE_DIR"/*/work.bak)
  shopt -u nullglob
  printf 'tampered\n' >>"${copies[0]}"

  hosts_run --yes profile load work
  [ "$status" -eq 7 ]
  [[ $stderr == *'checksum'* ]]
}

@test "load asks first, and refuses to assume an answer without a terminal" {
  standard_fixture
  hosts_run profile save work
  printf '10.0.0.9\tbuild\n' >>"$FIXTURE"

  hosts_run profile load work
  [ "$status" -eq 8 ]
  [[ $stderr == *'without a terminal'* ]]
}

@test "rm asks first too" {
  standard_fixture
  hosts_run profile save work

  hosts_run profile rm work
  [ "$status" -eq 8 ]

  hosts_run profile ls
  [ "${#lines[@]}" -eq 1 ]
}

@test "rm deletes the profile" {
  standard_fixture
  hosts_run profile save work
  hosts_run --yes profile rm work
  [ "$status" -eq 0 ]

  hosts_run profile ls
  [ -z "$output" ]
}

@test "a name that is not there exits 5" {
  standard_fixture
  hosts_run --yes profile load nowhere
  [ "$status" -eq 5 ]
  hosts_run --yes profile rm nowhere
  [ "$status" -eq 5 ]
}

@test "a name that could escape the store is refused" {
  # The name becomes part of a filename, so this is safety, not tidiness.
  standard_fixture
  local name
  for name in '../escape' 'with/slash' '.hidden' 'sp ace' ''; do
    hosts_run --yes profile save "$name"
    [ "$status" -eq 4 ]
  done

  # A name starting with a hyphen is read as an option first, as it is for
  # every other command; past that it is refused like the rest.
  hosts_run --yes profile save -leading
  [ "$status" -eq 2 ]
  hosts_run --yes profile save -- -leading
  [ "$status" -eq 4 ]

  [ ! -e "$BATS_TEST_TMPDIR/escape.bak" ]
}

@test "a name longer than the limit is refused" {
  standard_fixture
  local long
  long=$(printf 'a%.0s' {1..65})
  hosts_run profile save "$long"
  [ "$status" -eq 4 ]
  [[ $stderr == *'longer than'* ]]
}

@test "two files get separate stores" {
  standard_fixture
  hosts_run profile save work

  local other="$BATS_TEST_TMPDIR/other"
  printf '10.0.0.1\tother\n' >"$other"
  run --separate-stderr "$HOSTS_BIN" --file "$other" profile ls
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "profile ls has three tab separated fields, in a stable order" {
  standard_fixture
  hosts_run profile save beta
  hosts_run profile save alpha

  hosts_run profile ls
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ ${lines[0]} == 'alpha'$'\t'* ]]
  [[ ${lines[1]} == 'beta'$'\t'* ]]

  local line
  for line in "${lines[@]}"; do
    [ "${line//[^$'\t']/}" = $'\t\t' ]
  done
}

@test "profile ls on an empty store produces no output and succeeds" {
  standard_fixture
  hosts_run profile ls
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "profile ls --json reports the store and every profile" {
  standard_fixture
  hosts_run profile save work
  hosts_run --json profile ls
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = '{' ]
  [ "${lines[1]}" = '  "version": 1,' ]
  [[ $output == *'"name": "work",'* ]]
  [[ $output == *'"sha256": "'* ]]
}

@test "profile ls --json on an empty store emits an empty array" {
  standard_fixture
  hosts_run --json profile ls
  [ "$status" -eq 0 ]
  [[ $output == *'"profiles": []'* ]]
}

@test "--dry-run writes nothing, for save, load and rm" {
  standard_fixture
  hosts_run --dry-run profile save work
  [ "$status" -eq 0 ]
  hosts_run profile ls
  [ -z "$output" ]

  hosts_run profile save work
  printf '10.0.0.9\tbuild\n' >>"$FIXTURE"
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  hosts_run --dry-run profile load work
  [ "$status" -eq 0 ]
  [[ $output == *'-10.0.0.9'* ]]
  run cmp "$FIXTURE" "$BATS_TEST_TMPDIR/before"
  [ "$status" -eq 0 ]

  hosts_run --dry-run profile rm work
  [ "$status" -eq 0 ]
  hosts_run profile ls
  [ "${#lines[@]}" -eq 1 ]
}

@test "saving needs no privilege on the file itself" {
  if [ "$(id -u)" -eq 0 ]; then
    skip 'running as root, which can write anything'
  fi
  standard_fixture
  chmod 0444 "$FIXTURE"
  hosts_run profile save work
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
  HOSTS_PROFILE_DIR="$BATS_TEST_TMPDIR/locked/store" \
    run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" profile save work
  chmod 755 "$BATS_TEST_TMPDIR/locked"
  [ "$status" -eq 3 ]
  [[ $stderr == *'HOSTS_PROFILE_DIR'* ]]
}

@test "profile needs a subcommand it knows" {
  standard_fixture
  hosts_run profile
  [ "$status" -eq 2 ]
  hosts_run profile nonsense
  [ "$status" -eq 2 ]
  hosts_run profile save
  [ "$status" -eq 2 ]
  hosts_run profile ls extra
  [ "$status" -eq 2 ]
}
