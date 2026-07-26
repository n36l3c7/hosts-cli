# shellcheck shell=bash
#
# hosts export - write the file to stdout.
#
# Without --json this reproduces the file byte for byte, including comments,
# blank lines and a missing final newline. It exists so that reading the file
# always goes through the same --file handling as every other command, and as
# the counterpart of the import command.

cmd_export() {
  local -i index last

  while (($#)); do
    case $1 in
      -h | --help)
        help_export
        return "$EX_OK"
        ;;
      --)
        shift
        break
        ;;
      *)
        die_usage 'export ' "export takes no argument: $1"
        ;;
    esac
  done

  if (($# > 0)); then
    die_usage 'export ' "export takes no argument: $1"
  fi

  hostsfile_load "$OPT_FILE"

  if ((OPT_JSON)); then
    # Every line is reported, not just the entries: the point of exporting is
    # fidelity, and comments and blank lines are part of the file.
    local -a all=()
    for ((index = 0; index < _hf_count; index++)); do
      all+=("$index")
    done
    records_json_document -- "${all[@]}"
    return "$EX_OK"
  fi

  last=$((_hf_count - 1))
  for ((index = 0; index < _hf_count; index++)); do
    if ((index == last && !_hf_trailing_newline)); then
      printf '%s' "${_hf_raw[index]}"
    else
      printf '%s\n' "${_hf_raw[index]}"
    fi
  done

  return "$EX_OK"
}
