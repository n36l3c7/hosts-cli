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
