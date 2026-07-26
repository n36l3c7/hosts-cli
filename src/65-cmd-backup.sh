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
  local target

  hostsfile_load "$OPT_FILE"
  resolve_path "$OPT_FILE" || die "$EX_ERROR" "cannot resolve $OPT_FILE"
  target=$RESOLVED_PATH

  backup_create "$target"

  if [[ -n $BACKUP_CREATED_ID ]]; then
    printf '%s\n' "$BACKUP_CREATED_ID"
  fi

  return "$EX_OK"
}

_backup_list() {
  local target id copy
  local -i i
  local sep=''

  resolve_path "$OPT_FILE" || die "$EX_ERROR" "cannot resolve $OPT_FILE"
  target=$RESOLVED_PATH

  backup_list "$target"

  if ((OPT_JSON)); then
    json_literal "$target"
    printf '{\n'
    printf '  "version": %d,\n' "$JSON_SCHEMA_VERSION"
    printf '  "file": %s,\n' "$JSON_LITERAL"
    json_literal "$BACKUP_DIR"
    printf '  "directory": %s,\n' "$JSON_LITERAL"
    printf '  "backups": ['

    sep=$'\n'
    for ((i = 0; i < ${#BACKUP_IDS[@]}; i++)); do
      id=${BACKUP_IDS[i]}
      copy=$(backup_path_for "$id")
      backup_meta_read "$(backup_meta_path_for "$id")"

      printf '%s' "$sep"
      sep=$',\n'
      printf '    {\n'
      printf '      "index": %d,\n' "$((i + 1))"
      json_literal "$id"
      printf '      "id": %s,\n' "$JSON_LITERAL"
      json_literal "$META_TIME"
      printf '      "time": %s,\n' "$JSON_LITERAL"
      printf '      "bytes": %d,\n' "$(_file_size "$copy")"
      json_literal "$META_SHA256"
      printf '      "sha256": %s,\n' "$JSON_LITERAL"
      json_literal "$META_MODE"
      printf '      "mode": %s,\n' "$JSON_LITERAL"
      json_literal "$META_OWNER"
      printf '      "owner": %s,\n' "$JSON_LITERAL"
      json_literal "$META_GROUP"
      printf '      "group": %s\n' "$JSON_LITERAL"
      printf '    }'
    done

    if ((${#BACKUP_IDS[@]} > 0)); then
      printf '\n  ]\n'
    else
      printf ']\n'
    fi
    printf '}\n'
    return "$EX_OK"
  fi

  for ((i = 0; i < ${#BACKUP_IDS[@]}; i++)); do
    id=${BACKUP_IDS[i]}
    copy=$(backup_path_for "$id")
    backup_meta_read "$(backup_meta_path_for "$id")"
    printf '%d\t%s\t%s\t%s\n' \
      "$((i + 1))" "$id" "$META_TIME" "$(_file_size "$copy")"
  done

  return "$EX_OK"
}

_file_size() {
  local output
  output=$(stat -c '%s' -- "$1" 2>/dev/null) || output=0
  printf '%s' "$output"
}
