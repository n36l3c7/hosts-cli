# shellcheck shell=bash
#
# Help output, for the program and for each subcommand.

usage() {
  cat <<EOF
$PROGRAM_NAME - a safe command-line manager for /etc/hosts

Usage:
  $PROGRAM_NAME [global options] <command> [arguments]

Commands:
  ls [pattern]        list entries, optionally filtered by a glob on the names
  get <hostname>      print the addresses a hostname points at
  search <text>       find entries by address, name or comment
  check               lint the file
  export              write the file to stdout

Global options:
  --file <path>       operate on a file other than $DEFAULT_HOSTS_FILE
  --json              machine readable output
  -q, --quiet         silence diagnostics, never the data
  -v, --verbose       print diagnostics about what is being done
  -h, --help          show this help, or the help of a command
  -V, --version       show the version

Every command accepts --help. This release is read only: no command writes to
the file.

Exit codes:
  0  success
  1  generic error
  2  usage error
  3  insufficient permissions
  4  invalid input, or check found errors
  5  the requested hostname is not in the file
EOF
}

version() {
  printf '%s %s\n' "$PROGRAM_NAME" "$PROGRAM_VERSION"
}

help_ls() {
  cat <<EOF
Usage: $PROGRAM_NAME ls [options] [pattern]

List the entries of the file. With a pattern, only entries with a name
matching that shell glob are listed; matching ignores case. Quote the pattern
so that the shell does not expand it first.

Options:
  -a, --all       list active and disabled entries
      --disabled  list only disabled entries
  -h, --help      show this help

Output is four tab separated fields, always in this order and always this
many, on a terminal as in a pipe:

  address <TAB> names <TAB> on|off <TAB> comment

Examples:
  $PROGRAM_NAME ls
  $PROGRAM_NAME ls '*.local'
  $PROGRAM_NAME ls --all | cut -f1,2
EOF
}

help_get() {
  cat <<EOF
Usage: $PROGRAM_NAME get [options] <hostname>

Print the addresses the given hostname points at, one per line and nothing
else, so that the result can be captured directly:

  address=\$($PROGRAM_NAME get staging)

Only active entries are considered, because a commented out entry takes no
part in name resolution. The match is exact and ignores case. More than one
address can be printed, typically one IPv4 and one IPv6.

Exits with 5 when the hostname is not in the file.

Options:
  -h, --help      show this help
EOF
}

help_search() {
  cat <<EOF
Usage: $PROGRAM_NAME search [options] <text>

Find entries whose address, names or comment contain the given text. Matching
is on substrings and ignores case. Disabled entries are included: when you are
searching you want to find them, and the state field says which is which.

The output format is the one of '$PROGRAM_NAME ls'.

Options:
  -h, --help      show this help
EOF
}

help_check() {
  cat <<EOF
Usage: $PROGRAM_NAME check [options]

Lint the file and report what is wrong with it, in the format compilers use:

  <file>:<line>: <severity>: <rule>: <message>

An error is something the resolver will get wrong or silently ignore; a
warning is something untidy or merely suspect. Findings go to stdout: they are
the data this command produces.

Rules:
  invalid-line              error    not an address followed by a hostname
  invalid-ip                error    the address does not parse
  invalid-hostname          error    the name breaks RFC 1123
  control-character         error    the line contains a control character
  duplicate-entry           error    an earlier line is identical
  duplicate-name            warning  the name already points at that address
  conflicting-ip            warning  the name points elsewhere in the same family
  nonstandard-hostname      warning  the name uses an underscore
  missing-loopback          warning  no 127.0.0.1 localhost
  missing-loopback6         warning  no ::1 localhost
  missing-trailing-newline  warning  the file does not end with a newline

The same name on an IPv4 and on an IPv6 address is normal dual stack and is
not reported. Cross line rules ignore disabled entries, which resolve nothing.

Exits with 4 when there is at least one error, or with --strict when there is
at least one warning.

Options:
      --strict    treat warnings as errors
  -h, --help      show this help
EOF
}

help_export() {
  cat <<EOF
Usage: $PROGRAM_NAME export [options]

Write the file to stdout. Without --json this reproduces it byte for byte,
comments, blank lines and a missing final newline included. With --json it
emits every line, entries and comments alike, as a structured document.

Options:
  -h, --help      show this help
EOF
}
