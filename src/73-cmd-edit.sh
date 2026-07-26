# shellcheck shell=bash
#
# hosts edit - open the file in an editor and check it on the way back in.

_EDIT_ERRORS=0

cmd_edit() {
  local target workdir copy original_sha edited_sha
  local -i errors

  while (($#)); do
    case $1 in
      -h | --help)
        help_edit
        return "$EX_OK"
        ;;
      --)
        shift
        break
        ;;
      *)
        die_usage 'edit ' "edit takes no argument: $1"
        ;;
    esac
  done

  if ((OPT_DRY_RUN)); then
    die_usage 'edit ' 'edit has nothing to preview; use --file to work on a copy'
  fi

  resolve_path "$OPT_FILE" || die "$EX_ERROR" "cannot resolve $OPT_FILE"
  target=$RESOLVED_PATH

  # Fail before the editor opens rather than after the work is done.
  local directory=${target%/*}
  [[ $directory != "$target" ]] || directory='.'
  if [[ ! -w $directory ]]; then
    die "$EX_PERM" "cannot write in $directory: $(write_failure_hint "$target")"
  fi

  file_sha256 "$target"
  original_sha=$FILE_SHA256

  workdir=$(mktemp -d) || die "$EX_ERROR" 'cannot create a working directory'
  copy="$workdir/hosts"
  cp -- "$target" "$copy" || {
    rm -rf -- "$workdir"
    die "$EX_ERROR" "cannot copy $target"
  }

  while true; do
    _edit_run_editor "$copy" || {
      rm -rf -- "$workdir"
      die "$EX_ERROR" 'the editor exited with an error'
    }

    file_sha256 "$copy"
    if [[ $FILE_SHA256 == "$original_sha" ]]; then
      rm -rf -- "$workdir"
      info "$target is unchanged"
      return "$EX_OK"
    fi

    _edit_report "$copy"
    errors=$_EDIT_ERRORS
    ((errors > 0)) || break

    # The work is never thrown away. With a terminal the editor opens again,
    # the way visudo does it; without one there is nobody to ask, so the file
    # stays where it is and its path is printed.
    if [[ ! -t 0 ]]; then
      err "$copy has $errors error(s) and was not installed; it is kept there"
      return "$EX_VALIDATION"
    fi

    if ! _edit_ask_again; then
      err "left as it was; your edit is kept in $copy"
      return "$EX_ABORTED"
    fi
  done

  # Kept aside before anything else runs: taking the backup below checksums
  # the target, and FILE_SHA256 holds whatever was hashed last.
  file_sha256 "$copy"
  local edited_sha=$FILE_SHA256

  backup_before_write "$target"
  atomic_install_file "$target" "$copy" "$edited_sha"
  rm -rf -- "$workdir"

  info "$target updated"
  return "$EX_OK"
}

# Run the editor on a file, in the environment the user actually has.
#
# The program sets LC_ALL=C so that character ranges behave the same
# everywhere, which is right for parsing and wrong for an editor that is about
# to be shown a file of someone else's text.
_edit_run_editor() {
  local file=$1 chosen
  local -a editor_command=()

  chosen=${VISUAL:-${EDITOR:-vi}}
  split_on_whitespace "$chosen"
  editor_command=("${FIELDS[@]}")

  ((${#editor_command[@]} > 0)) || die "$EX_ERROR" 'no editor to run'

  info "opening ${editor_command[0]}"

  if [[ -n $HOSTS_ORIGINAL_LC_ALL ]]; then
    LC_ALL=$HOSTS_ORIGINAL_LC_ALL "${editor_command[@]}" "$file"
  else
    env -u LC_ALL "${editor_command[@]}" "$file"
  fi
}

# Lint the edited copy and print what is wrong with it.
_edit_report() {
  local file=$1
  local -i i

  hostsfile_load "$file"

  _ck_rule=()
  _ck_severity=()
  _ck_line=()
  _ck_related=()
  _ck_subject=()
  _ck_message=()
  _check_scan

  _EDIT_ERRORS=0
  for ((i = 0; i < ${#_ck_rule[@]}; i++)); do
    if [[ ${_ck_severity[i]} == 'error' ]]; then
      _EDIT_ERRORS=$((_EDIT_ERRORS + 1))
    fi
  done

  # Errors stop the file being installed; warnings are said and let through,
  # the same judgement check makes without --strict.
  ((${#_ck_rule[@]} > 0)) || return 0
  _check_report_text >&2

  return 0
}

_edit_ask_again() {
  local reply

  printf 'edit again, or leave the file as it was? [E/l] ' >&2
  IFS= read -r reply || reply='l'

  case ${reply,,} in
    l | leave | q | quit | a | abort) return 1 ;;
  esac

  return 0
}
