# shellcheck shell=bash
#
# The atomic write engine.
#
# What is guaranteed: after a write the file holds either the whole of the old
# content or the whole of the new one, never a mixture. That comes from
# rename, which the kernel performs atomically within one filesystem, and it
# holds through a crash or a power cut.
#
# What is not guaranteed: that the new content survives a power cut in the
# moment right after the rename. Bash cannot call fsync, so the directory
# entry cannot be forced to disk. The failure mode of that is finding the old
# file, which is to say a lost change, never a damaged one.

ATOMIC_TMP=''
ATOMIC_TARGET=''
ATOMIC_LOCK_FD=''

# Remove the temporary file if a write was interrupted before it completed.
atomic_cleanup() {
  if [[ -n $ATOMIC_TMP ]]; then
    rm -f -- "$ATOMIC_TMP"
    ATOMIC_TMP=''
  fi
}

# Serialise writers to a file, when the system offers a way that cannot leave
# a stale lock behind.
#
# flock is held by the kernel and released when the process ends, however it
# ends. A lock built from mkdir would have to guess whether a leftover lock
# belongs to a live process, and guessing wrong leaves the tool permanently
# stuck: a worse outcome than the problem, because two concurrent writers can
# only lose an update, never damage the file, the rename being atomic either
# way. So the lock is taken when flock is there and skipped when it is not.
atomic_lock() {
  local target=$1 lock_path

  if ! have_command flock; then
    info 'flock is not available: concurrent writes are not serialised'
    return 0
  fi

  lock_path="${target%/*}/.${target##*/}.lock"

  if ! exec {ATOMIC_LOCK_FD}>>"$lock_path"; then
    info "cannot open $lock_path: concurrent writes are not serialised"
    ATOMIC_LOCK_FD=''
    return 0
  fi

  if ! flock -w 10 "$ATOMIC_LOCK_FD"; then
    die "$EX_ERROR" "another hosts process is holding the lock on $target"
  fi

  return 0
}

# Prepare a write to the given file, leaving the new content to be written
# into the file named by ATOMIC_TMP.
#
# The temporary file is created in the directory of the target, because only
# then is the final move a rename within one filesystem, which is the
# operation the kernel makes atomic. A temporary file in /tmp would turn it
# into a copy, and a copy can be interrupted halfway.
atomic_begin() {
  local target=$1 directory=${1%/*}

  [[ $directory != "$target" ]] || directory='.'

  if [[ ! -w $directory ]]; then
    die "$EX_PERM" "cannot write in $directory: $(write_failure_hint "$target")"
  fi

  if [[ -e $target ]] && has_extended_acl "$target" && ((!OPT_FORCE)); then
    die "$EX_CONFLICT" \
      "$target carries an extended ACL, which a rename cannot preserve; pass --force to write anyway and lose it"
  fi

  ATOMIC_TARGET=$target
  ATOMIC_TMP=$(mktemp -- "$directory/.${target##*/}.XXXXXX") ||
    die "$EX_ERROR" "cannot create a temporary file in $directory"

  trap atomic_cleanup EXIT
  trap 'atomic_cleanup; exit 130' INT
  trap 'atomic_cleanup; exit 143' TERM
}

# Give up on a prepared write, leaving the target untouched.
atomic_abort() {
  atomic_cleanup
  trap - EXIT INT TERM
}

# Install the prepared content over the target. The caller passes the SHA-256
# the new content is meant to have.
atomic_commit() {
  local expected_sha256=$1
  local target=$ATOMIC_TARGET
  local want_owner='' want_group='' want_mode=''

  if [[ -e $target ]]; then
    file_attributes "$target"
    want_owner=$FILE_OWNER
    want_group=$FILE_GROUP
    want_mode=$FILE_MODE

    chown -- "$want_owner:$want_group" "$ATOMIC_TMP" 2>/dev/null || true
    chmod -- "$want_mode" "$ATOMIC_TMP" 2>/dev/null || true

    # A file created in /etc inherits the etc_t SELinux context by type
    # transition, while /etc/hosts is net_conf_t. The rename keeps whatever
    # context the new file has, so it has to be copied across, or a confined
    # service on an enforcing system can stop resolving names.
    if have_command chcon; then
      chcon --reference="$target" -- "$ATOMIC_TMP" 2>/dev/null || true
    fi

    file_attributes "$ATOMIC_TMP"
    if [[ $FILE_OWNER != "$want_owner" || $FILE_GROUP != "$want_group" ||
      $FILE_MODE != "$want_mode" ]]; then
      atomic_abort
      die "$EX_PERM" \
        "cannot give the new file the ownership and permissions of $target"
    fi
  else
    chmod 0644 -- "$ATOMIC_TMP"
  fi

  # Did the bytes that were meant to be written actually land? This catches a
  # truncated write, a filesystem that filled up, and a producer that failed
  # halfway, while the target is still untouched.
  file_sha256 "$ATOMIC_TMP"
  if [[ $FILE_SHA256 != "$expected_sha256" ]]; then
    atomic_abort
    die "$EX_INTEGRITY" \
      "the prepared content does not match what was intended, nothing was written"
  fi

  # Best effort: see the note at the top of this file about what durability
  # can and cannot be promised from bash.
  sync -- "$ATOMIC_TMP" 2>/dev/null || true

  if ! mv -f -- "$ATOMIC_TMP" "$target"; then
    atomic_abort
    die "$EX_ERROR" "cannot install $target: $(write_failure_hint "$target")"
  fi

  ATOMIC_TMP=''
  trap - EXIT INT TERM
}

# Copy a file over the target, atomically. The SHA-256 of the source is
# checked afterwards, so a source that changes underneath is caught.
atomic_install_file() {
  local target=$1 source=$2 expected_sha256=$3

  atomic_lock "$target"
  atomic_begin "$target"

  if ! cp -- "$source" "$ATOMIC_TMP"; then
    atomic_abort
    die "$EX_ERROR" "cannot copy $source"
  fi

  atomic_commit "$expected_sha256"
}
