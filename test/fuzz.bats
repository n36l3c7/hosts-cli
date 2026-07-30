#!/usr/bin/env bats
#
# The parser against input it was not written for.
#
# The parser is written by hand and reads a file the machine depends on, so
# what matters is not that it understands nonsense but that nonsense cannot
# make it crash, hang, or quietly change the file. Three invariants are
# checked, and the third is the strongest:
#
#   check    never crashes and never returns a code outside its contract
#   ls, get  never crash, whatever is in the file
#   export   gives back exactly the bytes that were read
#
# The generator is seeded so that a failure can be reproduced. The seed is
# printed when something goes wrong.

load helper

readonly FUZZ_SEED=20260727
readonly FUZZ_LINES=400
readonly FUZZ_TIMEOUT=30

# Fragments chosen to sit on the edges of what the parser distinguishes:
# comments and disabled entries, addresses that nearly parse, names that
# nearly conform, whitespace where it is significant, and bytes that have no
# business being in a text file at all.
fuzz_fragments() {
  cat <<'EOF'
127.0.0.1 localhost
::1 localhost
0.0.0.0	ads.example.com
10.0.0.5    staging   staging.local	# a comment
# 10.0.0.5 disabled
#10.0.0.5 disabled-tight
## 10.0.0.5 doubly
# a plain comment
# 10.0.0.5 is the old address of the staging box
203.0.113.7
999.1.1.1 bogus
010.0.0.1 leading-zero
1.2.3.4. trailing-dot-address
::ffff:1.2.3.4 mapped
fe80::1%eth0 zoned
1:2:3:4:5:6:7:8:9 too-many-groups
:::: colons
10.0.0.1 -leading-hyphen
10.0.0.1 trailing-hyphen-
10.0.0.1 under_score
10.0.0.1 example.com.
10.0.0.1 a..b
10.0.0.1 UPPER.Case
10.0.0.1 caffè
10.0.0.1 name#hash
10.0.0.1 name	# tab before comment
	10.0.0.1	indented
#
###
 #
10.0.0.1
10.0.0.1 one two three four five six seven
EOF
  # A very long line, a line of only whitespace, and control bytes.
  printf '10.0.0.1 %s\n' "$(printf 'a%.0s' {1..300})"
  printf '10.0.0.1 %s\n' "$(printf 'x.%.0s' {1..80})y"
  printf '   \t  \n'
  printf '10.0.0.1\tcarriage\r\n'
  printf '10.0.0.1\tvertical\vtab\n'
  printf '10.0.0.1\tescape\033[0m\n'
  printf '\001\002\003\n'
}

# Build a file of FUZZ_LINES lines by drawing fragments with a fixed seed.
make_fuzz_file() {
  local -a pool=()
  mapfile -t pool < <(fuzz_fragments)

  RANDOM=$FUZZ_SEED
  local -i i
  : >"$FIXTURE"
  for ((i = 0; i < FUZZ_LINES; i++)); do
    printf '%s\n' "${pool[RANDOM % ${#pool[@]}]}" >>"$FIXTURE"
  done
}

report() {
  printf 'seed %s, %s lines: %s\n' "$FUZZ_SEED" "$FUZZ_LINES" "$1" >&2
  printf 'the file is kept at %s\n' "$FIXTURE" >&2
}

@test "check survives a file of hostile lines" {
  make_fuzz_file

  run --separate-stderr timeout "$FUZZ_TIMEOUT" \
    "$HOSTS_BIN" --file "$FIXTURE" check

  if [ "$status" -eq 124 ]; then
    report 'check did not finish'
    return 1
  fi
  # 0 when nothing is wrong, 4 when something is. Nothing else is in contract.
  if [ "$status" -ne 0 ] && [ "$status" -ne 4 ]; then
    report "check returned $status, which is outside its contract"
    return 1
  fi
}

@test "check --json survives it too, and says how many it found" {
  make_fuzz_file

  run --separate-stderr timeout "$FUZZ_TIMEOUT" \
    "$HOSTS_BIN" --file "$FIXTURE" --json check
  if [ "$status" -ne 0 ] && [ "$status" -ne 4 ]; then
    report "check --json returned $status"
    return 1
  fi
  [[ $output == '{'* ]]
  [[ $output == *'"summary": { "errors": '* ]]
}

@test "the reading commands never crash on it" {
  make_fuzz_file

  local -a invocations=(
    'ls'
    'ls --all'
    'ls --blocked'
    'search 10.0.0'
    'get localhost'
    'get nowhere'
    'export'
  )

  local invocation
  for invocation in "${invocations[@]}"; do
    # shellcheck disable=SC2086
    run --separate-stderr timeout "$FUZZ_TIMEOUT" \
      "$HOSTS_BIN" --file "$FIXTURE" $invocation
    if [ "$status" -eq 124 ]; then
      report "$invocation did not finish"
      return 1
    fi
    # 0, or 5 for a name that is not there. Nothing else.
    if [ "$status" -ne 0 ] && [ "$status" -ne 5 ]; then
      report "$invocation returned $status"
      return 1
    fi
  done
}

@test "export gives back exactly the bytes that were read" {
  # The strongest of the three: if the round trip holds on arbitrary input,
  # the model keeps everything the file contains, and a later rewrite cannot
  # invent or drop a byte.
  make_fuzz_file

  run --separate-stderr bash -c \
    "timeout $FUZZ_TIMEOUT '$HOSTS_BIN' --file '$FIXTURE' export | cmp - '$FIXTURE'"
  if [ "$status" -ne 0 ]; then
    report "export did not reproduce the file: $output"
    return 1
  fi
}

@test "the round trip holds without a final newline as well" {
  make_fuzz_file
  # Take the newline off the end.
  printf '%s' "$(cat "$FIXTURE")" >"$FIXTURE.trimmed"
  mv -f "$FIXTURE.trimmed" "$FIXTURE"

  run --separate-stderr bash -c \
    "timeout $FUZZ_TIMEOUT '$HOSTS_BIN' --file '$FIXTURE' export | cmp - '$FIXTURE'"
  if [ "$status" -ne 0 ]; then
    report "export did not reproduce the file: $output"
    return 1
  fi
}

@test "a change to a hostile file leaves every other line untouched" {
  make_fuzz_file
  cp "$FIXTURE" "$BATS_TEST_TMPDIR/before"

  run --separate-stderr timeout "$FUZZ_TIMEOUT" \
    "$HOSTS_BIN" --file "$FIXTURE" --yes --no-backup add 198.51.100.9 fuzz-added
  if [ "$status" -ne 0 ]; then
    report "add returned $status"
    return 1
  fi

  # Everything but the appended line has to be byte for byte what it was.
  run --separate-stderr bash -c \
    "head -n -1 '$FIXTURE' | cmp - '$BATS_TEST_TMPDIR/before'"
  if [ "$status" -ne 0 ]; then
    report "a line nobody asked to change was changed: $output"
    return 1
  fi
}

@test "every line of the pool is reproduced exactly on its own" {
  # Narrower than the mixed file, and it says which fragment is at fault
  # rather than leaving four hundred lines to bisect.
  local -a pool=()
  mapfile -t pool < <(fuzz_fragments)

  local line
  for line in "${pool[@]}"; do
    printf '%s\n' "$line" >"$FIXTURE"
    run --separate-stderr bash -c \
      "'$HOSTS_BIN' --file '$FIXTURE' export | cmp - '$FIXTURE'"
    if [ "$status" -ne 0 ]; then
      printf 'this line does not survive the round trip: %q\n' "$line" >&2
      return 1
    fi
  done
}
