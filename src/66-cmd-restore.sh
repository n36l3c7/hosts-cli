# shellcheck shell=bash
#
# hosts restore - put a backup back in place.

cmd_restore() {
  local target id copy expected_sha256 taken_at
  local -a positional=()

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

  resolve_path "$OPT_FILE" || die "$EX_ERROR" "cannot resolve $OPT_FILE"
  target=$RESOLVED_PATH

  backup_resolve_id "$target" "${positional[0]:-}"
  id=$BACKUP_RESOLVED_ID
  copy=$(backup_path_for "$id")

  backup_meta_read "$(backup_meta_path_for "$id")"

  # The check that makes the whole store safe. A backup taken with --file from
  # somewhere else must never be written over this file.
  if [[ $META_TARGET != "$target" ]]; then
    die "$EX_INTEGRITY" \
      "the backup $id was taken from $META_TARGET, not from $target"
  fi

  # Kept aside before anything else runs: taking the backup below reads other
  # sidecars, and the META_* variables hold whichever was read last.
  expected_sha256=$META_SHA256
  taken_at=$META_TIME

  file_sha256 "$copy"
  if [[ $FILE_SHA256 != "$expected_sha256" ]]; then
    die "$EX_INTEGRITY" \
      "the backup $id does not match its own checksum and will not be used"
  fi

  if ((OPT_DRY_RUN)); then
    _restore_show_difference "$copy" "$target"
    info "would restore the backup $id over $target"
    return "$EX_OK"
  fi

  confirm "restore the backup $id of $taken_at over $target?"

  # The current content is kept first, so that a restore is itself undoable.
  backup_before_write "$target"

  atomic_install_file "$target" "$copy" "$expected_sha256"

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
