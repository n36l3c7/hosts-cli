# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-07-27

`edit`, `import` and `block`.

### Added

- `edit`, opening the file in an editor and checking what comes back. Errors
  stop it being installed and warnings do not. The work is never thrown away:
  with a terminal the editor opens again with the findings shown, the way
  `visudo` does it, and without one the path of the copy is printed.
- `import`, merging entries from a file or from standard input. The source is
  checked before anything is written, and one bad line makes the whole import
  fail. An entry is taken or left as a whole.
- `block`, pointing domains at a sinkhole address, with the domains read from
  standard input when none are given. Both `0.0.0.0` and `::` are used unless
  `--ipv4-only` says otherwise, because on a machine with IPv6 a block that
  only covers IPv4 blocks nothing at all. `--to` names another address.
- A marked-off section holding blocked domains, so that a blocklist of tens of
  thousands of machine written lines can be treated as one thing. Its markers
  go away with the last entry in it.
- `ls --blocked`, to include the entries inside that section.

### Changed

- `ls` leaves the block section out by default, so that the entries someone
  actually maintains are not buried under a generated list. `get` still
  resolves what is in it and `search` still finds it.
- `check` no longer compares the lines inside the block section with each
  other, since near identical generated names would produce nothing but
  noise. The per line rules still apply to them.
- The editor started by `edit` runs with the locale the user had. The program
  sets `LC_ALL=C` for its own parsing, which is the wrong thing to hand to an
  editor about to be shown someone else's text.

## [0.3.0] - 2026-07-27

Editing entries: `add`, `rm`, `on` and `off`, on top of the write engine of
0.2.0.

### Added

- `add`, pointing names at an address. Adding what is already there changes
  nothing. A missing name joins the line that already carries the others on
  the same address; names that are nowhere go on a new line. Names spread over
  several lines are refused, because merging them is the user's decision.
- `rm`, taking a name off every line that carries it and dropping a line left
  with nothing but its address, or removing every line pointing at an address.
  Exits with 5 when nothing matches, so a typo does not pass for success.
- `on` and `off`, enabling and disabling entries without deleting them.
- Help for each of the new commands, and examples in the man page.

### Changed

- A change is expressed as a list of edits over line numbers instead of a
  rebuild of the file, and within a line a name is removed together with one
  run of adjacent whitespace. Lines nobody asked to touch come out byte for
  byte identical, and `off` followed by `on` gives back the original line
  exactly.
- The same name on an IPv4 and on an IPv6 address is treated as dual stack
  everywhere, never as a clash: `add` accepts it and `check` already did.
- `off`, `on` and `rm` act on every line carrying the name rather than
  refusing when there is more than one. Acting on one line of a dual stack
  pair would leave the name resolving on the other family, and refusing to
  choose would fail on the correct hosts file of every Linux machine.
- A change reaching more than one line asks for confirmation; a change to a
  single line does not.

## [0.2.0] - 2026-07-27

The atomic write engine and the backup store. `restore` is the first command
that writes to the file; no command edits an entry yet.

### Added

- `backup` and `backup ls`, taking and listing byte-for-byte copies with a
  sidecar of metadata. Taking one only reads the file, so it needs no
  privilege on it.
- `restore`, putting a backup back in place by index or by identifier, after
  verifying its checksum and the path it was taken from, and after backing up
  the content it is about to replace.
- `diff`, comparing the file with a backup.
- Global options `--dry-run`, `--no-backup`, `--force` and `-y`/`--yes`.
- Exit codes 6, 7 and 8 added to the contract: refused without `--force`,
  write abandoned, and operation not confirmed.
- `HOSTS_BACKUP_DIR` and `HOSTS_KEEP_BACKUPS`.
- The written guarantee that a change leaves the file holding either the whole
  of the old content or the whole of the new one, and the equally explicit
  statement that surviving a power cut immediately after the rename is not
  promised, because Bash cannot call `fsync`.
