# shellcheck shell=bash
#
# Address and hostname validation.
#
# Addresses are validated the way inet_pton does, which is stricter than the
# historic inet_aton: an octet with a leading zero is rejected rather than read
# as octal, because the two readings disagree and the ambiguity is a known
# source of misdirected traffic.

_ADDRESS_FAMILY=''
_IPV6_GROUPS=0

# Succeed when the argument is a syntactically valid IPv4 address.
#
# The shape is checked with glob patterns rather than a regular expression:
# bash recompiles an expression on every match, and these run once per line.
is_valid_ipv4() {
  local octet

  # Word splitting drops a trailing empty field, so without this guard
  # "1.2.3.4." would split into four perfectly valid octets.
  [[ $1 != *. ]] || return 1

  split_fields '.' "$1"
  ((${#FIELDS[@]} == 4)) || return 1

  for octet in "${FIELDS[@]}"; do
    # These five patterns encode the 0 to 255 range and the rejection of a
    # leading zero at once: 010 and 256 match none of them, and an empty
    # octet, from an address such as 1..2.3, matches none either.
    case $octet in
      [0-9] | [1-9][0-9] | 1[0-9][0-9] | 2[0-4][0-9] | 25[0-5]) ;;
      *) return 1 ;;
    esac
  done

  return 0
}

# Validate one colon separated part of an IPv6 address and store the number of
# 16 bit groups it stands for in _IPV6_GROUPS. An embedded IPv4 address counts
# as two groups and is only legal as the very last group of the whole address,
# so the caller says whether this part may end with one.
_ipv6_count_groups() {
  local part=$1 allow_embedded_ipv4=$2 group
  local -a groups=()
  local -i i last

  _IPV6_GROUPS=0
  [[ -n $part ]] || return 0

  split_fields ':' "$part"
  groups=("${FIELDS[@]}")

  last=$((${#groups[@]} - 1))
  for i in "${!groups[@]}"; do
    group=${groups[i]}
    if [[ $group == *.* ]]; then
      ((allow_embedded_ipv4 && i == last)) || return 1
      is_valid_ipv4 "$group" || return 1
      _IPV6_GROUPS=$((_IPV6_GROUPS + 2))
      continue
    fi
    case $group in
      '' | *[!0-9A-Fa-f]*) return 1 ;;
    esac
    ((${#group} <= 4)) || return 1
    _IPV6_GROUPS=$((_IPV6_GROUPS + 1))
  done

  return 0
}

# Succeed when the argument is a syntactically valid IPv6 address. A zone
# identifier is accepted, because a link-local address without one is
# ambiguous and the form appears in real hosts files.
is_valid_ipv6() {
  local address=$1 zone head tail
  local -i groups_head groups_tail

  if [[ $address == *%* ]]; then
    # Everything after the first % is the zone, so a second % lands inside it
    # and is rejected below rather than being silently dropped.
    zone=${address#*%}
    address=${address%%%*}
    [[ -n $zone && $zone != *%* ]] || return 1
  fi

  case $address in
    '' | *[!0-9A-Fa-f:.]*) return 1 ;;
  esac

  # A leading or trailing colon is only legal as part of "::".
  case $address in
    : | :[!:]*) return 1 ;;
  esac
  case $address in
    *[!:]:) return 1 ;;
  esac

  if [[ $address == *::* ]]; then
    # "::" may appear at most once.
    case $address in
      *::*::*) return 1 ;;
    esac

    head=${address%%::*}
    tail=${address#*::}
    if [[ $head == *: || $tail == :* ]]; then
      return 1
    fi

    _ipv6_count_groups "$head" 0 || return 1
    groups_head=$_IPV6_GROUPS
    _ipv6_count_groups "$tail" 1 || return 1
    groups_tail=$_IPV6_GROUPS

    # "::" stands for at least one group of zeros.
    ((groups_head + groups_tail <= 7)) || return 1
    return 0
  fi

  _ipv6_count_groups "$address" 1 || return 1
  ((_IPV6_GROUPS == 8)) || return 1
  return 0
}

# Succeed when the argument is a valid IPv4 or IPv6 address, and store the
# address family in _ADDRESS_FAMILY.
classify_address() {
  local address=$1
  if is_valid_ipv4 "$address"; then
    _ADDRESS_FAMILY='inet'
    return 0
  fi
  if is_valid_ipv6 "$address"; then
    _ADDRESS_FAMILY='inet6'
    return 0
  fi
  _ADDRESS_FAMILY=''
  return 1
}

# Shared label walk for the two hostname checks below. The caller supplies the
# glob of characters a label may not contain, so that the lenient variant can
# allow the underscore.
_check_hostname_labels() {
  local name=$1 forbidden=$2 label

  ((${#name} >= 1 && ${#name} <= 253)) || return 1

  # A trailing dot marks a fully qualified DNS name. Entries in a hosts file
  # are not DNS wire names, so it is rejected rather than silently ignored.
  [[ $name != *. ]] || return 1

  split_fields '.' "$name"

  for label in "${FIELDS[@]}"; do
    ((${#label} >= 1 && ${#label} <= 63)) || return 1
    case $label in
      -* | *-) return 1 ;;
    esac
    # shellcheck disable=SC2254 # the caller supplies a pattern on purpose
    case $label in
      $forbidden) return 1 ;;
    esac
  done

  return 0
}

# Succeed when the argument is a hostname conforming to RFC 1123: labels of
# letters, digits and hyphens, never starting or ending with a hyphen, at most
# 63 characters each and 253 in total.
is_valid_hostname() {
  _check_hostname_labels "$1" '*[!A-Za-z0-9-]*'
}

# Succeed when the argument is a hostname that only breaks RFC 1123 by using
# an underscore. Container and orchestration tooling generates these names in
# large numbers, so they are reported as a warning rather than an error.
is_lenient_hostname() {
  _check_hostname_labels "$1" '*[!A-Za-z0-9_-]*'
}
