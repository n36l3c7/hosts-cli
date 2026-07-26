# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/n36l3c7/hosts-cli/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/n36l3c7/hosts-cli/releases/tag/v0.0.1
