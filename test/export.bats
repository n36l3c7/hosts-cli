#!/usr/bin/env bats
#
# hosts export.

load helper

@test "export reproduces the file byte for byte" {
  make_fixture <<'EOF'
# Static table lookup for hostnames.
127.0.0.1	localhost

10.0.0.5   staging staging.local    # staging box
# 192.168.1.40 old-nas
EOF
  run --separate-stderr bash -c "'$HOSTS_BIN' --file '$FIXTURE' export | cmp - '$FIXTURE'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "export preserves a missing final newline" {
  printf '127.0.0.1 localhost' >"$FIXTURE"
  run --separate-stderr bash -c "'$HOSTS_BIN' --file '$FIXTURE' export | cmp - '$FIXTURE'"
  [ "$status" -eq 0 ]
}

@test "export of an empty file produces nothing" {
  : >"$FIXTURE"
  hosts_run export
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "export --json reports comments and blank lines too" {
  make_fixture <<'EOF'
# a comment

10.0.0.5 staging
EOF
  hosts_run --json export
  [ "$status" -eq 0 ]
  [[ $output == *'"kind": "comment",'* ]]
  [[ $output == *'"kind": "blank",'* ]]
  [[ $output == *'"kind": "entry",'* ]]
  [[ $output == *'"line": 3,'* ]]
}

@test "a non entry line has null address fields and no aliases" {
  make_fixture <<'EOF'
# a comment
EOF
  hosts_run --json export
  [ "$status" -eq 0 ]
  [[ $output == *'"ip": null,'* ]]
  [[ $output == *'"family": null,'* ]]
  [[ $output == *'"canonical": null,'* ]]
  [[ $output == *'"aliases": [],'* ]]
}

@test "export takes no argument" {
  make_fixture <<'EOF'
127.0.0.1 localhost
EOF
  hosts_run export something
  [ "$status" -eq 2 ]
  [[ $stderr == *'takes no argument'* ]]
}
