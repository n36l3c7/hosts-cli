# shellcheck shell=bash
#
# Predicates used to select records.

declare -a SELECTED=()

# Succeed when any name of a record matches a shell glob. Matching ignores
# case, because hostname comparison is case insensitive.
record_matches_name_pattern() {
  local -i index=$1
  local pattern=${2,,} name

  record_names "$index"
  for name in "${RECORD_NAMES[@]}"; do
    # The pattern is deliberately left unquoted: it is a glob, not a literal.
    # shellcheck disable=SC2053
    if [[ ${name,,} == $pattern ]]; then
      return 0
    fi
  done

  return 1
}

# Succeed when the address, any name or the comment of a record contains the
# given text. Matching ignores case and is on substrings, which is what a
# search is expected to do.
record_matches_text() {
  local -i index=$1
  local needle=${2,,}

  if [[ ${_hf_ip[index],,} == *"$needle"* ]]; then
    return 0
  fi
  if [[ ${_hf_names[index],,} == *"$needle"* ]]; then
    return 0
  fi
  if ((_hf_has_comment[index])) && [[ ${_hf_comment[index],,} == *"$needle"* ]]; then
    return 0
  fi

  return 1
}

# Store in SELECTED the indexes of the active records carrying a name.
records_for_name() {
  local name=${1,,}
  local -a candidates=()
  local -i index

  SELECTED=()
  split_on_whitespace "${_hf_by_name[$name]:-}"
  candidates=("${FIELDS[@]}")

  for index in "${candidates[@]}"; do
    if ((_hf_enabled[index])); then
      SELECTED+=("$index")
    fi
  done
}
