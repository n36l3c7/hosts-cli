# shellcheck shell=bash
#
# Surgical edits to a single line of the file.
#
# A line is never rebuilt from its parsed fields. Rebuilding would turn
# "10.0.0.5    staging   staging.local" into "10.0.0.5<TAB>staging
# staging.local" and show up as a change to a line nobody asked to touch. So
# the original text is edited in place instead: the token is found, and it is
# removed together with exactly one run of adjacent whitespace.

LINE_RESULT=''
declare -a LINE_SEPARATORS=()
declare -a LINE_TOKENS=()
LINE_TAIL=''
LINE_LEAD=''
LINE_MARKER=''
LINE_COMMENT=''
LINE_BODY=''
LINE_NAMES_LEFT=0

# Take a raw line apart into the pieces an edit has to leave alone: the
# indentation, the hash that disables it if there is one, the entry itself,
# and the trailing comment. The entry is left in LINE_BODY.
line_split() {
  local raw=$1 rest

  LINE_LEAD=${raw%%[![:space:]]*}
  rest=${raw#"$LINE_LEAD"}

  LINE_MARKER=''
  if [[ $rest == '#'* ]]; then
    rest=${rest#\#}
    LINE_MARKER='#'
    # Whitespace after the hash belongs to the marker, so that re-enabling a
    # line gives back exactly what was there before.
    local spacing=${rest%%[![:space:]]*}
    LINE_MARKER+=$spacing
    rest=${rest#"$spacing"}
  fi

  LINE_COMMENT=''
  if [[ $rest == *'#'* ]]; then
    LINE_COMMENT=${rest#*\#}
    LINE_COMMENT="#$LINE_COMMENT"
    rest=${rest%%\#*}
  fi

  LINE_BODY=$rest
}

# Split the entry into alternating runs of whitespace and tokens, so that an
# edit can put back everything it did not mean to change.
line_scan() {
  local text=$1 separator token

  LINE_SEPARATORS=()
  LINE_TOKENS=()
  LINE_TAIL=''

  while [[ -n $text ]]; do
    separator=${text%%[![:space:]]*}
    text=${text#"$separator"}
    if [[ -z $text ]]; then
      LINE_TAIL=$separator
      break
    fi
    token=${text%%[[:space:]]*}
    text=${text#"$token"}
    LINE_SEPARATORS+=("$separator")
    LINE_TOKENS+=("$token")
  done
}

# Put a scanned entry back together.
line_join() {
  local out=''
  local -i i

  for i in "${!LINE_TOKENS[@]}"; do
    out+="${LINE_SEPARATORS[i]}${LINE_TOKENS[i]}"
  done

  printf -v LINE_BODY '%s%s' "$out" "$LINE_TAIL"
}

# Rebuild a whole line from the pieces line_split produced.
line_assemble() {
  LINE_RESULT="$LINE_LEAD$LINE_MARKER$LINE_BODY$LINE_COMMENT"
}

# Remove a name from a line, leaving the rest of its layout untouched. Fails
# when the name is not on the line. LINE_NAMES_LEFT says how many names remain.
line_remove_name() {
  local raw=$1 name=${2,,}
  local -i i target=-1 last

  line_split "$raw"
  line_scan "$LINE_BODY"

  for ((i = 1; i < ${#LINE_TOKENS[@]}; i++)); do
    if [[ ${LINE_TOKENS[i],,} == "$name" ]]; then
      target=$i
      break
    fi
  done

  ((target >= 0)) || return 1

  # The separator that follows the name is the one to drop, so that whatever
  # separated the address from the names survives; for the last name there is
  # no following separator, so the preceding one goes instead.
  last=$((${#LINE_TOKENS[@]} - 1))
  if ((target < last)); then
    unset 'LINE_SEPARATORS[target + 1]'
  else
    unset 'LINE_SEPARATORS[target]'
  fi
  unset 'LINE_TOKENS[target]'

  LINE_SEPARATORS=("${LINE_SEPARATORS[@]}")
  LINE_TOKENS=("${LINE_TOKENS[@]}")
  LINE_NAMES_LEFT=$((${#LINE_TOKENS[@]} - 1))

  line_join
  line_assemble
  return 0
}

# Add a name to the end of the names on a line.
line_add_name() {
  local raw=$1 name=$2

  line_split "$raw"
  line_scan "$LINE_BODY"

  LINE_SEPARATORS+=(' ')
  LINE_TOKENS+=("$name")

  line_join
  line_assemble
}

# Replace the address of a line, which is the one edit that is meant to change
# how the line looks.
line_set_address() {
  local raw=$1 address=$2

  line_split "$raw"
  line_scan "$LINE_BODY"

  ((${#LINE_TOKENS[@]} > 0)) || return 1
  LINE_TOKENS[0]=$address

  line_join
  line_assemble
  return 0
}

# Comment a line out, keeping its indentation so that enabling it again gives
# back what was there.
line_disable() {
  local raw=$1 lead
  lead=${raw%%[![:space:]]*}
  LINE_RESULT="$lead# ${raw#"$lead"}"
}

# Uncomment a line. One space after the hash is taken to belong to the hash,
# which is what makes disabling and enabling a line an exact round trip.
line_enable() {
  local raw=$1 lead rest
  lead=${raw%%[![:space:]]*}
  rest=${raw#"$lead"}
  rest=${rest#\#}
  rest=${rest# }
  LINE_RESULT="$lead$rest"
}

# Build a brand new entry. A single tab between the address and the names is
# what the files shipped by Debian and Ubuntu use.
line_new_entry() {
  local address=$1
  shift
  LINE_RESULT="$address"$'\t'"$*"
}
