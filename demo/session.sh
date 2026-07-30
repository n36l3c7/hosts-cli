#!/usr/bin/env bash
#
# The session recorded into docs/demo.gif.
#
# Every command shown on screen is a command that actually runs, against a
# scratch file in a temporary directory. Nothing is staged for the picture: a
# demo that showed one command and ran another would be the least defensible
# thing in the repository.
#
# It works on ./hosts rather than /etc/hosts because recording needs no root
# and a demo should not be able to damage the machine it is recorded on. That
# the file is named on each command is the honest cost of that.

set -u

readonly DIR_COLOUR=$'\033[36m'
readonly PROMPT_COLOUR=$'\033[32m'
readonly RESET=$'\033[0m'

readonly TYPING_DELAY=0.045
readonly READING_PAUSE=1.4
readonly BEFORE_TYPING=0.5

prompt() {
  printf '%s~/demo%s %s$%s ' \
    "$DIR_COLOUR" "$RESET" "$PROMPT_COLOUR" "$RESET"
}

# Print a line one character at a time, so the recording looks like someone
# typing rather than like a log file scrolling past.
type_out() {
  local text=$1
  local -i i

  prompt
  sleep "$BEFORE_TYPING"
  for ((i = 0; i < ${#text}; i++)); do
    printf '%s' "${text:i:1}"
    sleep "$TYPING_DELAY"
  done
  printf '\n'
}

# Show a command being typed, then run that very command.
demo_run() {
  local -a command=("$@")

  type_out "${command[*]}"
  "${command[@]}" || true
  sleep "$READING_PAUSE"
}

main() {
  # The starting point: a small file, the kind any machine has.
  {
    printf '127.0.0.1\tlocalhost\n'
    printf '::1\t\tlocalhost ip6-localhost\n'
    printf '10.0.0.9\tbuild\n'
  } >hosts

  demo_run hosts --file hosts ls

  demo_run hosts --file hosts add 10.0.0.5 staging staging.local

  demo_run hosts --file hosts ls

  demo_run hosts --file hosts rm staging.local

  demo_run hosts --file hosts ls

  demo_run hosts --file hosts rm staging

  demo_run hosts --file hosts ls

  # Leave the last frame on screen long enough to read. No trailing newline:
  # it would push the cursor onto a line of its own and leave it sitting there
  # under the prompt for the whole of the pause.
  prompt
  sleep 2.5
}

main "$@"
