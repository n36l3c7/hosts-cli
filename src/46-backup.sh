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

BACKUP_DIR=''
BACKUP_CREATED_ID=''
BACKUP_RESOLVED_ID=''
declare -a BACKUP_IDS=()

META_TARGET=''
META_TIME=''
META_MODE=''
META_OWNER=''
META_GROUP=''
META_SHA256=''

# The root of the backup store.
backup_root() {
  printf '%s' "${HOSTS_BACKUP_DIR:-$DEFAULT_BACKUP_ROOT}"
}

# How many backups to keep per target.
backup_keep() {
  printf '%s' "${HOSTS_KEEP_BACKUPS:-$DEFAULT_BACKUP_KEEP}"
}

# Store the backup directory of a target in BACKUP_DIR.
#
# The name is readable so that the store can be browsed by hand, and carries a
# digest of the path so that two different targets cannot share a directory.
# Correctness does not rest on it either way: the sidecar is what restore
# checks.
backup_dir_for() {
  local target=$1 slug

  string_sha256 "$target"

  slug=${target#/}
  slug=${slug//\//_}
  slug=${slug//[^A-Za-z0-9._-]/_}
  slug=${slug:0:64}

  BACKUP_DIR="$(backup_root)/$slug.${STRING_SHA256:0:8}"
}

backup_path_for() {
  printf '%s' "$BACKUP_DIR/hosts.$1.bak"
}

backup_meta_path_for() {
  printf '%s' "$BACKUP_DIR/hosts.$1.meta"
}

# Read a sidecar into the META_* variables.
backup_meta_read() {
  local file=$1 line key value

  META_TARGET=''
  META_TIME=''
  META_MODE=''
  META_OWNER=''
  META_GROUP=''
  META_SHA256=''

  while IFS= read -r line; do
    key=${line%%=*}
    value=${line#*=}
    case $key in
      target) META_TARGET=$value ;;
      time) META_TIME=$value ;;
      mode) META_MODE=$value ;;
      owner) META_OWNER=$value ;;
      group) META_GROUP=$value ;;
      sha256) META_SHA256=$value ;;
    esac
  done <"$file"
}

# Store the identifiers of the backups of a target in BACKUP_IDS, newest
# first. A copy without its sidecar is an interrupted backup and is ignored.
backup_list() {
  local target=$1 path id
  local -a copies=()
  local -i i

  backup_dir_for "$target"
  BACKUP_IDS=()

  [[ -d $BACKUP_DIR ]] || return 0

  expand_glob "$BACKUP_DIR/hosts.*.bak"
  copies=("${FIELDS[@]}")

  # Identifiers begin with a timestamp, so the order the shell produces is
  # chronological and only has to be reversed.
  for ((i = ${#copies[@]} - 1; i >= 0; i--)); do
    path=${copies[i]}
    id=${path##*/hosts.}
    id=${id%.bak}
    [[ -f "$BACKUP_DIR/hosts.$id.meta" ]] || continue
    BACKUP_IDS+=("$id")
  done

  return 0
}

# Delete the backups beyond the ones to keep. The most recent is never
# removed, whatever the setting says.
backup_rotate() {
  local target=$1 id
  local -i keep i

  keep=$(backup_keep)
  ((keep >= 1)) || keep=1

  backup_list "$target"

  for ((i = keep; i < ${#BACKUP_IDS[@]}; i++)); do
    id=${BACKUP_IDS[i]}
    rm -f -- "$(backup_path_for "$id")" "$(backup_meta_path_for "$id")"
    info "removed the backup $id"
  done

  return 0
}

# Take a backup of a target, unless it would be identical to the most recent
# one. Stores the new identifier in BACKUP_CREATED_ID, empty when nothing was
# written.
backup_create() {
  local target=$1 id copy meta current

  BACKUP_CREATED_ID=''

  file_sha256 "$target"
  current=$FILE_SHA256

  backup_list "$target"
  if ((${#BACKUP_IDS[@]} > 0)); then
    backup_meta_read "$(backup_meta_path_for "${BACKUP_IDS[0]}")"
    if [[ $META_SHA256 == "$current" ]]; then
      # Without this, twenty writes that change nothing would push every real
      # backup out of the rotation window.
      info "unchanged since the backup ${BACKUP_IDS[0]}, no new one taken"
      return 0
    fi
  fi

  if ((OPT_DRY_RUN)); then
    info "would take a backup of $target in $BACKUP_DIR"
    return 0
  fi

  if ! mkdir -p -- "$BACKUP_DIR"; then
    die "$EX_PERM" \
      "cannot create $BACKUP_DIR; set HOSTS_BACKUP_DIR to a writable directory"
  fi

  timestamp_id
  id=$TIMESTAMP_ID
  copy=$(backup_path_for "$id")
  meta=$(backup_meta_path_for "$id")

  if ! cp -- "$target" "$copy"; then
    die "$EX_PERM" "cannot write into $BACKUP_DIR"
  fi

  file_attributes "$target"

  # The sidecar is written last and moved into place, so that a sidecar always
  # means a complete copy sits beside it.
  {
    printf 'target=%s\n' "$target"
    printf 'time=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'mode=%s\n' "$FILE_MODE"
    printf 'owner=%s\n' "$FILE_OWNER"
    printf 'group=%s\n' "$FILE_GROUP"
    printf 'sha256=%s\n' "$current"
  } >"$meta.tmp"
  mv -f -- "$meta.tmp" "$meta"

  BACKUP_CREATED_ID=$id
  info "took the backup $id in $BACKUP_DIR"

  backup_rotate "$target"

  return 0
}

# Take the automatic backup that precedes a mutation, honouring --no-backup.
backup_before_write() {
  local target=$1

  if ((!OPT_BACKUP)); then
    warn 'writing without a backup'
    return 0
  fi

  backup_create "$target"
}

# Resolve what the user typed into a backup identifier, in BACKUP_RESOLVED_ID.
# Accepts an index as shown by "backup ls", where 1 is the most recent, or an
# identifier in full.
backup_resolve_id() {
  local target=$1 wanted=$2 id
  local -i index

  BACKUP_RESOLVED_ID=''
  backup_list "$target"

  if ((${#BACKUP_IDS[@]} == 0)); then
    die "$EX_NOTFOUND" "there is no backup of $target"
  fi

  if [[ -z $wanted ]]; then
    BACKUP_RESOLVED_ID=${BACKUP_IDS[0]}
    return 0
  fi

  case $wanted in
    '' | *[!0-9]*) ;;
    *)
      index=$wanted
      if ((index < 1 || index > ${#BACKUP_IDS[@]})); then
        die "$EX_NOTFOUND" "there is no backup number $wanted"
      fi
      BACKUP_RESOLVED_ID=${BACKUP_IDS[index - 1]}
      return 0
      ;;
  esac

  for id in "${BACKUP_IDS[@]}"; do
    if [[ $id == "$wanted" ]]; then
      BACKUP_RESOLVED_ID=$id
      return 0
    fi
  done

  die "$EX_NOTFOUND" "there is no backup $wanted of $target"
}
