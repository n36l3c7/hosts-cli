# shellcheck shell=bash
#
# hosts check - lint the file.
#
# Severity follows one principle: an error is something the resolver will get
# wrong or silently ignore, a warning is something that is untidy or merely
# suspect. check has to be usable in continuous integration against files it
# did not write, so anything that has a legitimate reading stays a warning.

declare -a _ck_rule=()
declare -a _ck_severity=()
declare -a _ck_line=()
declare -a _ck_related=()
declare -a _ck_subject=()
declare -a _ck_message=()

# Record a finding. A line of 0 means the finding is about the file as a
# whole; related is a space separated list of other line numbers.
check_add() {
  _ck_rule+=("$1")
  _ck_severity+=("$2")
  _ck_line+=("$3")
  _ck_related+=("$4")
  _ck_subject+=("$5")
  _ck_message+=("$6")
}

# Walk the file once, forwards. Every cross line rule only ever refers to an
# earlier line, so a single forward pass emits findings already ordered by
# line and nothing has to be sorted afterwards.
_check_scan() {
  local -A first_seen=() seen_names=()
  local -a earlier=()
  local name lname key
  local -i index other has_loopback4=0 has_loopback6=0
  local -i reported_duplicate reported_conflict

  for ((index = 0; index < _hf_count; index++)); do
    if [[ ${_hf_raw[index]} == *[$'\001'-$'\010'$'\013'-$'\037']* ]]; then
      check_add 'control-character' 'error' "$((index + 1))" '' '' \
        'the line contains a control character'
    fi

    case ${_hf_kind[index]} in
      invalid)
        if [[ ${_hf_reason[index]} == 'bad-address' ]]; then
          split_on_whitespace "${_hf_raw[index]}"
          name=${FIELDS[0]:-}
          check_add 'invalid-ip' 'error' "$((index + 1))" '' "$name" \
            "not a valid IPv4 or IPv6 address: $name"
        else
          check_add 'invalid-line' 'error' "$((index + 1))" '' '' \
            'not an address followed by at least one hostname'
        fi
        continue
        ;;
      entry) ;;
      *)
        continue
        ;;
    esac

    # Name validity is judged on every entry, active or not: a disabled entry
    # carries the same defect the day it is switched back on.
    record_names "$index"
    for name in "${RECORD_NAMES[@]}"; do
      if is_valid_hostname "$name"; then
        continue
      fi
      if is_lenient_hostname "$name"; then
        check_add 'nonstandard-hostname' 'warning' "$((index + 1))" '' "$name" \
          "hostname is outside RFC 1123: $name"
      else
        check_add 'invalid-hostname' 'error' "$((index + 1))" '' "$name" \
          "not a valid hostname: $name"
      fi
    done

    # Cross line rules only look at active entries: a commented out entry
    # takes no part in name resolution, so it can neither duplicate nor
    # conflict with anything.
    ((_hf_enabled[index])) || continue

    # Nor do they look inside the block section. Thousands of near identical
    # names written by a script would produce nothing but noise; the per line
    # rules above still apply to them.
    ((!_hf_in_block[index])) || continue

    for name in "${RECORD_NAMES[@]}"; do
      if [[ ${name,,} == 'localhost' ]]; then
        [[ ${_hf_ip[index]} != '127.0.0.1' ]] || has_loopback4=1
        [[ ${_hf_ip[index]} != '::1' ]] || has_loopback6=1
      fi
    done

    key="${_hf_ip[index]} ${_hf_names[index],,}"
    if [[ -n ${first_seen[$key]:-} ]]; then
      other=${first_seen[$key]}
      local canonical
      record_canonical "$index" canonical
      check_add 'duplicate-entry' 'error' "$((index + 1))" "$((other + 1))" \
        "$canonical" "identical to the entry on line $((other + 1))"
      continue
    fi
    first_seen[$key]=$index

    # At most one finding of each kind per line: a line that repeats several
    # names of an earlier one is a single mistake, not one per name.
    reported_duplicate=0
    reported_conflict=0

    for name in "${RECORD_NAMES[@]}"; do
      lname=${name,,}
      if [[ -n ${seen_names[$lname]:-} ]]; then
        split_on_whitespace "${seen_names[$lname]}"
        earlier=("${FIELDS[@]}")
        for other in "${earlier[@]}"; do
          if [[ ${_hf_ip[index]} == "${_hf_ip[other]}" ]]; then
            if ((!reported_duplicate)); then
              reported_duplicate=1
              check_add 'duplicate-name' 'warning' "$((index + 1))" \
                "$((other + 1))" "$name" \
                "$name already points at ${_hf_ip[index]} on line $((other + 1))"
            fi
            break
          fi
          if [[ ${_hf_family[index]} == "${_hf_family[other]}" ]]; then
            if ((!reported_conflict)); then
              reported_conflict=1
              check_add 'conflicting-ip' 'warning' "$((index + 1))" \
                "$((other + 1))" "$name" \
                "$name also points at ${_hf_ip[other]} on line $((other + 1))"
            fi
            break
          fi
        done
      fi
      seen_names[$lname]="${seen_names[$lname]:-}${seen_names[$lname]:+ }$index"
    done
  done

  if ((!has_loopback4)); then
    check_add 'missing-loopback' 'warning' 0 '' 'localhost' \
      'no active entry maps 127.0.0.1 to localhost'
  fi
  if ((!has_loopback6)); then
    check_add 'missing-loopback6' 'warning' 0 '' 'localhost' \
      'no active entry maps ::1 to localhost'
  fi
  if ((_hf_count > 0 && !_hf_trailing_newline)); then
    check_add 'missing-trailing-newline' 'warning' 0 '' '' \
      'the file does not end with a newline'
  fi
}

