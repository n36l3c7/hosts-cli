# shellcheck shell=bash
#
# The backup store.
#
# Backups live in one directory per target file, and every backup is a byte
# for byte copy with a sidecar of metadata beside it. The copy is kept plain
# on purpose: in an emergency it has to be possible to put the file back with
# cp, knowing nothing about this program.
#
# The sidecar is what makes restoring safe. It records the absolute path the
# backup was taken from, and restore refuses when that is not the file it is
# about to write. Without that check, a backup taken with --file from some
# scratch file could later be restored over /etc/hosts.
#
# Results come back through variables the caller names. The six metadata
# fields used to live in globals, and reading them after a call that had
# rewritten them in the meantime was one of the three bugs this refactor
# removes.
#
# Every local in a function that takes the name of a variable is prefixed with
# an underscore. That is not decoration: a local sharing its name with the
# variable the caller asked to fill shadows it, the nameref then points at the
# function's own copy, and the result quietly never reaches the caller.

# The root of the backup store.
backup_root() {
  printf '%s' "${HOSTS_BACKUP_DIR:-$DEFAULT_BACKUP_ROOT}"
}

# How many backups to keep per target.
backup_keep() {
  printf '%s' "${HOSTS_KEEP_BACKUPS:-$DEFAULT_BACKUP_KEEP}"
}

