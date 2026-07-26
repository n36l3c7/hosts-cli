# shellcheck shell=bash
#
# Rendering of records, in text and in JSON.
#
# The text format has a fixed number of tab separated fields, the same on a
# terminal and in a pipe and the same whatever the options: field one is
# always the address, field two always the names. Nothing is aligned, coloured
# or paginated, so that the output stays usable from a script.

# Print one record as "address<TAB>names<TAB>state<TAB>comment".
record_text() {
  local -i index=$1
  local state comment=''

  if ((_hf_enabled[index])); then
    state='on'
  else
    state='off'
  fi

  if ((_hf_has_comment[index])); then
    trim "${_hf_comment[index]}"
    comment=$TRIMMED
  fi

  printf '%s\t%s\t%s\t%s\n' \
    "${_hf_ip[index]}" "${_hf_names[index]}" "$state" "$comment"
}

# Print the JSON object of one record, indented to sit inside an array.
record_json() {
  local -i index=$1
  local kind ip family canonical aliases comment raw enabled

  json_literal "${_hf_kind[index]}"
  kind=$JSON_LITERAL

  if ((_hf_enabled[index])); then
    enabled='true'
  else
    enabled='false'
  fi

  if [[ -n ${_hf_ip[index]} ]]; then
    json_literal "${_hf_ip[index]}"
    ip=$JSON_LITERAL
    json_literal "${_hf_family[index]}"
    family=$JSON_LITERAL
  else
    ip='null'
    family='null'
  fi

  record_names "$index"
  if ((${#RECORD_NAMES[@]} > 0)); then
    json_literal "${RECORD_NAMES[0]}"
    canonical=$JSON_LITERAL
    json_literal_array "${RECORD_NAMES[@]:1}"
    aliases=$JSON_LITERAL
  else
    canonical='null'
    aliases='[]'
  fi

  # The comment is reported without its surrounding whitespace, which is
  # noise; the raw field keeps the line exactly as it is in the file.
  trim "${_hf_comment[index]}"
  json_literal_or_null "${_hf_has_comment[index]}" "$TRIMMED"
  comment=$JSON_LITERAL

  json_literal "${_hf_raw[index]}"
  raw=$JSON_LITERAL

  printf '    {\n'
  printf '      "line": %d,\n' "$((index + 1))"
  printf '      "kind": %s,\n' "$kind"
  printf '      "enabled": %s,\n' "$enabled"
  printf '      "ip": %s,\n' "$ip"
  printf '      "family": %s,\n' "$family"
  printf '      "canonical": %s,\n' "$canonical"
  printf '      "aliases": %s,\n' "$aliases"
  printf '      "comment": %s,\n' "$comment"
  printf '      "raw": %s\n' "$raw"
  printf '    }'
}

# Print a JSON document whose entries array holds the given record indexes.
# Any extra key and value pairs are emitted before the array.
records_json_document() {
  local -a extra=()
  local key

  while (($# > 0)) && [[ $1 != '--' ]]; do
    extra+=("$1")
    shift
  done
  shift || true

  json_literal "$_hf_path"
  printf '{\n'
  printf '  "version": %d,\n' "$JSON_SCHEMA_VERSION"
  printf '  "file": %s,\n' "$JSON_LITERAL"
  for key in "${extra[@]}"; do
    printf '  %s,\n' "$key"
  done
  printf '  "entries": ['

  local sep=$'\n'
  local -i index
  for index in "$@"; do
    printf '%s' "$sep"
    record_json "$index"
    sep=$',\n'
  done

  if (($# > 0)); then
    printf '\n  ]\n'
  else
    printf ']\n'
  fi
  printf '}\n'
}
