# shellcheck shell=bash
#
# Entry point, global options and command dispatch.
#
# Global options are accepted before and after the command name, because
# "hosts ls --file x" is what people type even when "hosts --file x ls" is the
# documented order. An option that is not global is handed to the command.

OPT_FILE=$DEFAULT_HOSTS_FILE
OPT_JSON=0
OPT_DRY_RUN=0
OPT_BACKUP=1
OPT_YES=0
OPT_FORCE=0

main() {
  local command=''
  local -a rest=()
  local -i status=0

  while (($#)); do
    case $1 in
      --)
        shift
        if [[ -z $command ]]; then
          if (($#)); then
            command=$1
            shift
          fi
          rest+=("$@")
        else
          # The command has already been named, so this terminator belongs to
          # it and has to survive: it is how an argument starting with a
          # hyphen is passed through.
          rest+=('--' "$@")
        fi
        break
        ;;
      --file)
        (($# >= 2)) || die_usage '' '--file requires a path'
        OPT_FILE=$2
        shift 2
        ;;
      --file=*)
        OPT_FILE=${1#*=}
        shift
        ;;
      --json)
        OPT_JSON=1
        shift
        ;;
      --dry-run)
        OPT_DRY_RUN=1
        shift
        ;;
      --no-backup)
        OPT_BACKUP=0
        shift
        ;;
      -y | --yes)
        OPT_YES=1
        shift
        ;;
      --force)
        OPT_FORCE=1
        shift
        ;;
      -q | --quiet)
        VERBOSITY=0
        shift
        ;;
      -v | --verbose)
        VERBOSITY=2
        shift
        ;;
      -V | --version)
        version
        return "$EX_OK"
        ;;
      -h | --help)
        if [[ -z $command ]]; then
          usage
          return "$EX_OK"
        fi
        rest+=("$1")
        shift
        ;;
      -*)
        if [[ -z $command ]]; then
          die_usage '' "unknown option: $1"
        fi
        rest+=("$1")
        shift
        ;;
      *)
        if [[ -z $command ]]; then
          command=$1
        else
          rest+=("$1")
        fi
        shift
        ;;
    esac
  done

  if [[ -z $command ]]; then
    usage >&2
    return "$EX_USAGE"
  fi

  case $command in
    ls) cmd_ls "${rest[@]}" || status=$? ;;
    get) cmd_get "${rest[@]}" || status=$? ;;
    search) cmd_search "${rest[@]}" || status=$? ;;
    check) cmd_check "${rest[@]}" || status=$? ;;
    export) cmd_export "${rest[@]}" || status=$? ;;
    backup) cmd_backup "${rest[@]}" || status=$? ;;
    restore) cmd_restore "${rest[@]}" || status=$? ;;
    diff) cmd_diff "${rest[@]}" || status=$? ;;
    *) die_usage '' "unknown command: $command" ;;
  esac

  return "$status"
}

# Run only when executed, so that the test suite can source this file and
# exercise individual functions in isolation.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