# Store the directory holding the backups of a target.
#
# The name is readable so that the store can be browsed by hand, and carries a
# digest of the path so that two different targets cannot share a directory.
# Correctness does not rest on it either way: the sidecar is what restore
# checks.
backup_dir_for() {
  local _target=$1
  local -n _out_dir=$2
  local _slug _digest

  string_sha256 "$_target" _digest

  _slug=${_target#/}
  _slug=${_slug//\//_}
  _slug=${_slug//[^A-Za-z0-9._-]/_}
  _slug=${_slug:0:64}

  _out_dir="$(backup_root)/$_slug.${_digest:0:8}"
}

# Store the path of the copy, and of the sidecar, of one backup.
backup_paths_for() {
  local _directory=$1 _id=$2
  local -n _out_copy=$3
  local -n _out_meta=$4

  _out_copy="$_directory/hosts.$_id.bak"
  _out_meta="$_directory/hosts.$_id.meta"
}

# Read a sidecar into an associative array the caller names, with the keys
# target, time, mode, owner, group and sha256.
backup_meta_read() {
  local _file=$1
  local -n _out_fields=$2
  local _line _key _value

  _out_fields=()

  while IFS= read -r _line; do
    _key=${_line%%=*}
    _value=${_line#*=}
    case $_key in
      target | time | mode | owner | group | sha256)
        _out_fields["$_key"]=$_value
        ;;
    esac
  done <"$_file"
}

# Store the identifiers of the backups of a target, newest first. A copy
# without its sidecar is an interrupted backup and is ignored.
backup_list() {
  local _target=$1
  local -n _out_ids=$2
  local _directory _path _id
  local -a _copies=()
  local -i _i

  _out_ids=()
  backup_dir_for "$_target" _directory

  [[ -d $_directory ]] || return 0

  expand_glob "$_directory/hosts.*.bak"
  _copies=("${FIELDS[@]}")

  # Identifiers begin with a timestamp, so the order the shell produces is
  # chronological and only has to be reversed.
  for ((_i = ${#_copies[@]} - 1; _i >= 0; _i--)); do
    _path=${_copies[_i]}
    _id=${_path##*/hosts.}
    _id=${_id%.bak}
    [[ -f "$_directory/hosts.$_id.meta" ]] || continue
    _out_ids+=("$_id")
  done

  return 0
}

# Delete the backups beyond the ones to keep. The most recent is never
# removed, whatever the setting says.
backup_rotate() {
  local target=$1 directory copy meta
  local -a ids=()
  local -i keep i

  keep=$(backup_keep)
  ((keep >= 1)) || keep=1

  backup_dir_for "$target" directory
  backup_list "$target" ids

  for ((i = keep; i < ${#ids[@]}; i++)); do
    backup_paths_for "$directory" "${ids[i]}" copy meta
    rm -f -- "$copy" "$meta"
    info "removed the backup ${ids[i]}"
  done

  return 0
}

# Take a backup of a target, unless it would be identical to the most recent
# one, storing the new identifier in the variable the caller names, empty when
# nothing was written.
backup_create() {
  local _target=$1
  local -n _out_created=$2
  local _directory _id _copy _meta _current
  local -a _ids=()
  local -A _previous=()

  _out_created=''

  file_sha256 "$_target" _current
  backup_dir_for "$_target" _directory
  backup_list "$_target" _ids

  if ((${#_ids[@]} > 0)); then
    backup_paths_for "$_directory" "${_ids[0]}" _copy _meta
    backup_meta_read "$_meta" _previous
    if [[ ${_previous[sha256]:-} == "$_current" ]]; then
      # Without this, twenty writes that change nothing would push every real
      # backup out of the rotation window.
      info "unchanged since the backup ${_ids[0]}, no new one taken"
      return 0
    fi
  fi

  if ((OPT_DRY_RUN)); then
    info "would take a backup of $_target in $_directory"
    return 0
  fi

  if ! mkdir -p -- "$_directory"; then
    die "$EX_PERM" \
      "cannot create $_directory; set HOSTS_BACKUP_DIR to a writable directory"
  fi

  timestamp_id _id
  backup_paths_for "$_directory" "$_id" _copy _meta

  if ! cp -- "$_target" "$_copy"; then
    die "$EX_PERM" "cannot write into $_directory"
  fi

  snapshot_write_meta "$_meta" "$_target" "$_current"

  _out_created=$_id
  info "took the backup $_id in $_directory"

  backup_rotate "$_target"

  return 0
}

# Write the sidecar of a copy, last and by rename, so that a sidecar always
# means a complete copy sits beside it.
snapshot_write_meta() {
  local meta=$1 target=$2 digest=$3
  local owner group mode

  file_attributes "$target" owner group mode

  {
    printf 'target=%s\n' "$target"
    printf 'time=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'mode=%s\n' "$mode"
    printf 'owner=%s\n' "$owner"
    printf 'group=%s\n' "$group"
    printf 'sha256=%s\n' "$digest"
  } >"$meta.tmp"

  mv -f -- "$meta.tmp" "$meta"
}

# Take the automatic backup that precedes a mutation, honouring --no-backup.
backup_before_write() {
  local target=$1 created

  if ((!OPT_BACKUP)); then
    warn 'writing without a backup'
    return 0
  fi

  backup_create "$target" created
}

# Resolve what the user typed into a backup identifier. Accepts an index as
# shown by "backup ls", where 1 is the most recent, or an identifier in full.
backup_resolve_id() {
  local _target=$1 _wanted=$2
  local -n _out_id=$3
  local _candidate
  local -a _ids=()
  local -i _index

  _out_id=''
  backup_list "$_target" _ids

  if ((${#_ids[@]} == 0)); then
    die "$EX_NOTFOUND" "there is no backup of $_target"
  fi

  if [[ -z $_wanted ]]; then
    _out_id=${_ids[0]}
    return 0
  fi

  case $_wanted in
    '' | *[!0-9]*) ;;
    *)
      _index=$_wanted
      if ((_index < 1 || _index > ${#_ids[@]})); then
        die "$EX_NOTFOUND" "there is no backup number $_wanted"
      fi
      _out_id=${_ids[_index - 1]}
      return 0
      ;;
  esac

  for _candidate in "${_ids[@]}"; do
    if [[ $_candidate == "$_wanted" ]]; then
      _out_id=$_candidate
      return 0
    fi
  done

  die "$EX_NOTFOUND" "there is no backup $_wanted of $_target"
}
