# shellcheck shell=bash
#
# Predicates used to select records.


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

# Store the indexes of the active records carrying a name.
records_for_name() {
  local _name=${1,,}
  local -n _out_records=$2
  local -a _candidates=()
  local -i _index

  _out_records=()
  split_on_whitespace "${_hf_by_name[$_name]:-}"
  _candidates=("${FIELDS[@]}")

  for _index in "${_candidates[@]}"; do
    if ((_hf_enabled[_index])); then
      _out_records+=("$_index")
    fi
  done
}
