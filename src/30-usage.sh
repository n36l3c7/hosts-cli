# shellcheck shell=bash
#
# Help and version output.

usage() {
  cat <<EOF
$PROGRAM_NAME - a safe command-line manager for /etc/hosts

Usage:
  $PROGRAM_NAME <command> [options]

Options:
  -h, --help     show this help and exit
  -V, --version  show the version and exit

No command is available yet: this release only provides the packaging and
build scaffolding. See https://github.com/n36l3c7/hosts-cli for the roadmap.

Exit codes:
  0  success
  2  usage error
EOF
}

version() {
  printf '%s %s\n' "$PROGRAM_NAME" "$PROGRAM_VERSION"
}
