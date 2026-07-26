# hosts

A safe command-line manager for `/etc/hosts`.

[![CI](https://github.com/n36l3c7/hosts-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/n36l3c7/hosts-cli/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-0.0.1-blue.svg)](CHANGELOG.md)
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

This is the `0.0.1` scaffolding release: build, packaging, documentation and
continuous integration are in place, but no entry management command is
implemented yet. Only `--help` and `--version` do anything.

The planned command surface, delivered one wave at a time:

| Wave | Commands |
| --- | --- |
| 1 | `ls`, `get`, `search`, `check`, `export` |
| 2 | `backup`, `backup ls`, `restore`, `diff` |
| 3 | `add`, `rm`, `on`, `off` |
| 4 | `edit`, `import`, `block` |
| 5 | `profile save`, `profile load`, `profile ls`, `profile rm` |
| 6 | `flush`, shell completions |

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
hosts --version
hosts --help
man hosts
```

## Configuration

None yet. Configuration will be introduced with the commands that need it,
through environment variables (`HOSTS_BACKUP_DIR`, `HOSTS_KEEP_BACKUPS`) and
the global `--file` flag.

## Exit codes

Exit codes are part of the public interface: a value keeps its meaning for the
whole `1.x` line. Values greater than or equal to 64 are reserved and never
returned. Codes are documented here as the commands that raise them land.

| Code | Meaning |
| --- | --- |
| `0` | Success, including an idempotent operation that changed nothing |
| `2` | Usage error: unknown command, unknown option, missing argument |

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

## Contributing

Work is delivered in waves: one coherent slice of functionality per pull
request, squash merged so that each wave lands as exactly one commit. Open a
pull request only once CI is green, and state in its body the scope, the
rationale, and how to test the change.

## Licence

MIT, see [LICENSE](LICENSE).
