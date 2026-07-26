# shellcheck shell=bash
#
# Program identity and the exit code contract.

readonly PROGRAM_NAME='hosts'
readonly PROGRAM_VERSION='@VERSION@'

# Exit codes. These are part of the public interface: a value keeps its meaning
# for the whole 1.x line. Values >= 64 are reserved and never returned.
readonly EX_OK=0        # success, including an idempotent no-op
readonly EX_USAGE=2     # unknown subcommand, unknown flag, missing argument
