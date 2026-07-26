# shellcheck shell=bash
#
# Output helpers. Diagnostics always go to stderr so that stdout stays clean
# for data that callers may want to pipe.

# Print a diagnostic message to stderr, prefixed with the program name.
err() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
}

# Print a diagnostic message and exit with the given code.
die() {
  local code=$1
  shift
  err "$*"
  exit "$code"
}
