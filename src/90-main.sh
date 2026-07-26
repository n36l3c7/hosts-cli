# shellcheck shell=bash
#
# Entry point and command dispatch.

main() {
  if (($# == 0)); then
    usage >&2
    return "$EX_USAGE"
  fi

  case $1 in
    -h | --help)
      usage
      return "$EX_OK"
      ;;
    -V | --version)
      version
      return "$EX_OK"
      ;;
    *)
      err "unknown command or option: $1"
      err "run '$PROGRAM_NAME --help' for usage"
      return "$EX_USAGE"
      ;;
  esac
}

# Run only when executed, so that the test suite can source this file and
# exercise individual functions in isolation.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
