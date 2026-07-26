# shellcheck shell=bash
#
# hosts ls - list entries.

cmd_ls() {
  local pattern=''
  local -i show_active=1 show_disabled=0 show_blocked=0 index
  local -a positional=() selected=()

  while (($#)); do
    case $1 in
      -h | --help)
        help_ls
        return "$EX_OK"
        ;;
      -a | --all)
        show_active=1
        show_disabled=1
        shift
        ;;
      --disabled)
        show_active=0
        show_disabled=1
        shift
        ;;
      --blocked)
        show_blocked=1
        shift
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        die_usage 'ls ' "unknown option for 'ls': $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if ((${#positional[@]} > 1)); then
    die_usage 'ls ' "ls accepts at most one pattern"
  fi
  pattern=${positional[0]:-}

  hostsfile_load "$OPT_FILE"

  for ((index = 0; index < _hf_count; index++)); do
    [[ ${_hf_kind[index]} == 'entry' ]] || continue

    # A blocklist is thousands of machine written lines. Showing it by default
    # would bury the handful of entries someone actually maintains.
    if ((_hf_in_block[index] && !show_blocked)); then
      continue
    fi

    if ((_hf_enabled[index])); then
      ((show_active)) || continue
    else
      ((show_disabled)) || continue
    fi

    if [[ -n $pattern ]]; then
      record_matches_name_pattern "$index" "$pattern" || continue
    fi

    selected+=("$index")
  done

  if ((OPT_JSON)); then
    records_json_document -- "${selected[@]}"
  else
    for index in "${selected[@]}"; do
      record_text "$index"
    done
  fi

  return "$EX_OK"
}
