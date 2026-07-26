# shellcheck shell=bash
#
# Small helpers shared by the rest of the program.
#
# These set a variable instead of printing: a command substitution forks, and
# they run several times per line on files with tens of thousands of them.

TRIMMED=''
declare -a FIELDS=()

# Strip leading and trailing whitespace, storing the result in TRIMMED.
trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  TRIMMED=$s
}

# Split a string into the FIELDS array on the given separator characters.
#
# This is word splitting rather than "read -ra ... <<<", because a here-string
# is not a builtin: bash writes it to a temporary file first, which on a file
# of fifty thousand lines costs more than everything else put together.
# Pathname expansion is off for the whole program, so a stray asterisk in the
# input cannot turn into a list of filenames here.
split_fields() {
  local IFS=$1
  # shellcheck disable=SC2206 # splitting is exactly the point here
  FIELDS=($2)
}

# Split on whitespace, the separator of a hosts file.
split_on_whitespace() {
  split_fields $' \t\n' "$1"
}

# Expand a pathname pattern into the FIELDS array, empty when nothing matches.
#
# Pathname expansion is off program wide, so it is turned on for this one
# expansion and turned straight back off. This runs once per command, not once
# per line, so the cost that made the same guard unacceptable inside
# split_fields does not arise here.
expand_glob() {
  local nullglob_was_set=1

  shopt -q nullglob || nullglob_was_set=0
  shopt -s nullglob
  set +f
  # shellcheck disable=SC2206 # expansion is the point here
  FIELDS=($1)
  set -f
  if ((!nullglob_was_set)); then
    shopt -u nullglob
  fi

  return 0
}
