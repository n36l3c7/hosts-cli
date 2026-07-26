#!/usr/bin/env bats
#
# Splitting a single line into its parts.

load helper

# Report the parse result of a line as a single pipe separated record, so that
# one assertion can pin every field at once. The line is passed as an argument
# rather than interpolated into the script, so any content is safe.
parsed() {
  run --separate-stderr bash -c "source '$HOSTS_BIN'
parse_line \"\$1\"
printf '%s|%s|%s|%s|%s|%s|%s\n' \"\$PARSED_KIND\" \"\$PARSED_ENABLED\" \\
  \"\$PARSED_IP\" \"\$PARSED_FAMILY\" \"\$PARSED_NAMES\" \\
  \"\$PARSED_HAS_COMMENT\" \"\$PARSED_COMMENT\"" parse-line "$1"
}

# Report only the kind and the reason a line was rejected.
parsed_reason() {
  run --separate-stderr bash -c "source '$HOSTS_BIN'
parse_line \"\$1\"
printf '%s|%s\n' \"\$PARSED_KIND\" \"\$PARSED_REASON\"" parse-line "$1"
}

@test "a blank line is blank" {
  parsed ""
  [ "$status" -eq 0 ]
  [ "$output" = "blank|0||||0|" ]
}

@test "a whitespace only line is blank" {
  parsed "   "
  [ "${output%%|*}" = 'blank' ]
}

@test "a plain entry is read into its parts" {
  parsed "10.0.0.5 staging staging.local"
  [ "$output" = "entry|1|10.0.0.5|inet|staging staging.local|0|" ]
}

@test "leading whitespace and tabs between fields are accepted" {
  parsed "$(printf '\t  10.0.0.5\t\tstaging  staging.local  ')"
  [ "$output" = "entry|1|10.0.0.5|inet|staging staging.local|0|" ]
}

@test "a trailing comment is separated from the names" {
  parsed "10.0.0.5 staging # staging box"
  [ "$output" = "entry|1|10.0.0.5|inet|staging|1| staging box" ]
}

@test "a comment needs no space before it" {
  parsed "10.0.0.5 staging#note"
  [ "$output" = "entry|1|10.0.0.5|inet|staging|1|note" ]
}

@test "an IPv6 entry is recognised" {
  parsed "::1 localhost ip6-localhost"
  [ "$output" = "entry|1|::1|inet6|localhost ip6-localhost|0|" ]
}

@test "a commented entry is a disabled entry" {
  parsed "# 192.168.1.40 old-nas"
  [ "$output" = "entry|0|192.168.1.40|inet|old-nas|0|" ]
}

@test "a commented entry without a space after the hash is still an entry" {
  parsed "#192.168.1.40 old-nas"
  [ "$output" = "entry|0|192.168.1.40|inet|old-nas|0|" ]
}

@test "a disabled entry keeps its own trailing comment" {
  parsed "# 192.168.1.40 old-nas # decommissioned"
  [ "$output" = "entry|0|192.168.1.40|inet|old-nas|1| decommissioned" ]
}

@test "a prose comment that starts with an address is not an entry" {
  # Every word here is a syntactically valid hostname, so name validity alone
  # cannot tell this apart from a disabled entry; the length of the list can.
  parsed "# 10.0.0.5 is the old address of the staging box"
  [ "${output%%|*}" = 'comment' ]
}

@test "a commented line with more names than an entry ever carries is a comment" {
  parsed "# 10.0.0.5 one two three four five"
  [ "${output%%|*}" = 'comment' ]
}

@test "a commented line at the name limit is still an entry" {
  parsed "# 10.0.0.5 one two three four"
  [ "${output%%|*}" = 'entry' ]
}

@test "an ordinary comment is a comment" {
  parsed "# Static table lookup for hostnames."
  [ "${output%%|*}" = 'comment' ]
}

@test "a doubly commented entry stays a comment" {
  parsed "## 192.168.1.40 old-nas"
  [ "${output%%|*}" = 'comment' ]
}

@test "a line with an address but no name is invalid" {
  parsed_reason "203.0.113.7"
  [ "$output" = 'invalid|no-address-and-name' ]
}

@test "a line whose first field is not an address is invalid" {
  parsed_reason "999.1.1.1 bogus"
  [ "$output" = 'invalid|bad-address' ]
}

@test "a name that breaks RFC 1123 still parses as an entry" {
  # The resolver will read the line, so the program has to see it too; saying
  # that the name is wrong is the job of check, not of the parser.
  parsed "10.0.0.11 -badname"
  [ "$output" = "entry|1|10.0.0.11|inet|-badname|0|" ]
}