# Report the findings in the format compilers use, so that the error parser of
# an editor can consume them directly.
_check_report_text() {
  local -i i

  for ((i = 0; i < ${#_ck_rule[@]}; i++)); do
    if ((_ck_line[i] > 0)); then
      printf '%s:%d: %s: %s: %s\n' \
        "$_hf_path" "${_ck_line[i]}" "${_ck_severity[i]}" \
        "${_ck_rule[i]}" "${_ck_message[i]}"
    else
      printf '%s: %s: %s: %s\n' \
        "$_hf_path" "${_ck_severity[i]}" "${_ck_rule[i]}" "${_ck_message[i]}"
    fi
  done
}

_check_report_json() {
  local -i errors=$1 warnings=$2
  local -i i
  local sep line related subject
  local -a related_lines=()

  json_literal "$_hf_path"
  printf '{\n'
  printf '  "version": %d,\n' "$JSON_SCHEMA_VERSION"
  printf '  "file": %s,\n' "$JSON_LITERAL"
  printf '  "summary": { "errors": %d, "warnings": %d },\n' "$errors" "$warnings"
  printf '  "findings": ['

  sep=$'\n'
  for ((i = 0; i < ${#_ck_rule[@]}; i++)); do
    printf '%s' "$sep"
    sep=$',\n'

    if ((_ck_line[i] > 0)); then
      line=${_ck_line[i]}
    else
      line='null'
    fi

    split_on_whitespace "${_ck_related[i]}"
    related_lines=("${FIELDS[@]}")
    related="[${related_lines[*]:-}]"
    related=${related// /, }

    if [[ -n ${_ck_subject[i]} ]]; then
      json_literal "${_ck_subject[i]}"
      subject=$JSON_LITERAL
    else
      subject='null'
    fi

    printf '    {\n'
    json_literal "${_ck_rule[i]}"
    printf '      "rule": %s,\n' "$JSON_LITERAL"
    json_literal "${_ck_severity[i]}"
    printf '      "severity": %s,\n' "$JSON_LITERAL"
    printf '      "line": %s,\n' "$line"
    printf '      "related": %s,\n' "$related"
    printf '      "subject": %s,\n' "$subject"
    json_literal "${_ck_message[i]}"
    printf '      "message": %s\n' "$JSON_LITERAL"
    printf '    }'
  done

  if ((${#_ck_rule[@]} > 0)); then
    printf '\n  ]\n'
  else
    printf ']\n'
  fi
  printf '}\n'
}

cmd_check() {
  local -i strict=0 i errors=0 warnings=0

  while (($#)); do
    case $1 in
      -h | --help)
        help_check
        return "$EX_OK"
        ;;
      --strict)
        strict=1
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        die_usage 'check ' "check takes no argument: $1"
        ;;
    esac
  done

  if (($# > 0)); then
    die_usage 'check ' "check takes no argument: $1"
  fi

  hostsfile_load "$OPT_FILE"
  _check_scan

  for ((i = 0; i < ${#_ck_rule[@]}; i++)); do
    if [[ ${_ck_severity[i]} == 'error' ]]; then
      errors+=1
    else
      warnings+=1
    fi
  done

  if ((OPT_JSON)); then
    _check_report_json "$errors" "$warnings"
  else
    _check_report_text
  fi

  info "$_hf_count lines, $errors errors, $warnings warnings"

  if ((errors > 0)); then
    return "$EX_VALIDATION"
  fi
  if ((strict && warnings > 0)); then
    return "$EX_VALIDATION"
  fi

  return "$EX_OK"
}
