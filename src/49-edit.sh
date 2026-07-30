# shellcheck shell=bash
#
# A change to the file, expressed as a list of edits over line numbers.
#
# Nothing rebuilds the file from the parsed model. A change says which lines
# it replaces, which it deletes and what it appends, and everything else is
# written back exactly as it was read. Lines nobody touched stay identical by
# construction, not by care: there is no path through this code that could
# reformat one.

declare -A EDIT_REPLACE=()
declare -A EDIT_DELETE=()
declare -A EDIT_INSERT=()
declare -a EDIT_APPEND=()
EDIT_INSERTED=0
EDIT_TRAILING_NEWLINE=0

edit_reset() {
  EDIT_REPLACE=()
  EDIT_DELETE=()
  EDIT_INSERT=()
  EDIT_APPEND=()
  EDIT_INSERTED=0
  EDIT_TRAILING_NEWLINE=0
}

edit_replace() {
  EDIT_REPLACE[$1]=$2
}

edit_delete() {
  EDIT_DELETE[$1]=1
}

edit_append() {
  EDIT_APPEND+=("$1")
}

# Put a line before the one at the given index. Several lines can be queued
# for the same place and come out in the order they were added.
edit_insert_before() {
  local -i index=$1
  local text=$2

  if [[ -n ${EDIT_INSERT[$index]:-} ]]; then
    EDIT_INSERT[$index]+=$'\n'$text
  else
    EDIT_INSERT[$index]=$text
  fi
  EDIT_INSERTED=$((EDIT_INSERTED + 1))
}

# Give the file the final newline it is missing. This is the only change that
# alters no line of it, so it counts as one of its own: without that, a file
# whose sole fault is the missing newline would look like nothing to do.
edit_end_with_newline() {
  EDIT_TRAILING_NEWLINE=1
}

# How many lines of the file the change touches. Used to decide whether an
# operation is narrow enough to go ahead without asking.
edit_touched() {
  printf '%s' "$((${#EDIT_REPLACE[@]} + ${#EDIT_DELETE[@]} +
    ${#EDIT_APPEND[@]} + EDIT_INSERTED + EDIT_TRAILING_NEWLINE))"
}

edit_is_empty() {
  ((${#EDIT_REPLACE[@]} + ${#EDIT_DELETE[@]} +
    ${#EDIT_APPEND[@]} + EDIT_INSERTED + EDIT_TRAILING_NEWLINE == 0))
}

# Write the result of the change to a file.
edit_render() {
  local out=$1 line
  local -i i last=-1 ends_without_newline=0

  for ((i = 0; i < _hf_count; i++)); do
    [[ -z ${EDIT_DELETE[$i]:-} ]] || continue
    last=$i
  done

  # A file that did not end with a newline keeps that, unless something is
  # appended: appending to such a file means giving it the newline it lacked.
  if ((!_hf_trailing_newline && ${#EDIT_APPEND[@]} == 0 &&
    !EDIT_TRAILING_NEWLINE)); then
    ends_without_newline=1
  fi

  {
    for ((i = 0; i < _hf_count; i++)); do
      if [[ -n ${EDIT_INSERT[$i]:-} ]]; then
        printf '%s\n' "${EDIT_INSERT[$i]}"
      fi

      [[ -z ${EDIT_DELETE[$i]:-} ]] || continue

      if [[ -n ${EDIT_REPLACE[$i]+set} ]]; then
        line=${EDIT_REPLACE[$i]}
      else
        line=${_hf_raw[i]}
      fi

      if ((i == last && ends_without_newline)); then
        printf '%s' "$line"
      else
        printf '%s\n' "$line"
      fi
    done

    for line in "${EDIT_APPEND[@]}"; do
      printf '%s\n' "$line"
    done
  } >"$out"
}

# Apply the change: nothing at all when it is empty, a preview under --dry-run,
# and otherwise a backup followed by an atomic write.
edit_commit() {
  local target=$1 description=$2
  local expected_sha256
  local -i touched

  if edit_is_empty; then
    info 'nothing to change'
    return "$EX_OK"
  fi

  block_prune_if_empty

  touched=$(edit_touched)

  ATOMIC_SCRATCH=$(mktemp) || die "$EX_ERROR" 'cannot create a temporary file'
  trap atomic_cleanup EXIT
  trap 'atomic_cleanup; exit 130' INT
  trap 'atomic_cleanup; exit 143' TERM

  edit_render "$ATOMIC_SCRATCH"
  file_sha256 "$ATOMIC_SCRATCH" expected_sha256

  if ((OPT_DRY_RUN)); then
    edit_show_difference "$target" "$ATOMIC_SCRATCH"
    info "would $description, touching $touched line(s) of $target"
    atomic_cleanup
    trap - EXIT INT TERM
    return "$EX_OK"
  fi

  # Narrow operations go ahead; a change that reaches across several lines is
  # worth a question first.
  if ((touched > 1)); then
    confirm "$description, touching $touched lines of $target?"
  fi

  if ((!_hf_trailing_newline && ${#EDIT_APPEND[@]} > 0)); then
    info "$target did not end with a newline; adding one to append to it"
  fi

  backup_before_write "$target"
  atomic_install_file "$target" "$ATOMIC_SCRATCH" "$expected_sha256"

  atomic_cleanup
  trap - EXIT INT TERM

  info "$description, touching $touched line(s) of $target"

  return "$EX_OK"
}

# Show what a change would do, when there is a tool to show it with.
edit_show_difference() {
  local target=$1 rendered=$2

  if ! have_command diff; then
    info 'diff is not installed, so the change cannot be shown'
    return 0
  fi

  diff -u --label "$target" --label "$target (after)" -- "$target" "$rendered" ||
    true

  return 0
}
