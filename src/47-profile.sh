# shellcheck shell=bash
#
# The profile store.
#
# A profile is a snapshot of the whole file kept under a name the user chose,
# so that a known state can be brought back later. It is not an overlay: it
# replaces the file rather than being merged into it.
#
# A snapshot with a name is the same object as a backup, so everything that
# makes a backup safe is reused unchanged: the byte for byte copy, the sidecar
# recording the path it came from, and the checksum. What differs is the
# lifetime. Backups are taken automatically and rotate; profiles are made on
# purpose and never go away by themselves. Keeping them in a directory of
# their own means rotation cannot reach them without knowing anything about
# them, and neither listing has to filter the other out.
#
# As in the backup store, locals here are prefixed with an underscore so that
# they cannot shadow a variable a caller asked to have filled.

# The root of the profile store.
profile_root() {
  printf '%s' "${HOSTS_PROFILE_DIR:-$DEFAULT_PROFILE_ROOT}"
}

# Store the directory holding the profiles of a target. Namespaced by target
# for the same reason backups are: a profile of a scratch file must not be
# reachable when the target is /etc/hosts.
profile_dir_for() {
  local _target=$1
  local -n _out_dir=$2
  local _slug _digest

  string_sha256 "$_target" _digest

  _slug=${_target#/}
  _slug=${_slug//\//_}
  _slug=${_slug//[^A-Za-z0-9._-]/_}
  _slug=${_slug:0:64}

  _out_dir="$(profile_root)/$_slug.${_digest:0:8}"
}

# Store the path of the copy, and of the sidecar, of one profile.
profile_paths_for() {
  local _directory=$1 _name=$2
  local -n _out_copy=$3
  local -n _out_meta=$4

  _out_copy="$_directory/$_name.bak"
  _out_meta="$_directory/$_name.meta"
}

# Reject a name that could not safely become a filename.
#
# This is not about tidiness. Without it, a name of ../../etc/passwd is a
# question nobody should have to think about.
profile_check_name() {
  local _name=$1

  if [[ -z $_name ]]; then
    die "$EX_VALIDATION" 'a profile needs a name'
  fi

  if ((${#_name} > MAX_PROFILE_NAME_LENGTH)); then
    die "$EX_VALIDATION" \
      "the name is longer than $MAX_PROFILE_NAME_LENGTH characters: $_name"
  fi

  case $_name in
    [.-]*)
      die "$EX_VALIDATION" "a profile name cannot start with . or -: $_name"
      ;;
    *[!A-Za-z0-9._-]*)
      die "$EX_VALIDATION" \
        "a profile name may hold only letters, digits, dot, dash and underscore: $_name"
      ;;
  esac

  return 0
}

# Store the names of the profiles of a target, in the order the shell gives
# them, which for these names is alphabetical and so is stable.
profile_list() {
  local _target=$1
  local -n _out_names=$2
  local _directory _path _name
  local -a _copies=()

  _out_names=()
  profile_dir_for "$_target" _directory

  [[ -d $_directory ]] || return 0

  expand_glob "$_directory/*.bak"
  _copies=("${FIELDS[@]}")

  for _path in "${_copies[@]}"; do
    _name=${_path##*/}
    _name=${_name%.bak}
    # A copy without its sidecar is an interrupted save and is ignored.
    [[ -f "$_directory/$_name.meta" ]] || continue
    _out_names+=("$_name")
  done

  return 0
}

# Succeed when a profile of that name exists.
profile_exists() {
  local _target=$1 _name=$2
  local _directory _copy _meta

  profile_dir_for "$_target" _directory
  profile_paths_for "$_directory" "$_name" _copy _meta

  [[ -f $_copy && -f $_meta ]]
}

# Save the current file under a name.
#
# Unlike a backup this never deduplicates: asking for a state to be kept under
# a name means wanting it under that name, whether or not the same bytes are
# already kept under another.
profile_save() {
  local _target=$1 _name=$2
  local _directory _copy _meta _digest

  profile_dir_for "$_target" _directory
  profile_paths_for "$_directory" "$_name" _copy _meta

  if [[ -f $_copy ]] && ((!OPT_FORCE)); then
    die "$EX_CONFLICT" \
      "the profile $_name already exists; pass --force to replace it"
  fi

  file_sha256 "$_target" _digest

  if ((OPT_DRY_RUN)); then
    info "would save $_target as the profile $_name in $_directory"
    return 0
  fi

  if ! mkdir -p -- "$_directory"; then
    die "$EX_PERM" \
      "cannot create $_directory; set HOSTS_PROFILE_DIR to a writable directory"
  fi

  if ! cp -- "$_target" "$_copy.tmp"; then
    die "$EX_PERM" "cannot write into $_directory"
  fi
  mv -f -- "$_copy.tmp" "$_copy"

  # The sidecar is the same shape as a backup's, and written last for the same
  # reason: its presence is what says the copy beside it is complete.
  snapshot_write_meta "$_meta" "$_target" "$_digest"

  return 0
}
