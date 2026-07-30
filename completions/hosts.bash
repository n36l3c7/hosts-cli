# shellcheck shell=bash
#
# Bash completion for hosts(1).
#
# Install as .../share/bash-completion/completions/hosts
#
# Values that come from listing a directory, profile names and backup
# identifiers, are always offered: that costs nothing. Hostnames are different,
# because offering them means reading and parsing the file, which on a file
# holding a blocklist of tens of thousands of lines takes seconds and would
# leave the shell looking hung. So they are offered only while the file is
# small enough, counted with wc, which reads but does not parse.

_hosts_commands='ls get search check export add rm on off edit import block
backup restore diff profile flush'

_hosts_global_options='--file --json --dry-run --no-backup --force --yes
--quiet --verbose --help --version'

# The file the command line is pointed at, so that completion follows --file.
_hosts_target_file() {
  local i

  for ((i = 1; i < COMP_CWORD; i++)); do
    case ${COMP_WORDS[i]} in
      --file)
        printf '%s' "${COMP_WORDS[i + 1]:-/etc/hosts}"
        return 0
        ;;
      --file=*)
        printf '%s' "${COMP_WORDS[i]#*=}"
        return 0
        ;;
    esac
  done

  printf '/etc/hosts'
}

# The first word that is neither an option nor the value of one.
_hosts_command_word() {
  local i word skip=0

  for ((i = 1; i < COMP_CWORD; i++)); do
    word=${COMP_WORDS[i]}
    if ((skip)); then
      skip=0
      continue
    fi
    case $word in
      --file)
        skip=1
        ;;
      -*) ;;
      *)
        printf '%s' "$word"
        return 0
        ;;
    esac
  done

  return 0
}

_hosts_hostnames() {
  local file=$1
  local -i limit=${HOSTS_COMPLETION_MAX_LINES:-5000}
  local lines

  [[ -r $file ]] || return 0

  lines=$(wc -l <"$file" 2>/dev/null) || return 0
  ((lines <= limit)) || return 0

  hosts --file "$file" ls --all 2>/dev/null | cut -f2 | tr ' ' '\n'
}

_hosts_profiles() {
  hosts --file "$1" profile ls 2>/dev/null | cut -f1
}

_hosts_backups() {
  hosts --file "$1" backup ls 2>/dev/null | cut -f2
}

_hosts_completions() {
  local current previous command file candidates=''

  current=${COMP_WORDS[COMP_CWORD]}
  previous=${COMP_WORDS[COMP_CWORD - 1]}
  command=$(_hosts_command_word)
  file=$(_hosts_target_file)

  COMPREPLY=()

  # The value of an option, rather than a word of the command line proper.
  case $previous in
    --file)
      mapfile -t COMPREPLY < <(compgen -f -- "$current")
      return 0
      ;;
    --to)
      return 0
      ;;
  esac

  if [[ -z $command ]]; then
    if [[ $current == -* ]]; then
      candidates=$_hosts_global_options
    else
      candidates=$_hosts_commands
    fi
    mapfile -t COMPREPLY < <(compgen -W "$candidates" -- "$current")
    return 0
  fi

  if [[ $current == -* ]]; then
    case $command in
      ls) candidates='--all --disabled --blocked' ;;
      check) candidates='--strict --fix' ;;
      block) candidates='--ipv4-only --to' ;;
      *) candidates='' ;;
    esac
    candidates="$candidates $_hosts_global_options"
    mapfile -t COMPREPLY < <(compgen -W "$candidates" -- "$current")
    return 0
  fi

  case $command in
    get | rm | on | off)
      mapfile -t COMPREPLY < <(compgen -W "$(_hosts_hostnames "$file")" -- "$current")
      ;;
    profile)
      case $previous in
        load | rm)
          mapfile -t COMPREPLY < <(compgen -W "$(_hosts_profiles "$file")" -- "$current")
          ;;
        profile)
          mapfile -t COMPREPLY < <(compgen -W 'save load ls rm' -- "$current")
          ;;
      esac
      ;;
    restore | diff)
      mapfile -t COMPREPLY < <(compgen -W "$(_hosts_backups "$file")" -- "$current")
      ;;
    backup)
      mapfile -t COMPREPLY < <(compgen -W 'ls' -- "$current")
      ;;
    import)
      mapfile -t COMPREPLY < <(compgen -f -- "$current")
      ;;
  esac

  return 0
}

complete -F _hosts_completions hosts
