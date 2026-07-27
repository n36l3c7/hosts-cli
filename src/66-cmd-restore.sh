# shellcheck shell=bash
#
# hosts restore - put a backup back in place.

cmd_restore() {
  local target directory id copy meta actual_sha256
  local -a positional=()
  local -A meta_fields=()

  while (($#)); do
    case $1 in
      -h | --help)
        help_restore
        return "$EX_OK"
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        die_usage 'restore ' "unknown option for 'restore': $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if ((${#positional[@]} > 1)); then
    die_usage 'restore ' 'restore accepts at most one backup'
  fi

  resolve_path "$OPT_FILE" target || die "$EX_ERROR" "cannot resolve $OPT_FILE"

  backup_resolve_id "$target" "${positional[0]:-}" id
  backup_dir_for "$target" directory
  backup_paths_for "$directory" "$id" copy meta
  backup_meta_read "$meta" meta_fields

  # The check that makes the whole store safe. A backup taken with --file from
  # somewhere else must never be written over this file.
  if [[ ${meta_fields[target]:-} != "$target" ]]; then
    die "$EX_INTEGRITY" \
      "the backup $id was taken from ${meta_fields[target]:-nowhere}, not from $target"
  fi

  file_sha256 "$copy" actual_sha256
  if [[ $actual_sha256 != "${meta_fields[sha256]:-}" ]]; then
    die "$EX_INTEGRITY" \
      "the backup $id does not match its own checksum and will not be used"
  fi

  if ((OPT_DRY_RUN)); then
    _restore_show_difference "$copy" "$target"
    info "would restore the backup $id over $target"
    return "$EX_OK"
  fi

  confirm "restore the backup $id of ${meta_fields[time]:-an unknown time} over $target?"

  # The current content is kept first, so that a restore is itself undoable.
  backup_before_write "$target"

  atomic_install_file "$target" "$copy" "${meta_fields[sha256]}"

  info "restored the backup $id over $target"

  return "$EX_OK"
}

# Show what a restore would change, when there is a tool to show it with.
_restore_show_difference() {
  local copy=$1 target=$2

  if ! have_command diff; then
    info 'diff is not installed, so the change cannot be shown'
    return 0
  fi

  diff -u --label "$target" --label "$target (restored)" -- "$target" "$copy" ||
    true

  return 0
}
