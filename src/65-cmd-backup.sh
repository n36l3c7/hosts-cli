# shellcheck shell=bash
#
# hosts backup - take a backup, and list the ones already taken.

cmd_backup() {
  local -a positional=()

  while (($#)); do
    case $1 in
      -h | --help)
        help_backup
        return "$EX_OK"
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        die_usage 'backup ' "unknown option for 'backup': $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if ((${#positional[@]} > 1)); then
    die_usage 'backup ' 'backup accepts at most one subcommand'
  fi

  case ${positional[0]:-} in
    '')
      _backup_take
      ;;
    ls)
      _backup_list
      ;;
    *)
      die_usage 'backup ' "unknown subcommand for 'backup': ${positional[0]}"
      ;;
  esac
}

# Taking a backup only reads the target, so it needs no privilege on it; what
# it needs is somewhere to write the copy.
_backup_take() {
  local target created

  hostsfile_load "$OPT_FILE"
  resolve_path "$OPT_FILE" target || die "$EX_ERROR" "cannot resolve $OPT_FILE"

  backup_create "$target" created

  if [[ -n $created ]]; then
    printf '%s\n' "$created"
  fi

  return "$EX_OK"
}

_backup_list() {
  local target directory id copy meta sep=''
  local -a ids=()
  local -A meta_fields=()
  local -i i

  resolve_path "$OPT_FILE" target || die "$EX_ERROR" "cannot resolve $OPT_FILE"

  backup_dir_for "$target" directory
  backup_list "$target" ids

  if ((OPT_JSON)); then
    json_literal "$target"
    printf '{\n'
    printf '  "version": %d,\n' "$JSON_SCHEMA_VERSION"
    printf '  "file": %s,\n' "$JSON_LITERAL"
    json_literal "$directory"
    printf '  "directory": %s,\n' "$JSON_LITERAL"
    printf '  "backups": ['

    sep=$'\n'
    for ((i = 0; i < ${#ids[@]}; i++)); do
      id=${ids[i]}
      backup_paths_for "$directory" "$id" copy meta
      backup_meta_read "$meta" meta_fields

      printf '%s' "$sep"
      sep=$',\n'
      printf '    {\n'
      printf '      "index": %d,\n' "$((i + 1))"
      json_literal "$id"
      printf '      "id": %s,\n' "$JSON_LITERAL"
      json_literal "${meta_fields[time]:-}"
      printf '      "time": %s,\n' "$JSON_LITERAL"
      printf '      "bytes": %d,\n' "$(file_size "$copy")"
      json_literal "${meta_fields[sha256]:-}"
      printf '      "sha256": %s,\n' "$JSON_LITERAL"
      json_literal "${meta_fields[mode]:-}"
      printf '      "mode": %s,\n' "$JSON_LITERAL"
      json_literal "${meta_fields[owner]:-}"
      printf '      "owner": %s,\n' "$JSON_LITERAL"
      json_literal "${meta_fields[group]:-}"
      printf '      "group": %s\n' "$JSON_LITERAL"
      printf '    }'
    done

    if ((${#ids[@]} > 0)); then
      printf '\n  ]\n'
    else
      printf ']\n'
    fi
    printf '}\n'
    return "$EX_OK"
  fi

  for ((i = 0; i < ${#ids[@]}; i++)); do
    id=${ids[i]}
    backup_paths_for "$directory" "$id" copy meta
    backup_meta_read "$meta" meta_fields
    printf '%d\t%s\t%s\t%s\n' \
      "$((i + 1))" "$id" "${meta_fields[time]:-}" "$(file_size "$copy")"
  done

  return "$EX_OK"
}

file_size() {
  local output
  output=$(stat -c '%s' -- "$1" 2>/dev/null) || output=0
  printf '%s' "$output"
}
