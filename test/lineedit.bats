#!/usr/bin/env bats
#
# Surgical edits to a single line.
#
# The property under test is that an edit changes what it was asked to change
# and nothing else, whitespace included: a line rebuilt from its parsed fields
# would show up in the diff as a change nobody asked for.

load helper

# Run one of the line editing functions and print what it produced, with tabs
# made visible so an assertion can pin them.
edited() {
  run --separate-stderr bash -c "source '$HOSTS_BIN'
$1 \"\$1\" \"\$2\"
printf '%s\n' \"\$LINE_RESULT\"" line-edit "$2" "${3:-}"
}

@test "removing a name keeps the separator that follows the address" {
  edited line_remove_name "$(printf '10.0.0.5    staging   staging.local')" staging
  [ "$status" -eq 0 ]
  [ "$output" = '10.0.0.5    staging.local' ]
}

@test "removing the last name keeps the separator before the ones that stay" {
  edited line_remove_name "$(printf '10.0.0.5    staging   staging.local')" staging.local
  [ "$status" -eq 0 ]
  [ "$output" = '10.0.0.5    staging' ]
}

@test "a tab between the address and the names survives a removal" {
  edited line_remove_name "$(printf '10.0.0.5\tstaging staging.local')" staging
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '10.0.0.5\tstaging.local')" ]
}

@test "a trailing comment survives a removal" {
  edited line_remove_name "$(printf '10.0.0.5\tstaging api\t# staging box')" api
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '10.0.0.5\tstaging\t# staging box')" ]
}

@test "indentation survives a removal" {
  edited line_remove_name "$(printf '  10.0.0.5 staging api')" api
  [ "$status" -eq 0 ]
  [ "$output" = '  10.0.0.5 staging' ]
}

@test "removing a name that is not on the line fails" {
  edited line_remove_name '10.0.0.5 staging' nowhere
  [ "$status" -ne 0 ]
}

@test "the address is never taken for a name" {
  edited line_remove_name '10.0.0.5 staging' 10.0.0.5
  [ "$status" -ne 0 ]
}

@test "removing a name ignores case" {
  edited line_remove_name '10.0.0.5 staging API' api
  [ "$status" -eq 0 ]
  [ "$output" = '10.0.0.5 staging' ]
}

@test "a name is added after the ones already there" {
  edited line_add_name "$(printf '10.0.0.5\tstaging')" api
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '10.0.0.5\tstaging api')" ]
}

@test "a name is added before the trailing comment" {
  edited line_add_name "$(printf '10.0.0.5\tstaging\t# box')" api
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '10.0.0.5\tstaging api\t# box')" ]
}

@test "changing the address leaves the layout alone" {
  edited line_set_address "$(printf '10.0.0.5    staging   staging.local\t# box')" 10.0.0.9
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '10.0.0.9    staging   staging.local\t# box')" ]
}

@test "disabling and enabling a line is an exact round trip" {
  run --separate-stderr bash -c "source '$HOSTS_BIN'
line_disable \"\$1\"
line_enable \"\$LINE_RESULT\"
printf '%s\n' \"\$LINE_RESULT\"" round-trip "$(printf '  10.0.0.5    staging   staging.local\t# box')"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '  10.0.0.5    staging   staging.local\t# box')" ]
}

@test "disabling puts the hash after the indentation" {
  edited line_disable '  10.0.0.5 staging'
  [ "$status" -eq 0 ]
  [ "$output" = '  # 10.0.0.5 staging' ]
}

@test "enabling a line commented by hand without a space works too" {
  edited line_enable '#10.0.0.5 staging'
  [ "$status" -eq 0 ]
  [ "$output" = '10.0.0.5 staging' ]
}

@test "a new entry separates the address from the names with a tab" {
  run --separate-stderr bash -c "source '$HOSTS_BIN'
line_new_entry 10.0.0.5 staging staging.local
printf '%s\n' \"\$LINE_RESULT\"" new-entry
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '10.0.0.5\tstaging staging.local')" ]
}
