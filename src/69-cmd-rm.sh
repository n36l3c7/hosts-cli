# shellcheck shell=bash
#
# hosts rm - remove entries by hostname or by address.

cmd_rm() {
  local subject target
  local -a positional=()

  while (($#)); do
    case $1 in
      -h | --help)
        help_rm
        return "$EX_OK"
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        die_usage 'rm ' "unknown option for 'rm': $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if ((${#positional[@]} != 1)); then
    die_usage 'rm ' 'rm requires exactly one hostname or address'
  fi
  subject=${positional[0]}

  resolve_path "$OPT_FILE" target || die "$EX_ERROR" "cannot resolve $OPT_FILE"
  hostsfile_load "$target"

  edit_reset

  local family=''
  if classify_address "$subject" family; then
    _rm_by_address "$subject"
    edit_commit "$target" "remove every entry for $subject"
  else
    _rm_by_name "$subject"
    edit_commit "$target" "remove $subject"
  fi
}

# Remove whole lines. Addresses are compared as they are written, so ::1 and
# 0:0:0:0:0:0:0:1 are two different subjects even though they name one address.
_rm_by_address() {
  local address=$1
  local -i index found=0

  for ((index = 0; index < _hf_count; index++)); do
    [[ ${_hf_kind[index]} == 'entry' ]] || continue
    [[ ${_hf_ip[index]} == "$address" ]] || continue
    edit_delete "$index"
    found=1
  done

  ((found)) || die "$EX_NOTFOUND" "no entry points at $address"
}

# Take a name off every line that carries it, active or not, and drop a line
# that is left with nothing but its address.
_rm_by_name() {
  local name=$1 raw
  local -a candidates=()
  local -i index found=0

  split_on_whitespace "${_hf_by_name[${name,,}]:-}"
  candidates=("${FIELDS[@]}")

  for index in "${candidates[@]}"; do
    raw=${_hf_raw[index]}
    line_remove_name "$raw" "$name" || continue
    found=1
    if ((LINE_NAMES_LEFT == 0)); then
      edit_delete "$index"
    else
      edit_replace "$index" "$LINE_RESULT"
    fi
  done

  ((found)) || die "$EX_NOTFOUND" "no entry carries the name $name"
}
