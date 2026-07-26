# shellcheck shell=bash
#
# hosts diff - compare the file with a backup.

cmd_diff() {
  local target id copy
  local -a positional=()

  while (($#)); do
    case $1 in
      -h | --help)
        help_diff
        return "$EX_OK"
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        die_usage 'diff ' "unknown option for 'diff': $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if ((${#positional[@]} > 1)); then
    die_usage 'diff ' 'diff accepts at most one backup'
  fi

  # diff comes from diffutils rather than coreutils, so it is an optional
  # dependency and its absence is reported plainly instead of being worked
  # around with a worse implementation.
  if ! have_command diff; then
    die "$EX_ERROR" 'diff is not installed; it comes from the diffutils package'
  fi

  resolve_path "$OPT_FILE" || die "$EX_ERROR" "cannot resolve $OPT_FILE"
  target=$RESOLVED_PATH

  backup_resolve_id "$target" "${positional[0]:-}"
  id=$BACKUP_RESOLVED_ID
  copy=$(backup_path_for "$id")

  # The backup comes first, so that added lines are what the file has now and
  # removed lines are what it used to have.
  diff -u --label "$id" --label "$target" -- "$copy" "$target" || true

  return "$EX_OK"
}
