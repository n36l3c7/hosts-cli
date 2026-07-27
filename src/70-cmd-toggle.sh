# shellcheck shell=bash
#
# hosts on and hosts off - enable and disable entries without deleting them.
#
# Both act on every line carrying the name, because that is what turning a
# hostname on or off means. Acting on one line of a dual stack pair would
# leave the name resolving on the other family, which is a command doing half
# its job, and refusing to choose would fail on the most ordinary hosts file
# there is:
#
#   127.0.0.1  localhost
#   ::1        localhost

cmd_on() {
  _toggle_entries 'on' "$@"
}

cmd_off() {
  _toggle_entries 'off' "$@"
}

_toggle_entries() {
  local mode=$1
  shift
  local name target raw
  local -a positional=() candidates=()
  local -i index changed=0 already=0

  while (($#)); do
    case $1 in
      -h | --help)
        if [[ $mode == 'on' ]]; then
          help_on
        else
          help_off
        fi
        return "$EX_OK"
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        die_usage "$mode " "unknown option for '$mode': $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if ((${#positional[@]} != 1)); then
    die_usage "$mode " "$mode requires exactly one hostname"
  fi
  name=${positional[0]}

  resolve_path "$OPT_FILE" target || die "$EX_ERROR" "cannot resolve $OPT_FILE"
  hostsfile_load "$target"

  split_on_whitespace "${_hf_by_name[${name,,}]:-}"
  candidates=("${FIELDS[@]}")

  if ((${#candidates[@]} == 0)); then
    die "$EX_NOTFOUND" "no entry carries the name $name"
  fi

  edit_reset

  for index in "${candidates[@]}"; do
    raw=${_hf_raw[index]}
    if [[ $mode == 'off' ]]; then
      if ((!_hf_enabled[index])); then
        already=1
        continue
      fi
      line_disable "$raw"
    else
      if ((_hf_enabled[index])); then
        already=1
        continue
      fi
      line_enable "$raw"
    fi
    edit_replace "$index" "$LINE_RESULT"
    changed=1
  done

  # Asking for a state that already holds is not a failure: the file is how
  # it was asked to be.
  if ((!changed)); then
    if ((already)); then
      info "$name is already $mode"
    fi
    return "$EX_OK"
  fi

  edit_commit "$target" "turn $name $mode"
}
