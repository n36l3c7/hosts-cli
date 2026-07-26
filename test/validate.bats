#!/usr/bin/env bats
#
# Address and hostname validation.

load helper

@test "is_valid_ipv4 accepts well formed addresses" {
  in_script '
    for address in 0.0.0.0 1.2.3.4 127.0.0.1 255.255.255.255 10.0.0.1 \
      192.168.1.1 8.8.8.8 0.0.0.1; do
      is_valid_ipv4 "$address" || { echo "wrongly rejected: $address"; exit 1; }
    done
  '
  [ "$status" -eq 0 ]
}

@test "is_valid_ipv4 rejects malformed addresses" {
  in_script '
    for address in "" 1.2.3 1.2.3.4.5 256.1.1.1 999.1.1.1 1234.1.1.1 \
      1.2.3.a .1.2.3.4 1.2.3.4. 1..2.3 "1.2.3.4 " -1.2.3.4; do
      if is_valid_ipv4 "$address"; then echo "wrongly accepted: $address"; exit 1; fi
    done
  '
  [ "$status" -eq 0 ]
}

@test "is_valid_ipv4 rejects octets with a leading zero" {
  # inet_pton rejects them and inet_aton reads them as octal: the two
  # readings disagree, so the address is ambiguous rather than merely untidy.
  in_script '
    for address in 010.0.0.1 1.02.3.4 1.2.3.04 00.0.0.0; do
      if is_valid_ipv4 "$address"; then echo "wrongly accepted: $address"; exit 1; fi
    done
    is_valid_ipv4 0.0.0.0
  '
  [ "$status" -eq 0 ]
}

@test "is_valid_ipv6 accepts well formed addresses" {
  in_script '
    for address in :: ::1 1::8 2001:db8::1 1:2:3:4:5:6:7:8 \
      2001:0db8:0000:0000:0000:0000:0000:0001 1:2:3:4:5:6:7:: \
      fe80::200:5aee:feaa:20a2 ::ffff:1.2.3.4 ::ffff:255.255.255.255 \
      64:ff9b::1.2.3.4 ff02::1; do
      is_valid_ipv6 "$address" || { echo "wrongly rejected: $address"; exit 1; }
    done
  '
  [ "$status" -eq 0 ]
}

@test "is_valid_ipv6 accepts a zone identifier" {
  in_script '
    for address in fe80::1%eth0 fe80::1%1 fe80::1%wlp3s0; do
      is_valid_ipv6 "$address" || { echo "wrongly rejected: $address"; exit 1; }
    done
    for address in "fe80::1%" "fe80::1%a%b"; do
      if is_valid_ipv6 "$address"; then echo "wrongly accepted: $address"; exit 1; fi
    done
  '
  [ "$status" -eq 0 ]
}

@test "is_valid_ipv6 rejects malformed addresses" {
  in_script '
    for address in "" : ::: 1:2:3:4:5:6:7 1:2:3:4:5:6:7:8:9 1::2::3 1:::2 \
      1:2:3:4:5:6:7:8:: :1:2:3:4:5:6:7:8 1:2:3:4:5:6:7:8: 12345::1 gggg::1 \
      1.2.3.4 1.2.3.4::1 ::ffff:1.2.3.4.5 ::ffff:999.1.1.1 2001:db8:; do
      if is_valid_ipv6 "$address"; then echo "wrongly accepted: $address"; exit 1; fi
    done
  '
  [ "$status" -eq 0 ]
}

@test "an embedded IPv4 address is only legal as the last group" {
  in_script '
    is_valid_ipv6 ::ffff:1.2.3.4 || { echo "rejected a legal form"; exit 1; }
    if is_valid_ipv6 ::1.2.3.4:ffff; then echo "accepted a v4 group in the middle"; exit 1; fi
  '
  [ "$status" -eq 0 ]
}

@test "classify_address reports the address family" {
  in_script '
    classify_address 10.0.0.1 && [[ $_ADDRESS_FAMILY == inet ]] || exit 1
    classify_address ::1 && [[ $_ADDRESS_FAMILY == inet6 ]] || exit 1
    if classify_address nonsense; then exit 1; fi
    [[ -z $_ADDRESS_FAMILY ]]
  '
  [ "$status" -eq 0 ]
}

@test "is_valid_hostname accepts names conforming to RFC 1123" {
  in_script '
    long_label=$(printf "a%.0s" {1..63})
    for name in a localhost host1 1host my-host foo.bar a.b.c.d \
      staging.local UPPER.Case "$long_label" "$long_label.example"; do
      is_valid_hostname "$name" || { echo "wrongly rejected: $name"; exit 1; }
    done
  '
  [ "$status" -eq 0 ]
}

@test "is_valid_hostname rejects names breaking RFC 1123" {
  in_script '
    too_long_label=$(printf "a%.0s" {1..64})
    too_long_name=$(printf "aaaaaaaa.%.0s" {1..29})a
    for name in "" -foo foo- foo..bar .foo "foo bar" "foo:bar" "foo/bar" \
      "$too_long_label" "$too_long_name"; do
      if is_valid_hostname "$name"; then echo "wrongly accepted: $name"; exit 1; fi
    done
  '
  [ "$status" -eq 0 ]
}

@test "a trailing dot is rejected" {
  # An entry in a hosts file is not a DNS wire name, so the fully qualified
  # form is refused rather than silently accepted with a different meaning.
  in_script '
    if is_valid_hostname "example.com."; then exit 1; fi
    is_valid_hostname "example.com"
  '
  [ "$status" -eq 0 ]
}

@test "the underscore is refused by the strict check and allowed by the lenient one" {
  in_script '
    if is_valid_hostname "foo_bar"; then echo "strict accepted it"; exit 1; fi
    is_lenient_hostname "foo_bar" || { echo "lenient rejected it"; exit 1; }
    if is_lenient_hostname "-foo"; then echo "lenient accepted a leading hyphen"; exit 1; fi
  '
  [ "$status" -eq 0 ]
}
