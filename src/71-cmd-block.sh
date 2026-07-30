# shellcheck shell=bash
#
# hosts block - point domains at a sinkhole address.
#
# Blocked domains are kept in a section of their own at the end of the file,
# marked off so that a blocklist of tens of thousands of machine written lines
# can be treated as one thing rather than drowning the entries someone
# actually maintains.

declare -a BLOCK_DOMAINS=()

# Read domains from standard input, one per line, ignoring blank lines and
# comments so that a downloaded list can be piped in as it is.
_block_read_domains() {
  local line

  BLOCK_DOMAINS=()
  while IFS= read -r line; do
    trim "$line"
    [[ -n $TRIMMED ]] || continue
    [[ $TRIMMED != '#'* ]] || continue
    BLOCK_DOMAINS+=("$TRIMMED")
  done

  return 0
}

cmd_block() {
  local target domain
  local -a positional=() addresses=() to_block=()
  local -i ipv4_only=0 skipped=0

  while (($#)); do
    case $1 in
      -h | --help)
        help_block
        return "$EX_OK"
        ;;
      --ipv4-only)
        ipv4_only=1
        shift
        ;;
      --to)
        (($# >= 2)) || die_usage 'block ' '--to requires an address'
        addresses=("$2")
        shift 2
        ;;
      --to=*)
        addresses=("${1#*=}")
        shift
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        die_usage 'block ' "unknown option for 'block': $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  # A real blocklist has tens of thousands of domains in it, which do not fit
  # on a command line, so with no arguments they are read from standard input,
  # one per line.
  if ((${#positional[@]} == 0)); then
    if [[ -t 0 ]]; then
      die_usage 'block ' 'block requires at least one domain, or a list on stdin'
    fi
    _block_read_domains
    positional=("${BLOCK_DOMAINS[@]}")
    if ((${#positional[@]} == 0)); then
      die_usage 'block ' 'no domain was given'
    fi
  fi

  if ((${#addresses[@]} == 0)); then
    addresses=("$DEFAULT_BLOCK_ADDRESS_V4")
    # A block that only covers IPv4 blocks nothing at all on a machine that
    # has IPv6, which is the mistake most blocklist tools make.
    ((ipv4_only)) || addresses+=("$DEFAULT_BLOCK_ADDRESS_V6")
  fi

  local family=''
  for domain in "${addresses[@]}"; do
    classify_address "$domain" family ||
      die "$EX_VALIDATION" "not a valid IPv4 or IPv6 address: $domain"
  done

  for domain in "${positional[@]}"; do
    if is_valid_hostname "$domain"; then
      continue
    fi
    if is_lenient_hostname "$domain"; then
      warn "domain is outside RFC 1123: $domain"
      continue
    fi
    die "$EX_VALIDATION" "not a valid domain: $domain"
  done

  open_for_write "$OPT_FILE" target
  hostsfile_load "$target"

  edit_reset

  for domain in "${positional[@]}"; do
    if _block_is_spoken_for "$domain"; then
      # A bulk operation that gave up at the first obstacle would be useless,
      # so this reports and carries on, unlike add which refuses outright.
      warn "$domain already has an entry outside the block section; skipped"
      skipped=$((skipped + 1))
      continue
    fi
    if _block_already_blocked "$domain" "${addresses[@]}"; then
      continue
    fi
    to_block+=("$domain")
  done

  if ((${#to_block[@]} == 0)); then
    if ((skipped > 0)); then
      info "nothing to block, $skipped domain(s) skipped"
    else
      info 'nothing to block'
    fi
    return "$EX_OK"
  fi

  _block_queue "${addresses[@]}" -- "${to_block[@]}"

  edit_commit "$target" "block ${#to_block[@]} domain(s)"
}

# Drop the markers when a change leaves the block section with no entries in
# it. The section is declared as managed, so an empty one is scaffolding for
# nothing and goes away with what it held.
block_prune_if_empty() {
  local -i index

  ((_hf_block_open >= 0 && _hf_block_close > _hf_block_open)) || return 0

  for ((index = _hf_block_open + 1; index < _hf_block_close; index++)); do
    [[ ${_hf_kind[index]} == 'entry' ]] || continue
    [[ -n ${EDIT_DELETE[$index]:-} ]] || return 0
  done

  for ((index = _hf_block_open; index <= _hf_block_close; index++)); do
    edit_delete "$index"
  done

  return 0
}

# Succeed when the domain is already an entry somewhere outside the section.
_block_is_spoken_for() {
  local domain=${1,,}
  local -a candidates=()
  local -i index

  split_on_whitespace "${_hf_by_name[$domain]:-}"
  candidates=("${FIELDS[@]}")

  for index in "${candidates[@]}"; do
    ((_hf_in_block[index])) || return 0
  done

  return 1
}

# Succeed when the domain is already pointed at every sinkhole address.
_block_already_blocked() {
  local domain=${1,,}
  shift
  local address
  local -a candidates=()
  local -i index found

  split_on_whitespace "${_hf_by_name[$domain]:-}"
  candidates=("${FIELDS[@]}")

  for address in "$@"; do
    found=0
    for index in "${candidates[@]}"; do
      ((_hf_in_block[index])) || continue
      ((_hf_enabled[index])) || continue
      if [[ ${_hf_ip[index]} == "$address" ]]; then
        found=1
        break
      fi
    done
    ((found)) || return 1
  done

  return 0
}

# Queue the new lines, opening the section when there is not one yet.
_block_queue() {
  local -a addresses=()
  local address domain

  while (($# > 0)) && [[ $1 != '--' ]]; do
    addresses+=("$1")
    shift
  done
  shift || true

  if ((_hf_block_close >= 0)); then
    for domain in "$@"; do
      for address in "${addresses[@]}"; do
        line_new_entry "$address" "$domain"
        edit_insert_before "$_hf_block_close" "$LINE_RESULT"
      done
    done
    return 0
  fi

  edit_append "$BLOCK_SECTION_OPEN"
  edit_append "$BLOCK_SECTION_NOTE"
  for domain in "$@"; do
    for address in "${addresses[@]}"; do
      line_new_entry "$address" "$domain"
      edit_append "$LINE_RESULT"
    done
  done
  edit_append "$BLOCK_SECTION_CLOSE"

  return 0
}
