# shellcheck shell=bash
#
# Help output, for the program and for each subcommand.

usage() {
  cat <<EOF
$PROGRAM_NAME - a safe command-line manager for /etc/hosts

Usage:
  $PROGRAM_NAME [global options] <command> [arguments]

Reading:
  ls [pattern]        list entries, optionally filtered by a glob on the names
  get <hostname>      print the addresses a hostname points at
  search <text>       find entries by address, name or comment
  check               lint the file
  export              write the file to stdout

Editing:
  add <ip> <name>...  add or update an entry
  rm <name|ip>        remove a name, or every entry for an address
  on <name>           enable the entries carrying a name
  off <name>          disable them without deleting them
  edit                open the file in \$EDITOR and check it on the way back
  import [file]       merge entries from a file, or from standard input
  block <domain>...   point domains at a sinkhole address

Backups:
  backup              take a backup of the file
  backup ls           list the backups already taken
  restore [id]        put a backup back in place, the most recent by default
  diff [id]           compare the file with a backup

Profiles:
  profile save <name> keep the file as it is now, under a name
  profile load <name> bring that state back
  profile ls          list the profiles
  profile rm <name>   delete one

Global options:
  --file <path>       operate on a file other than $DEFAULT_HOSTS_FILE
  --json              machine readable output
  --dry-run           show what would happen, write nothing
  --no-backup         skip the automatic backup, which is a bad idea
  --force             go ahead with something that would otherwise be refused
  -y, --yes           answer yes to the confirmations
  -q, --quiet         silence diagnostics, never the data
  -v, --verbose       print diagnostics about what is being done
  -h, --help          show this help, or the help of a command
  -V, --version       show the version

Every command accepts --help.

Exit codes:
  0  success
  1  generic error
  2  usage error
  3  insufficient permissions
  4  invalid input, or check found errors
  5  the requested hostname or backup is not there
  6  refused because --force was not given
  7  write abandoned, the result could not be trusted
  8  the operation was not confirmed
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

Entries inside the block section are left out unless --blocked is given. A
blocklist is thousands of machine written lines, and showing it by default
would bury the handful of entries you actually maintain. '$PROGRAM_NAME search'
still finds them and '$PROGRAM_NAME get' still resolves them.

Options:
  -a, --all       list active and disabled entries
      --disabled  list only disabled entries
      --blocked   include the entries inside the block section
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

help_add() {
  cat <<EOF
Usage: $PROGRAM_NAME add [options] <address> <hostname>...

Point one or more hostnames at an address. Adding what is already there
changes nothing and succeeds.

Names that are missing from a line that already carries the others, on the
same address, are added to it as aliases; names that are nowhere yet go on a
new line at the end of the file. Names spread over several lines are refused,
because merging lines is a decision for you to make.

A name that already points somewhere else in the same address family is
refused, and --force points it at the new address instead. The same name on
an IPv4 and on an IPv6 address is ordinary dual stack and is never treated as
a clash. A disabled entry for the name is refused too: '$PROGRAM_NAME on' is
usually what was meant, and --force replaces it.

A name that only breaks RFC 1123 by using an underscore is accepted with a
warning, the same judgement '$PROGRAM_NAME check' makes.

Options:
      --dry-run   show the change and write nothing
      --force     go ahead when something is in the way
  -y, --yes       do not ask for confirmation
  -h, --help      show this help

Examples:
  $PROGRAM_NAME add 10.0.0.5 staging staging.local
  $PROGRAM_NAME add --force 10.0.0.9 staging
EOF
}

help_rm() {
  cat <<EOF
Usage: $PROGRAM_NAME rm [options] <hostname|address>

Given a hostname, take it off every line that carries it, active or disabled,
and drop a line that is left with nothing but its address. When the name was
the first on its line, the next one becomes the canonical name.

Given an address, remove every line that points at it. Addresses are compared
as they are written, so ::1 and 0:0:0:0:0:0:0:1 are two different subjects
even though they name one address.

Exits with 5 when nothing matches, so that a typo does not pass for success.

Options:
      --dry-run   show the change and write nothing
  -y, --yes       do not ask for confirmation
  -h, --help      show this help
EOF
}

help_on() {
  cat <<EOF
Usage: $PROGRAM_NAME on [options] <hostname>

Enable every disabled entry carrying the hostname, by removing the hash that
comments it out. Asking for a state that already holds changes nothing and
succeeds.

Options:
      --dry-run   show the change and write nothing
  -y, --yes       do not ask for confirmation
  -h, --help      show this help
EOF
}

help_off() {
  cat <<EOF
Usage: $PROGRAM_NAME off [options] <hostname>

Comment out every active entry carrying the hostname, keeping the line so it
can be brought back with '$PROGRAM_NAME on'.

Every line carrying the name is disabled, not just one. Turning off half of a
dual stack pair would leave the name resolving on the other family, which is a
command doing half its job.

Options:
      --dry-run   show the change and write nothing
  -y, --yes       do not ask for confirmation
  -h, --help      show this help
EOF
}

help_edit() {
  cat <<EOF
Usage: $PROGRAM_NAME edit [options]

Open the file in an editor, check what comes back, and install it atomically
after taking a backup. The editor works on a copy, so the file is never left
half written.

Errors stop the file being installed; warnings are printed and let through,
the same judgement '$PROGRAM_NAME check' makes without --strict.

Your work is never thrown away. When the edited file has errors and there is a
terminal, the editor opens again with the findings shown, the way visudo does
it; without a terminal there is nobody to ask, so the file is left as it was
and the path of your copy is printed.

The editor is \$VISUAL, then \$EDITOR, then vi. It runs with the locale you
had: this program sets LC_ALL=C for its own parsing, which would be the wrong
thing to hand to an editor.

Options:
  -h, --help      show this help
EOF
}

help_import() {
  cat <<EOF
Usage: $PROGRAM_NAME import [options] [file]

Merge entries from a file, or from standard input when no file is given or the
file is -. The format is that of a hosts file.

The source is checked before anything is written, and one bad line makes the
whole import fail: importing half of a broken file leaves a machine in a state
nobody can explain later.

Only active entries are taken; a commented out line in someone else's file is
a note to themselves. An entry is taken or left as a whole. One whose names
all point at the same address already is counted as present, one whose names
are entirely new is added at the end of the file with its comment, and
anything in between is left alone and reported, because a line half imported
would put a name on two lines at once.

Options:
      --dry-run   show the change and write nothing
  -y, --yes       do not ask for confirmation
  -h, --help      show this help

Examples:
  $PROGRAM_NAME import ./hosts.extra
  curl -s https://example.com/hosts | sudo $PROGRAM_NAME import
EOF
}

help_block() {
  cat <<EOF
Usage: $PROGRAM_NAME block [options] <domain>...

Point domains at a sinkhole address, so that they stop resolving.

Both $DEFAULT_BLOCK_ADDRESS_V4 and $DEFAULT_BLOCK_ADDRESS_V6 are used unless
--ipv4-only says otherwise: on a machine with IPv6 a block that only covers
IPv4 blocks nothing at all, which is the mistake most blocklist tools make.

Blocked domains are kept in a section of their own at the end of the file:

  $BLOCK_SECTION_OPEN
  $BLOCK_SECTION_NOTE
  $DEFAULT_BLOCK_ADDRESS_V4$(printf '\t')ads.example.com
  $DEFAULT_BLOCK_ADDRESS_V6$(printf '\t')ads.example.com
  $BLOCK_SECTION_CLOSE

Marking it off means a blocklist of tens of thousands of lines can be treated
as one thing: '$PROGRAM_NAME ls' leaves it out, and '$PROGRAM_NAME check' does
not compare its lines with each other. Nothing about it is magic, so
'$PROGRAM_NAME rm' unblocks a domain like any other entry.

A domain that already has an entry outside the section is skipped with a
warning rather than making the whole command fail, because a command given
many domains should not give up at the first obstacle. This is deliberately
unlike '$PROGRAM_NAME add', which refuses.

Options:
      --ipv4-only  use only $DEFAULT_BLOCK_ADDRESS_V4
      --to <addr>  use this address instead of the two defaults
      --dry-run    show the change and write nothing
  -y, --yes        do not ask for confirmation
  -h, --help       show this help
EOF
}

help_profile() {
  cat <<EOF
Usage: $PROGRAM_NAME profile save <name>
       $PROGRAM_NAME profile load <name>
       $PROGRAM_NAME profile ls
       $PROGRAM_NAME profile rm <name>

Keep the file as it is now under a name, and bring that state back later.

A profile is a snapshot of the whole file, not a set of entries merged into
it: loading one replaces what is there. Saving only reads the file, so it
needs no privilege on it.

A profile and a backup are the same object with different lifetimes. Backups
are taken automatically before every change and rotate away; profiles are made
on purpose and stay until you delete them, which is why they live apart, under
$(profile_root). Everything that makes a
backup safe applies unchanged: the copy is byte for byte, the sidecar records
the file it came from, and the checksum is verified before anything is written.

'profile load' keeps the content it is about to replace, so it can be undone
with '$PROGRAM_NAME restore' like any other change.

Saving over a name that exists is refused unless --force is given: quietly
replacing a state someone chose to keep is the kind of loss this program is
meant to prevent. Deleting one asks first, because nothing else holds a copy.

The output of 'profile ls' is three tab separated fields:

  name <TAB> time <TAB> bytes

Environment:
  HOSTS_PROFILE_DIR   where profiles are kept (default $DEFAULT_PROFILE_ROOT)

Options:
      --dry-run   show what would happen and write nothing
      --force     replace a profile that already exists
  -y, --yes       do not ask for confirmation
  -h, --help      show this help

Examples:
  sudo $PROGRAM_NAME profile save work
  sudo $PROGRAM_NAME profile load home
  $PROGRAM_NAME profile ls
EOF
}

help_backup() {
  cat <<EOF
Usage: $PROGRAM_NAME backup [options]
       $PROGRAM_NAME backup ls [options]

Take a backup of the file, or list the backups already taken. Taking one only
reads the file, so no privilege on it is needed; what is needed is somewhere
to write the copy.

A backup that would be identical to the most recent one is not taken, and the
reason is said under --verbose. Without that, a run of writes that change
nothing would push every backup that matters out of the rotation window.

Backups live in one directory per target file under
$(backup_root), each copy a byte for byte duplicate with a
sidecar of metadata beside it. The copy is deliberately plain, so that in an
emergency the file can be put back with cp. The sidecar records the path the
backup came from, and restore refuses to write it anywhere else.

The output of 'backup ls' is four tab separated fields, the most recent
first:

  index <TAB> id <TAB> time <TAB> bytes

Environment:
  HOSTS_BACKUP_DIR    where backups are kept (default $DEFAULT_BACKUP_ROOT)
  HOSTS_KEEP_BACKUPS  how many to keep per file (default $DEFAULT_BACKUP_KEEP)

Options:
  -h, --help      show this help
EOF
}

help_restore() {
  cat <<EOF
Usage: $PROGRAM_NAME restore [options] [id]

Put a backup back in place. Without an argument the most recent one is used;
otherwise give either the index shown by '$PROGRAM_NAME backup ls', where 1 is
the most recent, or the identifier in full.

Before anything is written the backup is checked against its own checksum, and
against the path it was taken from: a backup made with --file from somewhere
else is never written over this file. The current content is backed up first,
so a restore can itself be undone.

Only the content is restored. Ownership and permissions are those the file has
now, not those it had when the backup was taken; the sidecar records the
original ones for reference.

Options:
      --dry-run   show the difference and write nothing
  -y, --yes       do not ask for confirmation
  -h, --help      show this help
EOF
}

help_diff() {
  cat <<EOF
Usage: $PROGRAM_NAME diff [options] [id]

Compare the file with a backup, the most recent one by default. Removed lines
are what the backup holds, added lines are what the file holds now.

Exits with 0 whether or not there are differences; a non-zero status means the
comparison could not be made.

This is the one command that needs diff, from the diffutils package, and it
says so plainly when it is missing rather than reimplementing it badly.

Options:
  -h, --help      show this help
EOF
}
