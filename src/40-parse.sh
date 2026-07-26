# shellcheck shell=bash
#
# Parsing of a hosts file.
#
# The file is held in parallel arrays rather than in serialised records: field
# access stays a single array lookup on files with tens of thousands of lines,
# and there is no separator that a stray byte in the file could collide with.
#
# There is one element per line of the file, so the array index and the line
# number differ only by one, and the original line is always kept verbatim so
# that a later rewrite can leave untouched lines exactly as they were.

declare -a _hf_raw=()      # the line as read, byte for byte
declare -a _hf_kind=()     # entry | comment | blank | invalid
declare -a _hf_enabled=()  # 1 for an active entry, 0 otherwise
declare -a _hf_ip=()       # empty unless kind is entry
declare -a _hf_family=()   # inet | inet6, empty unless kind is entry
declare -a _hf_names=()    # names separated by a space, canonical first
declare -a _hf_comment=()  # trailing comment, without the leading '#'
declare -a _hf_has_comment=()
declare -a _hf_reason=()   # why a line was rejected, empty unless invalid

# Lookup index from a lowercased name to the array positions carrying it,
# as a list separated by a space.
declare -A _hf_by_name=()

_hf_path=''
_hf_count=0
_hf_trailing_newline=1

# Result of parse_line, and of the record accessors at the end of this file.
PARSED_KIND=''
PARSED_ENABLED=0
PARSED_IP=''
PARSED_FAMILY=''
PARSED_NAMES=''
PARSED_COMMENT=''
PARSED_HAS_COMMENT=0
PARSED_REASON=''
declare -a PARSED_NAME_LIST=()
RECORD_CANONICAL=''
declare -a RECORD_NAMES=()

# The largest number of names a commented line may carry and still be read as
# a disabled entry. Prose that starts with an address, such as
# "# 10.0.0.5 is the old address of the staging box", is made entirely of
# words that are valid hostnames, so name validity alone cannot tell it apart
# from a real entry; the length of the list can. Real entries are short: the
# longest in a stock Debian or Ubuntu file carries three names.
readonly MAX_DISABLED_ENTRY_NAMES=4

# Split a line into its parts, storing the result in the PARSED_* variables.
# Every line of the file produces a result, so this never fails.
parse_line() {
  local line=$1 body uncommented

  PARSED_KIND=''
  PARSED_ENABLED=0
  PARSED_IP=''
  PARSED_FAMILY=''
  PARSED_NAMES=''
  PARSED_COMMENT=''
  PARSED_HAS_COMMENT=0
  PARSED_REASON=''

  body=${line#"${line%%[![:space:]]*}"}

  if [[ -z $body ]]; then
    PARSED_KIND='blank'
    return 0
  fi

  if [[ $body == '#'* ]]; then
    # A commented line may be an entry that was disabled rather than deleted,
    # so it is worth trying to read one out of it.
    uncommented=${body#\#}
    uncommented=${uncommented#"${uncommented%%[![:space:]]*}"}
    if _parse_entry "$uncommented" 1; then
      PARSED_KIND='entry'
      PARSED_ENABLED=0
      return 0
    fi
    PARSED_KIND='comment'
    PARSED_COMMENT=${body#\#}
    PARSED_HAS_COMMENT=1
    return 0
  fi

  if _parse_entry "$body" 0; then
    PARSED_KIND='entry'
    PARSED_ENABLED=1
    return 0
  fi

  PARSED_KIND='invalid'
  return 0
}

# Try to read "address name [name...] [# comment]" out of a line of text.
# With commented set, the stricter rules described above are applied, because
# the text is only a candidate entry.
_parse_entry() {
  local text=$1 commented=$2
  local comment='' name
  local -i has_comment=0
  local -a fields=()

  if [[ $text == *'#'* ]]; then
    comment=${text#*\#}
    text=${text%%\#*}
    has_comment=1
  fi

  # The split has to be copied out at once: the validators below split too,
  # and they share the same buffer.
  split_on_whitespace "$text"
  fields=("${FIELDS[@]}")

  if ((${#fields[@]} < 2)); then
    PARSED_REASON='no-address-and-name'
    return 1
  fi

  if ! classify_address "${fields[0]}"; then
    PARSED_REASON='bad-address'
    return 1
  fi

  if ((commented)); then
    if ((${#fields[@]} - 1 > MAX_DISABLED_ENTRY_NAMES)); then
      return 1
    fi
    for name in "${fields[@]:1}"; do
      is_lenient_hostname "$name" || return 1
    done
  fi

  PARSED_IP=${fields[0]}
  PARSED_FAMILY=$_ADDRESS_FAMILY
  PARSED_NAME_LIST=("${fields[@]:1}")
  PARSED_NAMES=${fields[*]:1}
  PARSED_COMMENT=$comment
  PARSED_HAS_COMMENT=$has_comment
  return 0
}

# Read a hosts file into the arrays above and build the lookup index.
hostsfile_load() {
  local path=$1 line=''
  local -i index=0

  [[ -e $path ]] || die "$EX_ERROR" "no such file: $path"
  [[ -f $path ]] || die "$EX_ERROR" "not a regular file: $path"
  [[ -r $path ]] || die "$EX_PERM" "cannot read $path: permission denied"

  _hf_path=$path
  _hf_raw=()
  _hf_kind=()
  _hf_enabled=()
  _hf_ip=()
  _hf_family=()
  _hf_names=()
  _hf_comment=()
  _hf_has_comment=()
  _hf_reason=()
  _hf_by_name=()
  _hf_trailing_newline=1

  while IFS= read -r line; do
    _hf_store "$line" "$index"
    index+=1
  done <"$path"

  # read leaves the final line in the variable without returning success when
  # the file does not end with a newline.
  if [[ -n $line ]]; then
    _hf_trailing_newline=0
    _hf_store "$line" "$index"
    index+=1
  fi

  _hf_count=$index
  info "read $_hf_count lines from $path"
}

# Parse one line and append it to the arrays, updating the index.
_hf_store() {
  local line=$1 name
  local -i index=$2

  parse_line "$line"

  _hf_raw[index]=$line
  _hf_kind[index]=$PARSED_KIND
  _hf_enabled[index]=$PARSED_ENABLED
  _hf_ip[index]=$PARSED_IP
  _hf_family[index]=$PARSED_FAMILY
  _hf_names[index]=$PARSED_NAMES
  _hf_comment[index]=$PARSED_COMMENT
  _hf_has_comment[index]=$PARSED_HAS_COMMENT
  _hf_reason[index]=$PARSED_REASON

  [[ $PARSED_KIND == 'entry' ]] || return 0

  # The names were already split out by the parse, so they are reused rather
  # than split a second time.
  for name in "${PARSED_NAME_LIST[@]}"; do
    name=${name,,}
    _hf_by_name[$name]="${_hf_by_name[$name]:-}${_hf_by_name[$name]:+ }$index"
  done
}

# Store the names of a record in the RECORD_NAMES array.
record_names() {
  local -i index=$1
  split_on_whitespace "${_hf_names[index]}"
  RECORD_NAMES=("${FIELDS[@]}")
}

# Store the canonical name of a record, the first one on the line, in
# RECORD_CANONICAL.
record_canonical() {
  local all_names=${_hf_names[$1]}
  RECORD_CANONICAL=${all_names%% *}
}
