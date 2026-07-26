# shellcheck shell=bash
#
# Program identity and the exit code contract.

readonly PROGRAM_NAME='hosts'
readonly PROGRAM_VERSION='@VERSION@'

# Exit codes. These are part of the public interface: a value keeps its meaning
# for the whole 1.x line. Values >= 64 are reserved and never returned.
readonly EX_OK=0          # success, including an idempotent no-op
readonly EX_ERROR=1       # generic or unexpected failure
readonly EX_USAGE=2       # unknown command, unknown option, missing argument
readonly EX_PERM=3        # insufficient permissions
readonly EX_VALIDATION=4  # invalid input, or "check" found errors
readonly EX_NOTFOUND=5    # the requested hostname or entity is not there
readonly EX_CONFLICT=6    # refused because --force was not given
readonly EX_INTEGRITY=7   # write abandoned, the result could not be trusted
readonly EX_ABORTED=8     # the operation was not confirmed

readonly DEFAULT_HOSTS_FILE='/etc/hosts'
readonly DEFAULT_BACKUP_ROOT='/var/backups/hosts'
readonly DEFAULT_BACKUP_KEEP=20

# The sinkhole addresses a blocked domain is pointed at. Both families are
# used, because on a machine with IPv6 a block that only covers IPv4 blocks
# nothing at all.
readonly DEFAULT_BLOCK_ADDRESS_V4='0.0.0.0'
readonly DEFAULT_BLOCK_ADDRESS_V6='::'

# The section blocked domains are kept in. Marking it off means a blocklist of
# tens of thousands of machine written lines can be treated as one thing
# instead of drowning the handful of entries someone actually maintains.
readonly BLOCK_SECTION_OPEN='# >>> hosts block >>>'
readonly BLOCK_SECTION_CLOSE='# <<< hosts block <<<'
readonly BLOCK_SECTION_NOTE='# Managed by hosts(1): change it with "hosts block" and "hosts rm".'

# The schema version of the JSON output. Bumped only on a breaking change.
readonly JSON_SCHEMA_VERSION=1
