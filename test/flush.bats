#!/usr/bin/env bats
#
# hosts flush.
#
# The command reaches outside the file, so these tests give it a PATH holding
# nothing but scripted stand-ins. Real resolvers cannot be started or stopped
# from a test suite and should not be, and the machine running the suite may
# well have one of them installed, which would otherwise decide the answer.
#
# flush needs no external command of its own beyond id, so a PATH of only the
# fakes is enough; bash is linked in because the shebang looks it up there.

load helper

# Start from an empty PATH holding only what the program needs to run, and a
# root id, so that the permission check is not what is under test.
isolate() {
  FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN"
  ln -sf "$(command -v bash)" "$FAKE_BIN/bash"
  fake_id 0
}

# id reports the given user id, whatever it is asked.
fake_id() {
  printf '#!/bin/bash\necho %d\n' "$1" >"$FAKE_BIN/id"
  chmod +x "$FAKE_BIN/id"
}

# A stand-in resolver command that exits with the given status.
fake_command() {
  printf '#!/bin/bash\nexit %d\n' "${2:-0}" >"$FAKE_BIN/$1"
  chmod +x "$FAKE_BIN/$1"
}

flush_run() {
  run --separate-stderr env -i PATH="$FAKE_BIN" "$HOSTS_BIN" "$@"
}

@test "with no caching resolver it says so and succeeds" {
  # The C library has no cache of its own, so there is genuinely nothing to
  # do, and that is not a failure.
  isolate
  flush_run flush
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ ${lines[0]} == 'none'$'\t''nothing-to-flush'$'\t'* ]]
  [[ ${lines[0]} == *'glibc does not cache'* ]]
}

@test "systemd-resolved is flushed when it answers" {
  isolate
  fake_command resolvectl 0
  flush_run flush
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'systemd-resolved\tflushed\t')" ]
}

@test "a resolver that is installed but not running is reported, not an error" {
  isolate
  fake_command resolvectl 1
  flush_run flush
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'systemd-resolved\tnot-running\t')" ]
}

@test "nscd is flushed too, and both are reported" {
  isolate
  fake_command resolvectl 0
  fake_command nscd 0
  flush_run flush
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ ${lines[0]} == 'systemd-resolved'$'\t''flushed'* ]]
  [[ ${lines[1]} == 'nscd'$'\t''flushed'* ]]
}

@test "dnsmasq is reported with the command, and never reloaded" {
  # Reloading it can drop the network of the machine, which is worse than a
  # stale cache entry and not what anybody expects from a flush.
  isolate
  fake_command dnsmasq 0
  flush_run flush
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == 'dnsmasq'$'\t''needs-attention'$'\t'* ]]
  [[ ${lines[0]} == *'systemctl reload dnsmasq'* ]]
}

@test "--force does not make it reload a resolver either" {
  isolate
  fake_command dnsmasq 0
  flush_run --force flush
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == 'dnsmasq'$'\t''needs-attention'* ]]
}

@test "unbound and BIND are reported the same way" {
  isolate
  fake_command unbound-control 0
  fake_command rndc 0
  flush_run flush
  [ "$status" -eq 0 ]
  [[ $output == *'unbound'$'\t''needs-attention'* ]]
  [[ $output == *'bind'$'\t''needs-attention'* ]]
}

@test "--dry-run names what would be run and runs nothing" {
  isolate
  # An exit status of 1 would mean not running; --dry-run must not call it.
  fake_command resolvectl 1
  flush_run --dry-run flush
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'systemd-resolved\twould-flush\tresolvectl flush-caches')" ]
}

@test "without root and with something to flush it says to use sudo" {
  isolate
  fake_id 1000
  fake_command resolvectl 0
  flush_run flush
  [ "$status" -eq 3 ]
  [[ $stderr == *'needs root'* ]]
  [[ $stderr == *'sudo'* ]]
}

@test "without root and with nothing to flush it still succeeds" {
  isolate
  fake_id 1000
  flush_run flush
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == 'none'$'\t''nothing-to-flush'* ]]
}

@test "without root, --dry-run still says what it would do" {
  isolate
  fake_id 1000
  fake_command resolvectl 0
  flush_run --dry-run flush
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == 'systemd-resolved'$'\t''would-flush'* ]]
}

@test "flush --json reports every resolver it looked at" {
  isolate
  fake_command resolvectl 0
  flush_run --json flush
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = '{' ]
  [ "${lines[1]}" = '  "version": 1,' ]
  [[ $output == *'"name": "systemd-resolved",'* ]]
  [[ $output == *'"status": "flushed",'* ]]
}

@test "flush takes no argument" {
  isolate
  flush_run flush something
  [ "$status" -eq 2 ]
}