- Owner, group, permissions and SELinux context are carried over to the new
  file before it is installed. Without copying the context across, a file
  written into `/etc` keeps `etc_t` instead of `net_conf_t`, and a confined
  service on an SELinux system can stop resolving names.
- A file carrying an extended ACL is refused with exit 6 unless `--force` is
  given, because a rename cannot preserve one and losing it changes who may
  read and write the file.
- Writers are serialised with `flock` where it exists. A lock built from
  `mkdir` was considered and rejected: it would have to guess whether a
  leftover lock belongs to a live process, and guessing wrong leaves the tool
  stuck for good, which is worse than the problem it solves.
- A symbolic link given to `--file` is followed, so a write lands where it
  points instead of replacing the link with a regular file.

## [0.1.0] - 2026-07-27

The read-only commands. Nothing writes to the file yet, and no command needs
any privilege beyond being able to read it.

### Added

- `ls`, listing entries with an optional case-insensitive glob over the names,
  and `--all` and `--disabled` to select by state.
- `get`, printing the addresses a hostname points at, one per line and nothing
  else. Only active entries resolve; exits with 5 when the name is absent.
- `search`, matching substrings against address, names and comments, disabled
  entries included.
- `check`, linting the file with eleven rules split into errors and warnings,
  reported in the format compilers use, with `--strict` to fail on warnings.
- `export`, reproducing the file byte for byte, or emitting every line as a
  structured document with `--json`.
- Global options `--file`, `--json`, `-q`/`--quiet` and `-v`/`--verbose`,
  accepted before and after the command name, and a `--help` per command.
- A versioned JSON schema, part of the public interface, for `ls`, `get`,
  `search`, `check` and `export`.
- Address validation matching `inet_pton`, rejecting octets with a leading
  zero, and accepting an IPv6 zone identifier.
- Hostname validation following RFC 1123, with the underscore reported as a
  warning rather than an error because container tooling generates such names
  in large numbers.
- Exit codes 1, 3, 4 and 5 added to the contract, alongside 0 and 2.

### Changed

- The file is parsed into parallel arrays, one per field, keeping every line
  verbatim so a later rewrite can leave untouched lines exactly as they were.
- `LC_ALL=C` is set, so character ranges and case conversion behave the same
  on every machine, and pathname expansion is disabled program wide, so a
  stray asterisk in the file cannot turn into a list of filenames when a line
  is split into fields.
- Field splitting uses word splitting instead of `read <<<`, and validation
  uses glob patterns instead of regular expressions: a here-string is not a
  builtin and is written to a temporary file, and Bash recompiles a regular
  expression on every match. A 50,000-line file went from 38 s to 7.5 s.

## [0.0.1] - 2026-07-26

Scaffolding release: build, packaging, documentation and continuous
integration, with no entry management command yet.

### Added

- Build system assembling the modules in `src/` into a single self-contained
  `build/hosts` script, with the version injected from the `VERSION` file.
- `Makefile` with `build`, `install`, `uninstall`, `lint`, `test`, `clean` and
  `help` targets, honouring `PREFIX` and `DESTDIR`.
- `--help` and `--version`, and the first two entries of the exit code
  contract: `0` for success and `2` for a usage error.
- Man page `hosts(1)`, generated from `man/hosts.1.in` and installed by
  `make install`.
- Test suite based on bats, covering the command line surface and the build
  artifacts, run against the built script.
- Continuous integration on GitHub Actions: `shellcheck` on the assembled
  script and `mandoc -T lint` on the man page, plus the bats suite.
- Documentation site under `docs/`, published with GitHub Pages.
- README, changelog and MIT licence.

[Unreleased]: https://github.com/n36l3c7/hosts-cli/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/n36l3c7/hosts-cli/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/n36l3c7/hosts-cli/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/n36l3c7/hosts-cli/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/n36l3c7/hosts-cli/compare/v0.0.1...v0.1.0
[0.0.1]: https://github.com/n36l3c7/hosts-cli/releases/tag/v0.0.1
