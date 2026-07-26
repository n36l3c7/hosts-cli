# shellcheck shell=bash
#
# Probes of the system the program is running on.
#
# Everything platform specific is kept here, so that supporting another system
# later means rewriting this file and nothing else.

FILE_SHA256=''
STRING_SHA256=''
FILE_OWNER=''
FILE_GROUP=''
FILE_MODE=''
RESOLVED_PATH=''
TIMESTAMP_ID=''

# Succeed when a command is available.
have_command() {
  command -v -- "$1" >/dev/null 2>&1
}

# Store the SHA-256 of a file in FILE_SHA256.
file_sha256() {
  local output
  output=$(sha256sum -- "$1") || return 1
  FILE_SHA256=${output%% *}
}

# Store the SHA-256 of a string in STRING_SHA256.
string_sha256() {
  local output
  output=$(printf '%s' "$1" | sha256sum) || return 1
  STRING_SHA256=${output%% *}
}

# Store the absolute path of a file, with symbolic links resolved, in
# RESOLVED_PATH.
#
# On some systems the hosts file is a symbolic link. An atomic rename onto the
# link would replace it with a regular file and quietly undo that arrangement,
# so the link is followed first and the write lands where it points.
resolve_path() {
  RESOLVED_PATH=$(realpath -- "$1") || return 1
}

# Store the owner, group and permissions of a file in FILE_OWNER, FILE_GROUP
# and FILE_MODE.
file_attributes() {
  local output
  output=$(stat -c '%U %G %a' -- "$1") || return 1
  split_on_whitespace "$output"
  FILE_OWNER=${FIELDS[0]}
  FILE_GROUP=${FIELDS[1]}
  FILE_MODE=${FIELDS[2]}
}

# Succeed when a file carries an extended ACL.
#
# The trailing plus sign of ls is the indicator, rather than getfacl, because
# getfacl comes from a package that is not installed everywhere while ls is
# always there.
has_extended_acl() {
  local listing
  listing=$(ls -ld -- "$1") || return 1
  [[ ${listing%% *} == *+ ]]
}

# Store a sortable UTC timestamp with millisecond resolution in TIMESTAMP_ID.
#
# The fraction is padded here rather than with the width specifier of date:
# that specifier turns the zero padding off instead of applying it, so a
# nanosecond value below one hundred million comes out a digit short and the
# identifiers stop sorting chronologically.
timestamp_id() {
  local raw fraction

  raw=$(date -u '+%Y%m%dT%H%M%S %N') || return 1
  split_on_whitespace "$raw"
  fraction=${FIELDS[1]:-}

  case $fraction in
    '' | *[!0-9]*)
      fraction='000'
      ;;
    *)
      printf -v fraction '%09d' "$((10#$fraction))"
      fraction=${fraction:0:3}
      ;;
  esac

  TIMESTAMP_ID="${FIELDS[0]}.${fraction}Z"
}

# Describe why writing to a path failed, in the cases where the reason is not
# obvious from the error the kernel gives.
write_failure_hint() {
  local target=$1 attributes

  if have_command lsattr; then
    attributes=$(lsattr -d -- "$target" 2>/dev/null) || attributes=''
    if [[ -n $attributes && ${attributes%% *} == *i* ]]; then
      printf 'the file is marked immutable, chattr -i clears that'
      return 0
    fi
  fi

  printf 'permission denied'
}
