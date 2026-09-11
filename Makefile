VERSION := 0.0.1

LANGUAGE_NAME := tree-sitter-git-config

# repository
SRC_DIR := src

PARSER_REPO_URL := $(shell git -C $(SRC_DIR) remote get-url origin 2>/dev/null)

ifeq ($(PARSER_URL),)
	PARSER_URL := $(subst .git,,$(PARSER_REPO_URL))
ifeq ($(shell echo $(PARSER_URL) | grep '^[a-z][-+.0-9a-z]*://'),)
	PARSER_URL := $(subst :,/,$(PARSER_URL))
	PARSER_URL := $(subst git@,https://,$(PARSER_URL))
endif
endif

TS ?= tree-sitter

# code signing (macOS only):
# `tree-sitter build` / the linker emit a "linker-signed" ad-hoc signature which
# macOS refuses to dlopen (SIGKILL / "Code Signature Invalid"). Re-signing with a
# plain ad-hoc signature fixes it.
CODESIGN ?= codesign

# neovim tree-sitter parser (the file neovim actually loads: parser/git_config.so)
NVIM_PARSER := git_config.so
NVIM_PARSER_DIR ?= $(HOME)/.local/share/nvim/site/parser

# tree-sitter CLI parser cache (used by `tree-sitter parse/highlight` outside the
# repo). The CLI normally rebuilds this on its own; `cli-install` forces it.
TS_CACHE_DIR ?= $(HOME)/.cache/tree-sitter/lib

# ABI versioning
SONAME_MAJOR := $(word 1,$(subst ., ,$(VERSION)))
SONAME_MINOR := $(word 2,$(subst ., ,$(VERSION)))

# install directory layout
PREFIX ?= /usr/local
INCLUDEDIR ?= $(PREFIX)/include
LIBDIR ?= $(PREFIX)/lib
PCLIBDIR ?= $(LIBDIR)/pkgconfig

# object files
OBJS := $(patsubst %.c,%.o,$(wildcard $(SRC_DIR)/*.c))

# flags
ARFLAGS := rcs
override CFLAGS += -I$(SRC_DIR) -std=c11 -fPIC

# OS-specific bits
ifeq ($(OS),Windows_NT)
	$(error "Windows is not supported")
else ifeq ($(shell uname),Darwin)
	SOEXT = dylib
	SOEXTVER_MAJOR = $(SONAME_MAJOR).dylib
	SOEXTVER = $(SONAME_MAJOR).$(SONAME_MINOR).dylib
	LINKSHARED := $(LINKSHARED)-dynamiclib -Wl,
	ifneq ($(ADDITIONAL_LIBS),)
	LINKSHARED := $(LINKSHARED)$(ADDITIONAL_LIBS),
	endif
	LINKSHARED := $(LINKSHARED)-install_name,$(LIBDIR)/lib$(LANGUAGE_NAME).$(SONAME_MAJOR).dylib,-rpath,@executable_path/../Frameworks
else
	SOEXT = so
	SOEXTVER_MAJOR = so.$(SONAME_MAJOR)
	SOEXTVER = so.$(SONAME_MAJOR).$(SONAME_MINOR)
	LINKSHARED := $(LINKSHARED)-shared -Wl,
	ifneq ($(ADDITIONAL_LIBS),)
	LINKSHARED := $(LINKSHARED)$(ADDITIONAL_LIBS)
	endif
	LINKSHARED := $(LINKSHARED)-soname,lib$(LANGUAGE_NAME).so.$(SONAME_MAJOR)
endif
ifneq ($(filter $(shell uname),FreeBSD NetBSD DragonFly),)
	PCLIBDIR := $(PREFIX)/libdata/pkgconfig
endif

all: lib$(LANGUAGE_NAME).a lib$(LANGUAGE_NAME).$(SOEXT) $(LANGUAGE_NAME).pc

lib$(LANGUAGE_NAME).a: $(OBJS)
	$(AR) $(ARFLAGS) $@ $^

lib$(LANGUAGE_NAME).$(SOEXT): $(OBJS)
	$(CC) $(LDFLAGS) $(LINKSHARED) $^ $(LDLIBS) -o $@
ifneq ($(STRIP),)
	$(STRIP) $@
endif
ifeq ($(shell uname),Darwin)
	$(CODESIGN) --force --sign - $@
endif

$(LANGUAGE_NAME).pc: bindings/c/$(LANGUAGE_NAME).pc.in
	sed  -e 's|@URL@|$(PARSER_URL)|' \
		-e 's|@VERSION@|$(VERSION)|' \
		-e 's|@LIBDIR@|$(LIBDIR)|' \
		-e 's|@INCLUDEDIR@|$(INCLUDEDIR)|' \
		-e 's|@REQUIRES@|$(REQUIRES)|' \
		-e 's|@ADDITIONAL_LIBS@|$(ADDITIONAL_LIBS)|' \
		-e 's|=$(PREFIX)|=$${prefix}|' \
		-e 's|@PREFIX@|$(PREFIX)|' $< > $@

$(SRC_DIR)/parser.c: grammar.js
	$(TS) generate

# --- Neovim parser (git_config.so) ------------------------------------------
# Build the parser that Neovim loads and (on macOS) re-sign it. Without the
# codesign step Neovim crashes on startup with SIGKILL ("Code Signature
# Invalid") when dlopen'ing a linker-signed parser.
$(NVIM_PARSER): $(SRC_DIR)/parser.c
	$(TS) build -o $@
ifeq ($(shell uname),Darwin)
	$(CODESIGN) --force --sign - $@
endif

nvim: $(NVIM_PARSER)

# build, re-sign and install into Neovim's runtime parser directory.
# also refreshes the tree-sitter CLI cache (cli-install) so `:InspectTree` and
# the `tree-sitter` command line stay in sync.
nvim-install: $(NVIM_PARSER) cli-install
	install -d '$(NVIM_PARSER_DIR)'
	install -m755 $(NVIM_PARSER) '$(NVIM_PARSER_DIR)/$(NVIM_PARSER)'
ifeq ($(shell uname),Darwin)
	$(CODESIGN) --force --sign - '$(NVIM_PARSER_DIR)/$(NVIM_PARSER)'
endif

# build the parser into the tree-sitter CLI cache (mac: git_config.dylib, linux: git_config.so)
cli-install: $(SRC_DIR)/parser.c
	install -d '$(TS_CACHE_DIR)'
	$(TS) build -o '$(TS_CACHE_DIR)/git_config.$(SOEXT)'
ifeq ($(shell uname),Darwin)
	$(CODESIGN) --force --sign - '$(TS_CACHE_DIR)/git_config.$(SOEXT)'
endif

install: all
	install -d '$(DESTDIR)$(INCLUDEDIR)'/tree_sitter '$(DESTDIR)$(PCLIBDIR)' '$(DESTDIR)$(LIBDIR)'
	install -m644 bindings/c/$(LANGUAGE_NAME).h '$(DESTDIR)$(INCLUDEDIR)'/tree_sitter/$(LANGUAGE_NAME).h
	install -m644 $(LANGUAGE_NAME).pc '$(DESTDIR)$(PCLIBDIR)'/$(LANGUAGE_NAME).pc
	install -m644 lib$(LANGUAGE_NAME).a '$(DESTDIR)$(LIBDIR)'/lib$(LANGUAGE_NAME).a
	install -m755 lib$(LANGUAGE_NAME).$(SOEXT) '$(DESTDIR)$(LIBDIR)'/lib$(LANGUAGE_NAME).$(SOEXTVER)
	ln -sf lib$(LANGUAGE_NAME).$(SOEXTVER) '$(DESTDIR)$(LIBDIR)'/lib$(LANGUAGE_NAME).$(SOEXTVER_MAJOR)
	ln -sf lib$(LANGUAGE_NAME).$(SOEXTVER_MAJOR) '$(DESTDIR)$(LIBDIR)'/lib$(LANGUAGE_NAME).$(SOEXT)

uninstall:
	$(RM) '$(DESTDIR)$(LIBDIR)'/lib$(LANGUAGE_NAME).a \
		'$(DESTDIR)$(LIBDIR)'/lib$(LANGUAGE_NAME).$(SOEXTVER) \
		'$(DESTDIR)$(LIBDIR)'/lib$(LANGUAGE_NAME).$(SOEXTVER_MAJOR) \
		'$(DESTDIR)$(LIBDIR)'/lib$(LANGUAGE_NAME).$(SOEXT) \
		'$(DESTDIR)$(INCLUDEDIR)'/tree_sitter/$(LANGUAGE_NAME).h \
		'$(DESTDIR)$(PCLIBDIR)'/$(LANGUAGE_NAME).pc

clean:
	$(RM) $(OBJS) $(LANGUAGE_NAME).pc lib$(LANGUAGE_NAME).a lib$(LANGUAGE_NAME).$(SOEXT) $(NVIM_PARSER)

test:
	$(TS) test

.PHONY: all install uninstall clean test nvim nvim-install cli-install
