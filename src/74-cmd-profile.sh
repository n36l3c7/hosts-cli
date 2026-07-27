# shellcheck shell=bash
#
# hosts profile - save, restore, list and delete named states of the file.

cmd_profile() {
  local subcommand
  local -a positional=()

  while (($#)); do
    case $1 in
      -h | --help)
        help_profile
        return "$EX_OK"
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        die_usage 'profile ' "unknown option for 'profile': $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if ((${#positional[@]} == 0)); then
    die_usage 'profile ' 'profile needs one of save, load, ls or rm'
  fi

  subcommand=${positional[0]}
  positional=("${positional[@]:1}")

  case $subcommand in
    save) _profile_save "${positional[@]}" ;;
    load) _profile_load "${positional[@]}" ;;
    ls) _profile_ls "${positional[@]}" ;;
    rm) _profile_rm "${positional[@]}" ;;
    *) die_usage 'profile ' "unknown subcommand for 'profile': $subcommand" ;;
  esac
}

# Saving only reads the file, so it needs no privilege on it; what it needs is
# somewhere to write the copy.
_profile_save() {
  local target name

  (($# == 1)) || die_usage 'profile ' 'profile save takes one name'
  name=$1
  profile_check_name "$name"

  hostsfile_load "$OPT_FILE"
  resolve_path "$OPT_FILE" target || die "$EX_ERROR" "cannot resolve $OPT_FILE"

  profile_save "$target" "$name"
  info "saved $target as the profile $name"

  return "$EX_OK"
}

# Loading goes through the same path a restore takes, and so inherits every
# safety property already tested there: the checksum is verified, a snapshot
# taken from another file is refused, and the content being replaced is kept
# first, which is what makes a load undoable with 'hosts restore'.
_profile_load() {
  local target directory name copy meta actual_sha256
  local -A meta_fields=()

  (($# == 1)) || die_usage 'profile ' 'profile load takes one name'
  name=$1
  profile_check_name "$name"

  resolve_path "$OPT_FILE" target || die "$EX_ERROR" "cannot resolve $OPT_FILE"

  if ! profile_exists "$target" "$name"; then
    die "$EX_NOTFOUND" "there is no profile $name for $target"
  fi

  profile_dir_for "$target" directory
  profile_paths_for "$directory" "$name" copy meta
  backup_meta_read "$meta" meta_fields

  if [[ ${meta_fields[target]:-} != "$target" ]]; then
    die "$EX_INTEGRITY" \
      "the profile $name was saved from ${meta_fields[target]:-nowhere}, not from $target"
  fi

  file_sha256 "$copy" actual_sha256
  if [[ $actual_sha256 != "${meta_fields[sha256]:-}" ]]; then
    die "$EX_INTEGRITY" \
      "the profile $name does not match its own checksum and will not be used"
  fi

  if ((OPT_DRY_RUN)); then
    _profile_show_difference "$copy" "$target"
    info "would load the profile $name over $target"
    return "$EX_OK"
  fi

  confirm "load the profile $name over $target?"

  backup_before_write "$target"
  atomic_install_file "$target" "$copy" "${meta_fields[sha256]}"

  info "loaded the profile $name over $target"

  return "$EX_OK"
}

_profile_ls() {
  local target directory name copy meta sep=''
  local -a names=()
  local -A meta_fields=()
  local -i i

  (($# == 0)) || die_usage 'profile ' 'profile ls takes no argument'

  resolve_path "$OPT_FILE" target || die "$EX_ERROR" "cannot resolve $OPT_FILE"

  profile_dir_for "$target" directory
  profile_list "$target" names

  if ((OPT_JSON)); then
    json_literal "$target"
    printf '{\n'
    printf '  "version": %d,\n' "$JSON_SCHEMA_VERSION"
    printf '  "file": %s,\n' "$JSON_LITERAL"
    json_literal "$directory"
    printf '  "directory": %s,\n' "$JSON_LITERAL"
    printf '  "profiles": ['

    sep=$'\n'
    for ((i = 0; i < ${#names[@]}; i++)); do
      name=${names[i]}
      profile_paths_for "$directory" "$name" copy meta
      backup_meta_read "$meta" meta_fields

      printf '%s' "$sep"
      sep=$',\n'
      printf '    {\n'
      json_literal "$name"
      printf '      "name": %s,\n' "$JSON_LITERAL"
      json_literal "${meta_fields[time]:-}"
      printf '      "time": %s,\n' "$JSON_LITERAL"
      printf '      "bytes": %d,\n' "$(file_size "$copy")"
      json_literal "${meta_fields[sha256]:-}"
      printf '      "sha256": %s\n' "$JSON_LITERAL"
      printf '    }'
    done

    if ((${#names[@]} > 0)); then
      printf '\n  ]\n'
    else
      printf ']\n'
    fi
    printf '}\n'
    return "$EX_OK"
  fi

  for name in "${names[@]}"; do
    profile_paths_for "$directory" "$name" copy meta
    backup_meta_read "$meta" meta_fields
    printf '%s\t%s\t%s\n' \
      "$name" "${meta_fields[time]:-}" "$(file_size "$copy")"
  done

  return "$EX_OK"
}

# Deleting a profile destroys the only copy of something made on purpose, so
# it asks first.
_profile_rm() {
  local target directory name copy meta

  (($# == 1)) || die_usage 'profile ' 'profile rm takes one name'
  name=$1
  profile_check_name "$name"

  resolve_path "$OPT_FILE" target || die "$EX_ERROR" "cannot resolve $OPT_FILE"

  if ! profile_exists "$target" "$name"; then
    die "$EX_NOTFOUND" "there is no profile $name for $target"
  fi

  profile_dir_for "$target" directory
  profile_paths_for "$directory" "$name" copy meta

  if ((OPT_DRY_RUN)); then
    info "would delete the profile $name"
    return "$EX_OK"
  fi

  confirm "delete the profile $name of $target?"

  rm -f -- "$copy" "$meta"
  info "deleted the profile $name"

  return "$EX_OK"
}

_profile_show_difference() {
  local copy=$1 target=$2

  if ! have_command diff; then
    info 'diff is not installed, so the change cannot be shown'
    return 0
  fi

  diff -u --label "$target" --label "$target (loaded)" -- "$target" "$copy" ||
    true

  return 0
}
