#!/usr/bin/env bash
#
# Assemble a Debian package from the built artifacts.
#
# There is no debhelper here and no source package: what is being packaged is
# one shell script, one man page and two completions, and dpkg-deb builds that
# from a staging tree directly. --root-owner-group is what makes it work
# without fakeroot.

set -euo pipefail

readonly PACKAGE='hosts-cli'
readonly MAINTAINER='N36l3c7 <n36l3c7@protonmail.com>'

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
outdir=${1:-$root/build}
version=$(cat -- "$root/VERSION")

for artifact in "$root/build/hosts" "$root/build/hosts.1"; do
  if [[ ! -f $artifact ]]; then
    printf 'packaging: %s is missing; run make build first\n' "$artifact" >&2
    exit 1
  fi
done

staging=$(mktemp -d)
trap 'rm -rf -- "$staging"' EXIT INT TERM

# mktemp creates it private, and the root of a package is not.
chmod 0755 "$staging"

install -d "$staging/DEBIAN"
install -d "$staging/usr/bin"
install -d "$staging/usr/share/man/man1"
install -d "$staging/usr/share/bash-completion/completions"
install -d "$staging/usr/share/zsh/site-functions"
install -d "$staging/usr/share/doc/$PACKAGE"

install -m 0755 "$root/build/hosts" "$staging/usr/bin/hosts"
install -m 0644 "$root/build/hosts.1" "$staging/usr/share/man/man1/hosts.1"
install -m 0644 "$root/completions/hosts.bash" \
  "$staging/usr/share/bash-completion/completions/hosts"
install -m 0644 "$root/completions/_hosts" \
  "$staging/usr/share/zsh/site-functions/_hosts"
install -m 0644 "$root/packaging/deb/copyright" \
  "$staging/usr/share/doc/$PACKAGE/copyright"

# Debian policy wants the man page compressed. -n keeps the timestamp of the
# original out of the archive, which is one fewer reason for two builds of the
# same version to differ.
gzip -9n "$staging/usr/share/man/man1/hosts.1"

{
  printf '%s (%s) stable; urgency=low\n\n' "$PACKAGE" "$version"
  printf '  * Release %s.\n' "$version"
  printf '    See https://n36l3c7.github.io/hosts-cli/changelog.html\n\n'
  printf ' -- %s  %s\n' "$MAINTAINER" "$(date -R)"
} | gzip -9n >"$staging/usr/share/doc/$PACKAGE/changelog.Debian.gz"

sed "s/@VERSION@/$version/g" "$root/packaging/deb/control.in" \
  >"$staging/DEBIAN/control"

# Reported by apt before it installs, and expected in kibibytes.
size=$(du -sk --exclude=DEBIAN "$staging" | cut -f1)
printf 'Installed-Size: %s\n' "$size" >>"$staging/DEBIAN/control"

# Lets dpkg --verify say whether an installed file has been altered.
(cd "$staging" && find usr -type f -print0 | sort -z |
  xargs -0 md5sum >DEBIAN/md5sums)

install -d "$outdir"
dpkg-deb --build --root-owner-group "$staging" \
  "$outdir/${PACKAGE}_${version}_all.deb"
