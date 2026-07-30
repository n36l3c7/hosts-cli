#!/usr/bin/env bats
#
# The promise the whole program rests on, put under a process that dies.
#
# Everything else here has been reasoned about and documented: a change leaves
# the file holding either the whole of the old content or the whole of the new
# one, never a mixture, and concurrent writers cannot lose each other's work.
# These tests stop taking that on trust.

load helper

# The content the fixture starts from, and its checksum.
before_content() {
  printf '127.0.0.1\tlocalhost\n::1\t\tlocalhost\n10.0.0.5\tstaging\n'
}

reset_fixture() {
  before_content >"$FIXTURE"
}

sha_of() {
  sha256sum <"$1" | cut -d' ' -f1
}

@test "a write killed outright leaves the file whole" {
  # The kill lands at a different point on every pass, so between them the
  # window from creating the temporary file to renaming it over the target is
  # covered. Whatever the moment, the file has to be one of the two states.
  reset_fixture
  local sha_before
  sha_before=$(sha_of "$FIXTURE")

  # What the finished write produces, worked out once on a copy.
  local expected="$BATS_TEST_TMPDIR/expected"
  cp "$FIXTURE" "$expected"
  run --separate-stderr "$HOSTS_BIN" --file "$expected" --yes --no-backup \
    add 10.0.0.9 build
  [ "$status" -eq 0 ]
  local sha_after
  sha_after=$(sha_of "$expected")
  [ "$sha_before" != "$sha_after" ]

  local delay actual
  for delay in 0 0.002 0.004 0.006 0.008 0.010 0.013 0.016 0.020 0.025 0.030; do
    reset_fixture
    "$HOSTS_BIN" --file "$FIXTURE" --yes --no-backup add 10.0.0.9 build \
      >/dev/null 2>&1 &
    local victim=$!
    sleep "$delay"
    kill -KILL "$victim" 2>/dev/null || true
    wait "$victim" 2>/dev/null || true

    actual=$(sha_of "$FIXTURE")
    if [ "$actual" != "$sha_before" ] && [ "$actual" != "$sha_after" ]; then
      printf 'killed after %ss left the file in neither state\n' "$delay" >&2
      cat "$FIXTURE" >&2
      return 1
    fi
  done
}

@test "a write asked to stop cleanly leaves no temporary file behind" {
  # SIGKILL cannot be caught, so a leftover temporary file is unavoidable
  # there. SIGTERM can be, and the trap has to do its work.
  reset_fixture
  local sha_before
  sha_before=$(sha_of "$FIXTURE")

  local delay
  for delay in 0.002 0.006 0.012; do
    reset_fixture
    "$HOSTS_BIN" --file "$FIXTURE" --yes --no-backup add 10.0.0.9 build \
      >/dev/null 2>&1 &
    local victim=$!
    sleep "$delay"
    kill -TERM "$victim" 2>/dev/null || true
    wait "$victim" 2>/dev/null || true
  done

  shopt -s nullglob
  local -a leftovers=("$BATS_TEST_TMPDIR"/.hosts.*)
  shopt -u nullglob

  local path
  for path in "${leftovers[@]}"; do
    # The lock file is meant to stay; a working file is not.
    [[ $path == *.lock ]] || {
      printf 'a working file was left behind: %s\n' "$path" >&2
      return 1
    }
  done
}

@test "the file always parses, whenever a write is interrupted" {
  reset_fixture

  local delay
  for delay in 0 0.003 0.007 0.011 0.015 0.020; do
    reset_fixture
    "$HOSTS_BIN" --file "$FIXTURE" --yes --no-backup add 10.0.0.9 build \
      >/dev/null 2>&1 &
    local victim=$!
    sleep "$delay"
    kill -KILL "$victim" 2>/dev/null || true
    wait "$victim" 2>/dev/null || true

    # An interrupted write must never produce a line the parser rejects.
    run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" check
    if [[ $output == *invalid-line* || $output == *invalid-ip* ]]; then
      printf 'killed after %ss left a line that does not parse\n' "$delay" >&2
      cat "$FIXTURE" >&2
      return 1
    fi
  done
}

@test "two writers at once do not lose each other's work" {
  # The file is made large enough that reading it takes long enough for both
  # processes to be inside that read at the same time. That is what turns a
  # race that might happen into one that does, so the test says something
  # definite either way.
  {
    before_content
    local i
    for ((i = 0; i < 3000; i++)); do
      printf '0.0.0.0\tads-%d.example.com\n' "$i"
    done
  } >"$FIXTURE"

  "$HOSTS_BIN" --file "$FIXTURE" --yes --no-backup add 10.0.0.7 alpha \
    >/dev/null 2>&1 &
  local first=$!
  "$HOSTS_BIN" --file "$FIXTURE" --yes --no-backup add 10.0.0.8 beta \
    >/dev/null 2>&1 &
  local second=$!

  wait "$first"
  wait "$second"

  # Whoever wrote second must have seen what the first one wrote, which only
  # holds if the lock covers the read as well as the write.
  run grep -c 'alpha' "$FIXTURE"
  local has_alpha=$output
  run grep -c 'beta' "$FIXTURE"
  local has_beta=$output

  if [ "$has_alpha" != '1' ] || [ "$has_beta" != '1' ]; then
    printf 'alpha=%s beta=%s: one writer overwrote the other\n' \
      "$has_alpha" "$has_beta" >&2
    return 1
  fi
}

@test "a concurrent write never produces a file that does not parse" {
  reset_fixture

  local i
  for ((i = 0; i < 5; i++)); do
    "$HOSTS_BIN" --file "$FIXTURE" --yes --no-backup add "10.1.$i.1" "one-$i" \
      >/dev/null 2>&1 &
    "$HOSTS_BIN" --file "$FIXTURE" --yes --no-backup add "10.2.$i.1" "two-$i" \
      >/dev/null 2>&1 &
    wait
  done

  run --separate-stderr "$HOSTS_BIN" --file "$FIXTURE" check
  [[ $output != *invalid-line* ]]
  [[ $output != *invalid-ip* ]]
  [[ $output != *control-character* ]]
}
