# shellcheck shell=bash
#
# hosts get - show the addresses a hostname points at.

cmd_get() {
  local hostname
  local -i index
  local -a positional=()

  while (($#)); do
    case $1 in
      -h | --help)
        help_get
        return "$EX_OK"
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        die_usage 'get ' "unknown option for 'get': $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if ((${#positional[@]} != 1)); then
    die_usage 'get ' 'get requires exactly one hostname'
  fi
  hostname=${positional[0]}

  hostsfile_load "$OPT_FILE"

  # Only active entries are considered: a commented out entry does not take
  # part in name resolution, so reporting its address would be a lie.
  records_for_name "$hostname"

  if ((OPT_JSON)); then
    json_literal "$hostname"
    records_json_document "\"hostname\": $JSON_LITERAL" -- "${SELECTED[@]}"
  else
    for index in "${SELECTED[@]}"; do
      printf '%s\n' "${_hf_ip[index]}"
    done
  fi

  if ((${#SELECTED[@]} == 0)); then
    return "$EX_NOTFOUND"
  fi

  return "$EX_OK"
}
