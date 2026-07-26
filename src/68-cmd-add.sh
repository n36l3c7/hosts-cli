# shellcheck shell=bash
#
# hosts add - add or update an entry.

# The line a --force retargeted, or -1. The helpers below read the blocking
# list of cmd_add through dynamic scope, which is how bash locals work.
_ADD_RETARGETED=-1

cmd_add() {
  local address family target name lowered
  local -a positional=() names=() candidates=()
  local -a homes=() blocking=()
  local -i index home placed=0
  local -A seen_home=() seen_blocking=()

  while (($#)); do
    case $1 in
      -h | --help)
        help_add
        return "$EX_OK"
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        die_usage 'add ' "unknown option for 'add': $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if ((${#positional[@]} < 2)); then
    die_usage 'add ' 'add requires an address and at least one hostname'
  fi

  address=${positional[0]}
  names=("${positional[@]:1}")

  if ! classify_address "$address"; then
    die "$EX_VALIDATION" "not a valid IPv4 or IPv6 address: $address"
  fi
  family=$_ADDRESS_FAMILY

  # The same names check treats as an error what check treats as an error, and
  # merely warns where check warns. It would make no sense for check to
  # tolerate an underscore and for add to refuse it.
  for name in "${names[@]}"; do
    if is_valid_hostname "$name"; then
      continue
    fi
    if is_lenient_hostname "$name"; then
      warn "hostname is outside RFC 1123: $name"
      continue
    fi
    die "$EX_VALIDATION" "not a valid hostname: $name"
  done

  resolve_path "$OPT_FILE" || die "$EX_ERROR" "cannot resolve $OPT_FILE"
  target=$RESOLVED_PATH
  hostsfile_load "$target"

  # Work out, for every name, whether it is already where it should be, in the
  # way of what is being asked, or simply absent.
  local -a missing=()
  for name in "${names[@]}"; do
    lowered=${name,,}
    split_on_whitespace "${_hf_by_name[$lowered]:-}"
    candidates=("${FIELDS[@]}")

    home=-1
    for index in "${candidates[@]}"; do
      # A name on the other address family is ordinary dual stack, never a
      # clash: without this, adding an IPv6 entry beside an IPv4 one would be
      # refused on every machine that has both.
      [[ ${_hf_family[index]} == "$family" ]] || continue

      if ((_hf_enabled[index])) && [[ ${_hf_ip[index]} == "$address" ]]; then
        home=$index
        continue
      fi

      if [[ -z ${seen_blocking[$index]:-} ]]; then
        seen_blocking[$index]=1
        blocking+=("$index")
      fi
    done

    if ((home >= 0)); then
      if [[ -z ${seen_home[$home]:-} ]]; then
        seen_home[$home]=1
        homes+=("$home")
      fi
    else
      missing+=("$name")
    fi
  done

  edit_reset

  if ((${#blocking[@]} > 0)); then
    if ((!OPT_FORCE)); then
      _add_report_blocking "$address"
    fi
    _add_clear_blocking "$address" "${names[@]}"
    if ((_ADD_RETARGETED >= 0)); then
      placed=1
    fi
  fi

  if ((!placed)); then
    if ((${#missing[@]} == 0)); then
      info "$address already maps to ${names[*]}"
      return "$EX_OK"
    fi

    if ((${#homes[@]} > 1)); then
      local -a numbers=()
      for index in "${homes[@]}"; do
        numbers+=("$((index + 1))")
      done
      die "$EX_CONFLICT" \
        "the names are spread over lines ${numbers[*]}; merging them is your call"
    fi

    if ((${#homes[@]} == 1)); then
      _add_names_to_line "${homes[0]}" "${missing[@]}"
    else
      line_new_entry "$address" "${missing[@]}"
      edit_append "$LINE_RESULT"
    fi
  fi

  edit_commit "$target" "add $address ${names[*]}"
}

# Refuse, saying exactly what is in the way and how to get past it.
_add_report_blocking() {
  local address=$1 what
  local -i index=${blocking[0]}

  if ((_hf_enabled[index])); then
    what="${_hf_names[index]} already points at ${_hf_ip[index]} on line $((index + 1))"
    die "$EX_CONFLICT" "$what; pass --force to point it at $address instead"
  fi

  what="line $((index + 1)) is a disabled entry for ${_hf_names[index]}"
  die "$EX_CONFLICT" \
    "$what; enable it with '$PROGRAM_NAME on', or pass --force to replace it"
}

# With --force, get the lines that are in the way out of the way.
#
# A line that carries nothing but the names being added is about those names
# and nothing else, so its address is changed in place: that is what updating
# an entry means, and it is the smallest possible diff. Any other line keeps
# its own names and merely gives up the ones being moved.
_add_clear_blocking() {
  local address=$1
  shift
  local -a names=("$@")
  local -i index

  _ADD_RETARGETED=-1

  for index in "${blocking[@]}"; do
    if _add_line_is_only_about "$index" "${names[@]}"; then
      line_set_address "${_hf_raw[index]}" "$address"
      if ((!_hf_enabled[index])); then
        local retargeted=$LINE_RESULT
        line_enable "$retargeted"
      fi
      edit_replace "$index" "$LINE_RESULT"
      _ADD_RETARGETED=$index
      return 0
    fi
  done

  for index in "${blocking[@]}"; do
    _add_strip_names "$index" "${names[@]}"
  done

  return 0
}

# Succeed when a line carries exactly the names being added and no others.
_add_line_is_only_about() {
  local -i index=$1
  shift
  local -a wanted=("$@")
  local name candidate found

  record_names "$index"
  local -a on_line=("${RECORD_NAMES[@]}")

  ((${#on_line[@]} == ${#wanted[@]})) || return 1

  for name in "${on_line[@]}"; do
    found=''
    for candidate in "${wanted[@]}"; do
      if [[ ${name,,} == "${candidate,,}" ]]; then
        found=1
        break
      fi
    done
    [[ -n $found ]] || return 1
  done

  return 0
}

# Take the given names off a line, dropping the line when nothing is left.
_add_strip_names() {
  local -i index=$1
  shift
  local name raw
  local -i left

  raw=${_hf_raw[index]}
  left=-1

  for name in "$@"; do
    if line_remove_name "$raw" "$name"; then
      raw=$LINE_RESULT
      left=$LINE_NAMES_LEFT
    fi
  done

  ((left >= 0)) || return 0

  if ((left == 0)); then
    edit_delete "$index"
  else
    edit_replace "$index" "$raw"
  fi

  return 0
}

# Add the missing names as aliases of a line that already exists.
_add_names_to_line() {
  local -i index=$1
  shift
  local name raw=${_hf_raw[index]}

  for name in "$@"; do
    line_add_name "$raw" "$name"
    raw=$LINE_RESULT
  done

  edit_replace "$index" "$raw"
}
