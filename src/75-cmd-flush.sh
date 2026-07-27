# shellcheck shell=bash
#
# hosts flush - clear the cache of the system resolver.
#
# The fact this command is built around: glibc has no DNS cache of its own. On
# a machine with no caching daemon in the path, a change to the hosts file is
# already in effect and there is nothing here to do. Saying that plainly is
# probably the most useful thing this command can tell someone wondering why
# their change "has not worked".
#
# Only flushes that cannot disturb anything are performed. Reloading dnsmasq or
# restarting NetworkManager can drop the network of the machine, which is a
# categorically worse outcome than a stale cache entry, and nobody expects it
# from a command called flush. Those are reported with the command that would
# do it, and left to the person who can judge whether now is a good time.

declare -a FLUSH_NAMES=()
declare -a FLUSH_STATUS=()
declare -a FLUSH_DETAIL=()

cmd_flush() {
  local -i actionable=0

  while (($#)); do
    case $1 in
      -h | --help)
        help_flush
        return "$EX_OK"
        ;;
      --)
        shift
        break
        ;;
      *)
        die_usage 'flush ' "flush takes no argument: $1"
        ;;
    esac
  done

  if (($# > 0)); then
    die_usage 'flush ' "flush takes no argument: $1"
  fi

  FLUSH_NAMES=()
  FLUSH_STATUS=()
  FLUSH_DETAIL=()

  have_command resolvectl && actionable=1
  have_command nscd && actionable=1

  if ((actionable && !OPT_DRY_RUN)) && (($(id -u) != 0)); then
    die "$EX_PERM" \
      "clearing the resolver cache needs root; run 'sudo $PROGRAM_NAME flush'"
  fi

  _flush_resolved
  _flush_nscd
  _flush_report_others

  if ((${#FLUSH_NAMES[@]} == 0)); then
    _flush_record 'none' 'nothing-to-flush' \
      'no caching resolver found; glibc does not cache, so the file is already in effect'
  fi

  if ((OPT_JSON)); then
    _flush_json
  else
    _flush_text
  fi

  return "$EX_OK"
}

_flush_record() {
  FLUSH_NAMES+=("$1")
  FLUSH_STATUS+=("$2")
  FLUSH_DETAIL+=("$3")
}

# Rather than asking whether the service is running, try it and see: that needs
# no systemctl and gives the same answer.
_flush_resolved() {
  have_command resolvectl || return 0

  if ((OPT_DRY_RUN)); then
    _flush_record 'systemd-resolved' 'would-flush' 'resolvectl flush-caches'
    return 0
  fi

  if resolvectl flush-caches >/dev/null 2>&1; then
    _flush_record 'systemd-resolved' 'flushed' ''
  else
    _flush_record 'systemd-resolved' 'not-running' ''
  fi

  return 0
}

_flush_nscd() {
  have_command nscd || return 0

  if ((OPT_DRY_RUN)); then
    _flush_record 'nscd' 'would-flush' 'nscd -i hosts'
    return 0
  fi

  if nscd -i hosts >/dev/null 2>&1; then
    _flush_record 'nscd' 'flushed' ''
  else
    _flush_record 'nscd' 'not-running' ''
  fi

  return 0
}

# Caches this command will not touch, reported with what would clear them.
_flush_report_others() {
  if have_command dnsmasq; then
    _flush_record 'dnsmasq' 'needs-attention' \
      'not reloaded here, since that can drop the network: systemctl reload dnsmasq'
  fi

  if have_command unbound-control; then
    _flush_record 'unbound' 'needs-attention' \
      'not reloaded here: unbound-control reload'
  fi

  if have_command rndc; then
    _flush_record 'bind' 'needs-attention' \
      'not reloaded here: rndc flush'
  fi

  return 0
}

_flush_text() {
  local -i i

  for ((i = 0; i < ${#FLUSH_NAMES[@]}; i++)); do
    printf '%s\t%s\t%s\n' \
      "${FLUSH_NAMES[i]}" "${FLUSH_STATUS[i]}" "${FLUSH_DETAIL[i]}"
  done
}

_flush_json() {
  local sep=$'\n'
  local -i i

  printf '{\n'
  printf '  "version": %d,\n' "$JSON_SCHEMA_VERSION"
  printf '  "resolvers": ['

  for ((i = 0; i < ${#FLUSH_NAMES[@]}; i++)); do
    printf '%s' "$sep"
    sep=$',\n'
    printf '    {\n'
    json_literal "${FLUSH_NAMES[i]}"
    printf '      "name": %s,\n' "$JSON_LITERAL"
    json_literal "${FLUSH_STATUS[i]}"
    printf '      "status": %s,\n' "$JSON_LITERAL"
    json_literal "${FLUSH_DETAIL[i]}"
    printf '      "detail": %s\n' "$JSON_LITERAL"
    printf '    }'
  done

  if ((${#FLUSH_NAMES[@]} > 0)); then
    printf '\n  ]\n'
  else
    printf ']\n'
  fi
  printf '}\n'
}
