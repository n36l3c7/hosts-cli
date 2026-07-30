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
declare -a _ck_fixed=()

# Record a finding. A line of 0 means the finding is about the file as a
# whole; related is a space separated list of other line numbers.
check_add() {
  _ck_rule+=("$1")
  _ck_severity+=("$2")
  _ck_line+=("$3")
  _ck_related+=("$4")
  _ck_subject+=("$5")
  _ck_message+=("$6")
  _ck_fixed+=(0)
}

# Forget every finding, so that the file can be scanned again after being fixed.
_check_reset() {
  _ck_rule=()
  _ck_severity=()
  _ck_line=()
  _ck_related=()
  _ck_subject=()
  _ck_message=()
  _ck_fixed=()
}

# How many findings the fix pass dealt with.
_check_count_fixed() {
  local -n _out_count=$1
  local -i _i

  # Assigned arithmetically rather than with +=, which on a name the caller
  # supplied would concatenate unless that name happens to be an integer.
  _out_count=0
  for ((_i = 0; _i < ${#_ck_fixed[@]}; _i++)); do
    ((!_ck_fixed[_i])) || _out_count=$((_out_count + 1))
  done
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

# Which findings a machine is allowed to act on.
#
# The line is drawn at whether the finding forces its own fix. A duplicate
# entry has exactly one reading, and removing it changes nothing about what the
# file resolves. An address that does not parse has no reading at all: the fix
# would be to guess, and guessing at a resolver's configuration is the whole
# class of mistake this program exists to avoid. conflicting-ip is the one that
# tempts: two lines send a name to two addresses, and which of them is wanted
# is knowledge the file does not contain. control-character is left alone for a
# different reason - stripping bytes out of a line in silence would destroy the
# evidence of what happened to it.
_check_fixable() {
  case $1 in
    duplicate-entry | duplicate-name | missing-loopback | missing-loopback6 | \
      missing-trailing-newline)
      return 0
      ;;
  esac

  return 1
}

# Put a new entry where a reader would expect it: above the first entry the
# file already has, and at the end when it has none. A file whose entries are
# all inside a block section gets it after the section rather than within,
# since what is in there belongs to whatever wrote it.
_check_fix_insert_entry() {
  local text=$1
  local -i index

  for ((index = 0; index < _hf_count; index++)); do
    [[ ${_hf_kind[index]} == 'entry' ]] || continue
    ((!_hf_in_block[index])) || continue
    edit_insert_before "$index" "$text"
    return 0
  done

  edit_append "$text"
  return 0
}

# Take off a line every name that already resolves to the same address further
# up, and drop the line if that leaves it with nothing but an address.
#
# The scan reports one duplicate-name per line, because to a reader a line
# repeating several names of an earlier one is a single mistake. A fix cannot
# work that way: it has to deal with all of them, or one pass would not be
# enough and running the command twice would keep finding more.
_check_fix_duplicate_names() {
  local -i index=$1
  local raw=${_hf_raw[index]} name lname
  local -A seen_here=()
  local -a own_names=() carriers=()
  local -i changed=0 other

  record_names "$index"
  own_names=("${RECORD_NAMES[@]}")

  for name in "${own_names[@]}"; do
    lname=${name,,}

    # The same name written twice on one line: the second one is redundant
    # against the first, and no other line has to be involved.
    if [[ -n ${seen_here[$lname]:-} ]]; then
      if line_remove_name "$raw" "$name"; then
        raw=$LINE_RESULT
        changed=1
      fi
      continue
    fi
    seen_here[$lname]=1

    split_on_whitespace "${_hf_by_name[$lname]:-}"
    carriers=("${FIELDS[@]}")
    for other in "${carriers[@]}"; do
      ((other < index)) || continue
      ((_hf_enabled[other])) || continue
      ((!_hf_in_block[other])) || continue
      [[ ${_hf_ip[other]} == "${_hf_ip[index]}" ]] || continue
      if line_remove_name "$raw" "$name"; then
        raw=$LINE_RESULT
        changed=1
      fi
      break
    done
  done

  ((changed)) || return 1

  if ((LINE_NAMES_LEFT == 0)); then
    edit_delete "$index"
  else
    edit_replace "$index" "$raw"
  fi

  return 0
}

# Turn the fixable findings into one change over the file. Every edit is keyed
# by the line it belongs to and the file is rendered from the indices it was
# read with, so nothing here has to reason about line numbers moving underneath
# it. _ck_fixed records what was dealt with, so the report can leave it out.
_check_fix_build() {
  local -i i

  for ((i = 0; i < ${#_ck_rule[@]}; i++)); do
    _check_fixable "${_ck_rule[i]}" || continue

    # A line of 0 means the finding is about the file rather than a line of it,
    # so only the rules below that name a line may turn it into an index.
    case ${_ck_rule[i]} in
      missing-trailing-newline)
        edit_end_with_newline
        ;;
      missing-loopback)
        line_new_entry '127.0.0.1' 'localhost'
        _check_fix_insert_entry "$LINE_RESULT"
        ;;
      missing-loopback6)
        line_new_entry '::1' 'localhost' 'ip6-localhost'
        _check_fix_insert_entry "$LINE_RESULT"
        ;;
      duplicate-entry)
        edit_delete "$((_ck_line[i] - 1))"
        ;;
      duplicate-name)
        # The scan gives a line either a duplicate-entry, and then no name
        # findings at all, or at most one duplicate-name. So no line reaches
        # this twice and none of these edits can land on top of another.
        _check_fix_duplicate_names "$((_ck_line[i] - 1))" || continue
        ;;
    esac

    _ck_fixed[i]=1
  done
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
  local -i errors=$1 warnings=$2 fixed=$3
  local -i i reported=0
  local sep line related subject
  local -a related_lines=()

  json_literal "$_hf_path"
  printf '{\n'
  printf '  "version": %d,\n' "$JSON_SCHEMA_VERSION"
  printf '  "file": %s,\n' "$JSON_LITERAL"
  printf '  "summary": { "errors": %d, "warnings": %d, "fixed": %d },\n' \
    "$errors" "$warnings" "$fixed"
  printf '  "findings": ['

  sep=$'\n'
  for ((i = 0; i < ${#_ck_rule[@]}; i++)); do
    printf '%s' "$sep"
    sep=$',\n'
    reported+=1

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

  if ((reported > 0)); then
    printf '\n  ]\n'
  else
    printf ']\n'
  fi
  printf '}\n'
}

cmd_check() {
  local -i strict=0 fix=0 i errors=0 warnings=0 fixed=0 fixable=0
  local target

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
      --fix)
        fix=1
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

  # The preview of a change is a diff on stdout, which would leave the JSON
  # document it was printed beside unparseable. Better to refuse the
  # combination than to emit something no reader can consume.
  if ((fix && OPT_JSON && OPT_DRY_RUN)); then
    die_usage 'check ' 'combine --fix and --dry-run without --json: the preview is not JSON'
  fi

  if ((fix)); then
    # The lock goes on before the read, so that the file the fix is computed
    # from is the file the fix is written to.
    open_for_write "$OPT_FILE" target
    hostsfile_load "$target"
  else
    hostsfile_load "$OPT_FILE"
  fi

  _check_scan

  if ((fix)); then
    edit_reset
    _check_fix_build
    _check_count_fixed fixable
    edit_commit "$target" 'fix what can be fixed without guessing'

    # After a write, neither the findings nor their line numbers describe the
    # file any longer, and a message naming another line would name the wrong
    # one. So the file is read and scanned again rather than the findings being
    # patched up: every number and every message is then right by construction,
    # and anything the fix itself introduced gets reported too. Under --dry-run
    # nothing was written, so what was found still describes the file exactly
    # and nothing was in fact fixed.
    if ((OPT_DRY_RUN)); then
      fixed=0
    else
      fixed=$fixable
      if ((fixed > 0)); then
        _check_reset
        hostsfile_load "$target"
        _check_scan
      fi
    fi
  fi

  for ((i = 0; i < ${#_ck_rule[@]}; i++)); do
    if [[ ${_ck_severity[i]} == 'error' ]]; then
      errors+=1
    else
      warnings+=1
    fi
  done

  if ((OPT_JSON)); then
    _check_report_json "$errors" "$warnings" "$fixed"
  else
    _check_report_text
  fi

  if ((fix && OPT_DRY_RUN)); then
    info "$_hf_count lines, $fixable fixable, $errors errors, $warnings warnings"
  elif ((fix)); then
    info "$_hf_count lines, $fixed fixed, $errors errors, $warnings warnings"
  else
    info "$_hf_count lines, $errors errors, $warnings warnings"
  fi

  if ((errors > 0)); then
    return "$EX_VALIDATION"
  fi
  if ((strict && warnings > 0)); then
    return "$EX_VALIDATION"
  fi

  return "$EX_OK"
}
