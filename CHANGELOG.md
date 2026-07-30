# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Every released version is installable from the apt repository, not only the
  most recent one. `dpkg-scanpackages` reports one version per package unless
  told otherwise, so earlier `.deb` files were being published and then left
  out of the index: present but not installable, which is not what "the index
  is rebuilt from every release" was meant to mean.

## [1.0.1] - 2026-07-30

Verification of what 1.0.0 already claimed, and one claim that turned out not
to be true.

### Fixed

- Concurrent writers no longer lose each other's work. The lock was taken
  inside the write, after the file had already been read, so two writers each
  computed their change from the same starting point and the second one
  discarded the first. Serialising the writes prevented nothing, the rename
  having already made those indivisible: the update that got lost was lost
  during the read. The lock is now taken before the file is read and held
  until the new content is in place. 0.2.0 documented the protection this
  provides; it did not provide it.
- `hosts edit` holds that lock for as long as the editor is open, so another
  writer waits and then fails saying so rather than quietly discarding one of
  the two changes.
- The apt index is rebuilt after a release again. It was chained to the
  release event, which a release created by a workflow using the built-in
  token never raises: GitHub suppresses those so that workflows cannot
  trigger each other in a loop. It now chains to the release workflow itself,
  which is the mechanism meant for it. The index for 1.0.0 was published by
  running the workflow by hand.

### Added

- Tests that kill a write partway through, at a different point on each pass,
  and require the file to hold either the whole of the old content or the
  whole of the new one. That guarantee is the one the whole program rests on
  and had only ever been reasoned about.
- A test that runs two writers at once against a file large enough for the
  race to be certain rather than merely possible. It is what found the lock
  defect above.
- Tests that put the parser against input it was not written for: control
  bytes, addresses and names that nearly parse, lines of only whitespace, and
  a very long line. Three invariants are checked, the strongest being that
  `export` gives back exactly the bytes that were read. The generator is
  seeded so a failure can be reproduced. Nothing was found, which is also
  information.
- A portability job that runs the whole suite on Debian 11 and 12 and Ubuntu
  22.04 and 24.04, as an ordinary user rather than as root so that the tests
  about refused permissions do not skip themselves. Everything had until now
  only ever run on one Ubuntu, which left every assumption about `stat`,
  `date`, `realpath`, `sync`, `flock` and `install` untested.

### Changed

- The README no longer implies bash 4.4 is tested. It is the documented floor;
  what the suite runs against is bash 5.1 and 5.2, because nothing still
  supported ships 4.4.
- A test no longer expects a file to come out mode 644. Debian defaults to a
  umask of 022 and Ubuntu to 002, so the same fixture is 644 on one and 664 on
  the other; the sidecar records the mode the file actually has, which is what
  the test now checks. The portability job found this on its first run, which
  is the sort of thing it was added for.

## [1.0.0] - 2026-07-27

The first release that can be installed with `apt`, and the point from which
the interface is a promise.

Nothing in the program itself changed from 0.6.0. What changed is that there
is now a way to install it that does not begin with cloning a repository, and
a commitment about what will not break.

### Added

- A Debian package, `hosts-cli`, holding the command, the man page and the
  completions for bash and zsh. `make deb` builds it from the same artifacts
  `make install` uses.
- An APT repository published on GitHub Pages, signed, and rebuilt from the
  packages attached to every GitHub Release so that it holds no state of its
  own and cannot drift from what was published.
- A release workflow that runs on a tag, refuses to continue when the tag and
  the `VERSION` file disagree, installs the package it just built and uses it
  before publishing anything, and takes the release notes from this file.

### Changed

- GitHub Pages is deployed by a workflow rather than from the `docs` folder of
  the branch, because an APT repository contains a binary and committing one
  would put it in the history for good.
- The following are now covered by semantic versioning, and breaking any of
  them costs a major version: the exit codes 0 to 8; the tab separated output
  of `ls`, `search`, `check`, `backup ls`, `profile ls` and `flush`, the number
  of fields included; the JSON schema; the rule identifiers of `check`; the
  environment variables and the layout of the backup and profile stores,
  sidecar format included.

## [0.6.0] - 2026-07-27

`flush` and shell completions. The planned command surface is complete.

### Added

- `flush`, clearing the cache of the system resolver. It performs only the
  flushes that cannot disturb anything, systemd-resolved and nscd, and reports
  dnsmasq, unbound and BIND with the command that would reload them rather
  than reloading them: restarting a resolver can drop the network of the
  machine, which is worse than a stale cache entry and not what anybody
  expects from a command called flush. `--force` does not change that.
- Completions for bash and zsh, installed by `make install` into
  `share/bash-completion/completions` and `share/zsh/site-functions`.
- `HOSTS_COMPLETION_MAX_LINES`, defaulting to 5000.
- `zsh` in the lint job, so that the syntax check of the zsh completion
  actually runs rather than skipping itself.

### Changed

- Finding no caching resolver is a success, not a failure, and `flush` says
  why: the C library has no DNS cache of its own, so without a caching daemon
  a change to the file is already in effect.
- Completion offers profile names and backup identifiers always, since that
  means listing a directory, but hostnames only while the file is under the
  limit: producing them means parsing the file, which on a large blocklist
  takes seconds and would leave the shell looking hung.

## [0.5.0] - 2026-07-27

Profiles: named states of the file that can be brought back later.

### Added

- `profile save`, `profile load`, `profile ls` and `profile rm`. A profile is
  a snapshot of the whole file, not a set of entries merged into it.
- `HOSTS_PROFILE_DIR`, defaulting to `/var/lib/hosts/profiles`.
- Profile names are checked before they become filenames: letters, digits,
  dot, dash and underscore only, not starting with a dot or a dash, at most 64
  characters. That is a question of safety, not of tidiness.

### Changed

- A profile reuses the backup machinery unchanged: the byte for byte copy, the
  sidecar recording the file it was taken from, and the checksum verified
  before anything is written. What differs is the lifetime, so the two are
  kept in separate directories and rotation cannot reach a profile without
  having to know anything about it.
- `profile load` keeps the content it replaces, so it can be undone with
  `restore` like any other change. Saving over a name that exists is refused
  without `--force`, and deleting a profile asks first.

## [0.4.1] - 2026-07-27

No change in behaviour. Every command, option, exit code and output format is
what it was in 0.4.0.

### Changed

- Functions that produce a value now put it in a variable the caller names,
  instead of in one they share. Three bugs in the first five releases had the
  same shape: a caller read a shared result variable after calling something
  else that had written to it in the meantime, and got a perfectly valid value
  belonging to another file. Naming the destination removes the shared
  variable and with it that whole class of mistake. The parser keeps its
  shared buffers, where the cost of a fresh variable per line was measured and
  found to matter; everywhere else it costs nothing.
- Locals in those functions are prefixed with an underscore. A local sharing
  its name with the variable a caller asked to fill shadows it, and the result
  then quietly never arrives; the prefix makes that impossible rather than
  merely unlikely.

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

[Unreleased]: https://github.com/n36l3c7/hosts-cli/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/n36l3c7/hosts-cli/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/n36l3c7/hosts-cli/compare/v0.6.0...v1.0.0
[0.6.0]: https://github.com/n36l3c7/hosts-cli/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/n36l3c7/hosts-cli/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/n36l3c7/hosts-cli/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/n36l3c7/hosts-cli/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/n36l3c7/hosts-cli/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/n36l3c7/hosts-cli/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/n36l3c7/hosts-cli/compare/v0.0.1...v0.1.0
[0.0.1]: https://github.com/n36l3c7/hosts-cli/releases/tag/v0.0.1
