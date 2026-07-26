# shellcheck shell=bash
#
# JSON serialisation.
#
# The output schema is part of the public interface and is versioned by
# JSON_SCHEMA_VERSION. Bytes outside ASCII are passed through unchanged: they
# are valid UTF-8 JSON and keep comments readable.

JSON_ESCAPED=''
JSON_LITERAL=''

# Escape a string for use inside a JSON string literal, storing the result in
# JSON_ESCAPED.
json_escape() {
  local s=$1

  # The backslash is doubled first, or the escapes introduced below would be
  # escaped a second time.
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\b'/\\b}
  s=${s//$'\f'/\\f}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}

  # Any remaining C0 control byte has no short form and needs \u00XX.
  if [[ $s == *[$'\001'-$'\037']* ]]; then
    local out='' char
    local -i i
    for ((i = 0; i < ${#s}; i++)); do
      char=${s:i:1}
      if [[ $char == [$'\001'-$'\037'] ]]; then
        printf -v char '\\u%04x' "'$char"
      fi
      out+=$char
    done
    s=$out
  fi

  JSON_ESCAPED=$s
}

# Quote a string as a JSON literal, storing the result in JSON_LITERAL.
json_literal() {
  json_escape "$1"
  JSON_LITERAL="\"$JSON_ESCAPED\""
}

# Quote a string as a JSON literal, or produce null when the value is absent.
# Presence is passed separately because a comment that is empty and a comment
# that is missing are different things.
json_literal_or_null() {
  if (($1)); then
    json_literal "$2"
  else
    JSON_LITERAL='null'
  fi
}

# Build a JSON array of strings from the arguments into JSON_LITERAL.
json_literal_array() {
  local item out='[' sep=''
  for item in "$@"; do
    json_escape "$item"
    out+="$sep\"$JSON_ESCAPED\""
    sep=', '
  done
  JSON_LITERAL="$out]"
}
