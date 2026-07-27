# hosts-cli - build, test and installation.
#
# The shipped program is a single self-contained script, assembled from the
# modules in src/ so that development stays modular while distribution stays
# a matter of copying one file.

PREFIX      ?= /usr/local
BINDIR      ?= $(PREFIX)/bin
MANDIR      ?= $(PREFIX)/share/man/man1
BASHCOMPDIR ?= $(PREFIX)/share/bash-completion/completions
ZSHCOMPDIR  ?= $(PREFIX)/share/zsh/site-functions
DESTDIR     ?=

SHELLCHECK ?= shellcheck
MANDOC     ?= mandoc
BATS       ?= bats
INSTALL    ?= install
ZSH        ?= zsh

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
	$(INSTALL) -d $(DESTDIR)$(BASHCOMPDIR) $(DESTDIR)$(ZSHCOMPDIR)
	$(INSTALL) -m 0755 $(SCRIPT) $(DESTDIR)$(BINDIR)/hosts
	$(INSTALL) -m 0644 $(MANPAGE) $(DESTDIR)$(MANDIR)/hosts.1
	$(INSTALL) -m 0644 completions/hosts.bash $(DESTDIR)$(BASHCOMPDIR)/hosts
	$(INSTALL) -m 0644 completions/_hosts $(DESTDIR)$(ZSHCOMPDIR)/_hosts

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/hosts
	rm -f $(DESTDIR)$(MANDIR)/hosts.1
	rm -f $(DESTDIR)$(BASHCOMPDIR)/hosts
	rm -f $(DESTDIR)$(ZSHCOMPDIR)/_hosts

lint: build
	$(SHELLCHECK) $(SCRIPT)
	$(SHELLCHECK) completions/hosts.bash
	$(MANDOC) -T lint -W warning $(MANPAGE)
	@# The zsh completion cannot be exercised from bash, so a syntax check is
	@# what there is. It runs where zsh exists, and CI is one of those places.
	@if command -v $(ZSH) >/dev/null 2>&1; then \
		$(ZSH) -n completions/_hosts && echo "zsh -n completions/_hosts"; \
	else \
		echo "zsh not installed, skipping the syntax check of completions/_hosts"; \
	fi

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
