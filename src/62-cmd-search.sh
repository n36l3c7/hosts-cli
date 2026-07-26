# shellcheck shell=bash
#
# hosts search - find entries by address, name or comment.

cmd_search() {
  local needle
  local -i index
  local -a positional=() selected=()

  while (($#)); do
    case $1 in
      -h | --help)
        help_search
        return "$EX_OK"
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        die_usage 'search ' "unknown option for 'search': $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if ((${#positional[@]} != 1)); then
    die_usage 'search ' 'search requires exactly one pattern'
  fi
  needle=${positional[0]}

  hostsfile_load "$OPT_FILE"

  # Disabled entries are included: when searching you want to find them, and
  # the state column says which is which.
  for ((index = 0; index < _hf_count; index++)); do
    [[ ${_hf_kind[index]} == 'entry' ]] || continue
    record_matches_text "$index" "$needle" || continue
    selected+=("$index")
  done

  if ((OPT_JSON)); then
    json_literal "$needle"
    records_json_document "\"pattern\": $JSON_LITERAL" -- "${selected[@]}"
  else
    for index in "${selected[@]}"; do
      record_text "$index"
    done
  fi

  return "$EX_OK"
}
