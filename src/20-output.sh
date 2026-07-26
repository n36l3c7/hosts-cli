# shellcheck shell=bash
#
# Output helpers.
#
# Diagnostics always go to stderr, data always goes to stdout. The verbosity
# level only ever silences diagnostics: it never suppresses the data a command
# was asked to produce, so "hosts -q check" still prints its findings.

VERBOSITY=1 # 0 quiet, 1 normal, 2 verbose

# Print a diagnostic to stderr, prefixed with the program name. Always shown.
err() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
}

# Print a warning to stderr unless running quiet.
warn() {
  if ((VERBOSITY >= 1)); then
    printf '%s: warning: %s\n' "$PROGRAM_NAME" "$*" >&2
  fi
}

# Print progress information to stderr, only when running verbose.
info() {
  if ((VERBOSITY >= 2)); then
    printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  fi
}

# Print a diagnostic and exit with the given code.
die() {
  local code=$1
  shift
  err "$*"
  exit "$code"
}

# Ask the user to confirm something that cannot be undone easily.
#
# Without a terminal there is nobody to ask, so the operation is refused
# rather than assumed. The behaviour does depend on the environment, but only
# ever in the safe direction: --yes is how a script says it means it.
confirm() {
  local question=$1 reply

  if ((OPT_YES)); then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    die "$EX_ABORTED" \
      "$question: refusing to assume an answer without a terminal, pass --yes"
  fi

  printf '%s [y/N] ' "$question" >&2
  IFS= read -r reply || reply=''

  case ${reply,,} in
    y | yes) return 0 ;;
  esac

  die "$EX_ABORTED" 'aborted'
}

# Report a usage error and point at the relevant help.
die_usage() {
  local context=$1
  shift
  err "$*"
  err "run '$PROGRAM_NAME $context--help' for usage"
  exit "$EX_USAGE"
}
