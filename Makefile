# hosts-cli - build, test and installation.
#
# The shipped program is a single self-contained script, assembled from the
# modules in src/ so that development stays modular while distribution stays
# a matter of copying one file.

PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
MANDIR  ?= $(PREFIX)/share/man/man1
DESTDIR ?=

SHELLCHECK ?= shellcheck
MANDOC     ?= mandoc
BATS       ?= bats
INSTALL    ?= install

VERSION  := $(shell cat VERSION)
BUILDDIR := build
SOURCES  := $(sort $(wildcard src/*.sh))
SCRIPT   := $(BUILDDIR)/hosts
MANPAGE  := $(BUILDDIR)/hosts.1

.PHONY: all build install uninstall test lint clean help

all: build

build: $(SCRIPT) $(MANPAGE)

# The output directory is created by the recipes themselves: it cannot be an
# order-only prerequisite, because it is named like the phony "build" target.
$(SCRIPT): $(SOURCES) VERSION
	mkdir -p $(@D)
	cat $(SOURCES) | sed 's/@VERSION@/$(VERSION)/g' >$@.tmp
	chmod 0755 $@.tmp
	mv -f $@.tmp $@

$(MANPAGE): man/hosts.1.in VERSION
	mkdir -p $(@D)
	sed 's/@VERSION@/$(VERSION)/g' man/hosts.1.in >$@.tmp
	chmod 0644 $@.tmp
	mv -f $@.tmp $@

install: build
	$(INSTALL) -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(MANDIR)
	$(INSTALL) -m 0755 $(SCRIPT) $(DESTDIR)$(BINDIR)/hosts
	$(INSTALL) -m 0644 $(MANPAGE) $(DESTDIR)$(MANDIR)/hosts.1

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/hosts
	rm -f $(DESTDIR)$(MANDIR)/hosts.1

lint: build
	$(SHELLCHECK) $(SCRIPT)
	$(MANDOC) -T lint -W warning $(MANPAGE)

test: build
	$(BATS) test

clean:
	rm -rf $(BUILDDIR)

help:
	@echo 'Targets:'
	@echo '  build      assemble build/hosts and build/hosts.1'
	@echo '  lint       run shellcheck on the script and mandoc on the man page'
	@echo '  test       run the bats suite against the built script'
	@echo '  install    install into $$(DESTDIR)$$(PREFIX) (default /usr/local)'
	@echo '  uninstall  remove the installed files'
	@echo '  clean      remove the build directory'
