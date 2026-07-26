#!/usr/bin/env bats
#
# JSON serialisation. A comment in a hosts file can hold any byte, so escaping
# is the part of the output path most likely to produce a broken document.

load helper

# Escape a string and print the result. The value is passed as an argument so
# that no content can disturb the surrounding script.
escaped() {
  run --separate-stderr bash -c "source '$HOSTS_BIN'
json_escape \"\$1\"
printf '%s\n' \"\$JSON_ESCAPED\"" json-escape "$1"
}

@test "ordinary text is left alone" {
  escaped 'staging box'
  [ "$output" = 'staging box' ]
}

@test "a double quote is escaped" {
  escaped 'say "hello"'
  [ "$output" = 'say \"hello\"' ]
}

@test "a backslash is doubled" {
  escaped 'C:\path'
  [ "$output" = 'C:\\path' ]
}

@test "a backslash is doubled before other escapes are introduced" {
  # Escaping in the wrong order turns \t into \\t and corrupts the document.
  escaped "$(printf 'a\\\tb')"
  [ "$output" = 'a\\\tb' ]
}

@test "a tab uses its short form" {
  escaped "$(printf 'a\tb')"
  [ "$output" = 'a\tb' ]
}

@test "a carriage return uses its short form" {
  escaped "$(printf 'a\rb')"
  [ "$output" = 'a\rb' ]
}

@test "other control bytes use the \\u form" {
  escaped "$(printf 'a\033b\001c')"
  [ "$output" = 'a\u001bb\u0001c' ]
}

@test "bytes outside ASCII are passed through unchanged" {
  # They are valid UTF-8 JSON and escaping them would only make comments
  # unreadable.
  escaped 'caffè – naïve'
  [ "$output" = 'caffè – naïve' ]
}

@test "json_literal wraps the escaped value in quotes" {
  run --separate-stderr bash -c "source '$HOSTS_BIN'
json_literal 'a\"b'
printf '%s\n' \"\$JSON_LITERAL\"" json-literal
  [ "$output" = '"a\"b"' ]
}

@test "json_literal_or_null distinguishes an empty value from a missing one" {
  run --separate-stderr bash -c "source '$HOSTS_BIN'
json_literal_or_null 1 ''
printf '%s\n' \"\$JSON_LITERAL\"
json_literal_or_null 0 ''
printf '%s\n' \"\$JSON_LITERAL\"" json-or-null
  [ "${lines[0]}" = '""' ]
  [ "${lines[1]}" = 'null' ]
}

@test "json_literal_array builds an array, empty included" {
  run --separate-stderr bash -c "source '$HOSTS_BIN'
json_literal_array
printf '%s\n' \"\$JSON_LITERAL\"
json_literal_array one two
printf '%s\n' \"\$JSON_LITERAL\"" json-array
  [ "${lines[0]}" = '[]' ]
  [ "${lines[1]}" = '["one", "two"]' ]
}
