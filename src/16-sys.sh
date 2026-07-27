# shellcheck shell=bash
#
# Probes of the system the program is running on.
#
# Everything platform specific is kept here, so that supporting another system
# later means rewriting this file and nothing else.
#
# These hand their result back through a variable the caller names, rather
# than through one of their own. Three bugs in the first five releases had the
# same shape: a caller read a shared result variable after calling something
# else that had written to it in the meantime, and got a perfectly valid value
# belonging to another file. Naming the destination removes the shared
# variable, and with it that whole class of mistake. The parser keeps its
# shared buffers, where the cost of a fresh variable per line was measured and
# found to matter; here it costs nothing.

# Succeed when a command is available.
have_command() {
  command -v -- "$1" >/dev/null 2>&1
}

# Store the SHA-256 of a file in the variable named by the second argument.
file_sha256() {
  local -n _out_sha256=$2
  local _output
  _output=$(sha256sum -- "$1") || return 1
  _out_sha256=${_output%% *}
}

# Store the SHA-256 of a string in the variable named by the second argument.
string_sha256() {
  local -n _out_string_sha256=$2
  local _output
  _output=$(printf '%s' "$1" | sha256sum) || return 1
  _out_string_sha256=${_output%% *}
}

# Store the absolute path of a file, with symbolic links resolved.
#
# On some systems the hosts file is a symbolic link. An atomic rename onto the
# link would replace it with a regular file and quietly undo that arrangement,
# so the link is followed first and the write lands where it points.
resolve_path() {
  local -n _out_path=$2
  local _resolved
  _resolved=$(realpath -- "$1") || return 1
  _out_path=$_resolved
}

# Store the owner, group and permissions of a file in the three variables
# named by the caller.
file_attributes() {
  local -n _out_owner=$2
  local -n _out_group=$3
  local -n _out_mode=$4
  local _output
  local -a _parts=()

  _output=$(stat -c '%U %G %a' -- "$1") || return 1
  split_on_whitespace "$_output"
  _parts=("${FIELDS[@]}")

  _out_owner=${_parts[0]}
  _out_group=${_parts[1]}
  _out_mode=${_parts[2]}
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

# Store a sortable UTC timestamp with millisecond resolution.
#
# The fraction is padded here rather than with the width specifier of date:
# that specifier turns the zero padding off instead of applying it, so a
# nanosecond value below one hundred million comes out a digit short and the
# identifiers stop sorting chronologically.
timestamp_id() {
  local -n _out_timestamp=$1
  local _raw _fraction _seconds

  _raw=$(date -u '+%Y%m%dT%H%M%S %N') || return 1
  split_on_whitespace "$_raw"
  _seconds=${FIELDS[0]}
  _fraction=${FIELDS[1]:-}

  case $_fraction in
    '' | *[!0-9]*)
      _fraction='000'
      ;;
    *)
      printf -v _fraction '%09d' "$((10#$_fraction))"
      _fraction=${_fraction:0:3}
      ;;
  esac

  _out_timestamp="$_seconds.${_fraction}Z"
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
