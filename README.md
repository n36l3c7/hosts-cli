# hosts

A safe command-line manager for `/etc/hosts`.

[![CI](https://github.com/n36l3c7/hosts-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/n36l3c7/hosts-cli/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](CHANGELOG.md)
[![Licence](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

Documentation: <https://n36l3c7.github.io/hosts-cli/>

## What it does

`/etc/hosts` is small enough that everyone edits it by hand, and critical
enough that a corrupted write breaks name resolution on the whole machine.
`hosts` makes the common operations immediate without giving up safety:

- every write goes to a temporary file in the same directory, is validated,
  and is then moved into place with an atomic rename;
- owner, group and permissions of the original file are preserved;
- an automatic, rotated backup is taken before every mutation, so any change
  can be rolled back;
- input is validated before anything touches the file, and invalid input is
  rejected with a dedicated exit code;
- read commands never require root.

It is meant for developers and system administrators who add a local override,
point a hostname at a staging box, or block a domain several times a week.

## Status

This is `0.1.0`: the read-only commands are complete and tested. No command
writes to the file yet.

| Wave | Commands | Status |
| --- | --- | --- |
| 1 | `ls`, `get`, `search`, `check`, `export` | released in 0.1.0 |
| 2 | `backup`, `backup ls`, `restore`, `diff` | next |
| 3 | `add`, `rm`, `on`, `off` | planned |
| 4 | `edit`, `import`, `block` | planned |
| 5 | `profile save`, `profile load`, `profile ls`, `profile rm` | planned |
| 6 | `flush`, shell completions | planned |

## Requirements

- Linux with GNU coreutils.
- Bash 4.4 or newer. The program refuses to run on anything older.
- `diff` (from diffutils) for the `diff` command only, once it lands.

No other runtime dependency: no `jq`, no Python, no external libraries.

## Installation

```sh
git clone https://github.com/n36l3c7/hosts-cli.git
cd hosts-cli
sudo make install
```

This installs the script to `/usr/local/bin/hosts` and the man page to
`/usr/local/share/man/man1/hosts.1`. Override the destination with `PREFIX`
or `DESTDIR`:

```sh
make install PREFIX="$HOME/.local"
```

To remove it:

```sh
sudo make uninstall
```

## Quickstart

```sh
hosts ls                          # every active entry
hosts ls '*.local'                # filtered by a glob on the names
hosts get staging                 # just the address, ready to capture
hosts search "staging box"        # match on address, names or comments
hosts check                       # lint the file
hosts --file ./hosts.new check --strict
man hosts
```

## Commands

| Command | What it does |
| --- | --- |
| `ls [pattern]` | list entries, filtered by a glob on the names |
| `get <hostname>` | print the addresses a hostname points at |
| `search <text>` | find entries by address, name or comment |
| `check` | lint the file |
| `export` | write the file to stdout |

Every command accepts `--help`.

### Global options

Accepted before and after the command name.

| Option | Effect |
| --- | --- |
| `--file <path>` | operate on a file other than `/etc/hosts` |
| `--json` | machine-readable output |
| `-q`, `--quiet` | silence diagnostics, never the data |
| `-v`, `--verbose` | print diagnostics on stderr |
| `-h`, `--help` | show help, general or of a command |
| `-V`, `--version` | show the version |

### Output format

Diagnostics go to stderr, data to stdout. The text output of `ls` and
`search` is four tab-separated fields, always in this order and always this
many, on a terminal exactly as in a pipe:

```
address <TAB> names <TAB> on|off <TAB> comment
```

```
127.0.0.1	localhost	on
10.0.0.5	staging staging.local	on	staging box
192.168.1.40	old-nas	off
```

Nothing is aligned, coloured or paginated, and no option changes the number of
fields, so `cut -f1` is always the address and `awk -F'\t' '$3=="off"'` always
selects the disabled entries.

### `check`

An error is something the resolver will get wrong or silently ignore; a
warning is something untidy or merely suspect. `check` has to be usable in CI
against files it did not write, so anything with a legitimate reading stays a
warning.

| Rule | Severity | Meaning |
| --- | --- | --- |
| `invalid-line` | error | not an address followed by a hostname |
| `invalid-ip` | error | the address does not parse |
| `invalid-hostname` | error | the name breaks RFC 1123 |
| `control-character` | error | the line contains a control character |
| `duplicate-entry` | error | an earlier line is identical |
| `duplicate-name` | warning | the name already points at that address |
| `conflicting-ip` | warning | the name points elsewhere in the same family |
| `nonstandard-hostname` | warning | the name uses an underscore |
| `missing-loopback` | warning | no active `127.0.0.1 localhost` |
| `missing-loopback6` | warning | no active `::1 localhost` |
| `missing-trailing-newline` | warning | the file does not end with a newline |

The same name on an IPv4 and on an IPv6 address is normal dual stack and is
not reported: a rule blind to the address family would flag every healthy
Linux machine. Rules that compare lines ignore disabled entries, which resolve
nothing.

Findings are printed on stdout in the format compilers use, so the error
parser of an editor can consume them directly:

```
/etc/hosts:14: error: duplicate-entry: identical to the entry on line 12
/etc/hosts: warning: missing-loopback6: no active entry maps ::1 to localhost
```

### Addresses and names

Addresses are validated as `inet_pton` does, which is stricter than the
historic `inet_aton`: an octet with a leading zero is rejected rather than
read as octal, because the two readings disagree. An IPv6 zone identifier
(`fe80::1%eth0`) is accepted, because a link-local address without one is
ambiguous.

Hostnames follow RFC 1123. A trailing dot is rejected: an entry in a hosts
file is not a DNS wire name. Comparisons ignore case; the file keeps whatever
case it had.

A commented line is read as a disabled entry when its fields look like one:
an address, at most four names, and every name a plausible hostname. Prose
that happens to start with an address stays a comment.

## Configuration

None yet. Configuration arrives with the commands that need it, through
environment variables (`HOSTS_BACKUP_DIR`, `HOSTS_KEEP_BACKUPS`) and the
global `--file` flag.

## Exit codes

Exit codes are part of the public interface: a value keeps its meaning for the
whole `1.x` line. Values greater than or equal to 64 are reserved and never
returned.

| Code | Meaning |
| --- | --- |
| `0` | Success, including an operation that changed nothing |
| `1` | Generic error, such as a target file that is not there |
| `2` | Usage error: unknown command, unknown option, missing argument |
| `3` | Insufficient permissions to read the file |
| `4` | Invalid input, or `check` found errors |
| `5` | The requested hostname is not in the file |

A missing target file is `1` and not `5` on purpose: `get` uses `5` for a
hostname that is absent, and a script must be able to tell the two apart.

## JSON output

`--json` is accepted by `ls`, `get`, `search`, `check` and `export`. The
schema carries a `version` field and is part of the public interface. Bytes
outside ASCII are passed through unchanged, so comments stay readable.

```json
{
  "version": 1,
  "file": "/etc/hosts",
  "entries": [
    {
      "line": 12,
      "kind": "entry",
      "enabled": true,
      "ip": "10.0.0.5",
      "family": "inet",
      "canonical": "staging",
      "aliases": ["staging.local"],
      "comment": "staging box",
      "raw": "10.0.0.5\tstaging staging.local # staging box"
    }
  ]
}
```

`check --json` replaces `entries` with `summary` and `findings`; `export
--json` reports every line, comments and blank lines included, distinguished
by `kind`.

## Development

The shipped program is a single self-contained script assembled from the
modules in `src/`, so development stays modular while distribution stays a
matter of copying one file. Never edit `build/hosts` directly.

```sh
make build      # assemble build/hosts and build/hosts.1
make lint       # shellcheck on the script, mandoc on the man page
make test       # bats suite, run against the built script
make clean
```

The toolchain is `shellcheck`, `mandoc` and `bats`:

```sh
sudo apt-get install shellcheck mandoc bats
```

The test suite always runs against the built script and against fixture files
passed with `--file`. It never requires root and never touches the real
`/etc/hosts`.

The file is held in parallel arrays, one per field, rather than in serialised
records: field access stays a single array lookup, and there is no separator a
stray byte could collide with. Every line keeps its original text, so a later
rewrite can leave untouched lines exactly as they were.

### Performance

| File | `ls` | `check` |
| --- | --- | --- |
| a typical `/etc/hosts`, 10 lines | 21 ms | 23 ms |
| a 50,000-line blocklist | 7.5 s | 10 s |

For the size `/etc/hosts` actually is, the tool is instant. A blocklist of tens
of thousands of entries is not: Bash costs roughly 150 µs per line whatever the
parser does, and no tuning inside the loop changes that order of magnitude.
Bulk handling of blocklists arrives with `block` and `import`, which will use a
single `awk` pass where it wins.

Two changes did move the number, and both came out of measurement rather than
intuition. `read <<<` was replaced with word splitting, because a here-string
is not a builtin and Bash writes it to a temporary file first. Glob patterns
replaced regular expressions, because Bash recompiles an expression on every
match. Together they took the 50,000-line case from 38 s to 7.5 s.

## Contributing

Work is delivered in waves: one coherent slice of functionality per pull
request, squash merged so that each wave lands as exactly one commit. Open a
pull request only once CI is green, and state in its body the scope, the
rationale, and how to test the change.

## Licence

MIT, see [LICENSE](LICENSE).
