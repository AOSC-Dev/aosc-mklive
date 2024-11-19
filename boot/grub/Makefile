#!/usr/bin/make -f
# GRUB config and translation helper.
#
# This Makefile is created solely for the convenience of the developers and
# translators.
define USAGE

Usage
=====

1. Invoking make directly:
   Updates the PO Template, then PO Translations, and generates MO files.
   Generates the langsel.cfg language selection menu.

2. make newlang NEWLANG=xx_XX:
   Generates a new PO file with the locale xx_XX. You must translate it or
   remove it prior calling 'make install'.

3. make update-po:
   Updates the PO Tempate (if installer.cfg or boot.cfg is modified), then
   updates the translations with the new PO template.

4. make install:
   Make sure POT, PO, and MO files are update, then installs the mo files
   to DESTDIR/PREFIX, where
   DESTDIR = <aosc-mklive root>/iso;
   PREFIX = /boot/grub.

5. make testiso:
   Creates a simple bootable ISO file for testing the menus.
   Performs 'make install' before creating.
   You can specify the output file using TESTISO=/path/to/iso.

6. make clean:
   Removes generated MO files, DESTDIR and the test ISO.

Steps to add a new language
===========================

Here are the steps to add a new langauge (translation and menu entry):

1. Write a description file at langs/\$$LANG.mk, e.g. langs/fr_FR.mk.
   The contents are:
   CODE := fr_FR (same as the locale used by glibc)
   DISPNAME := Français (The name of the langauge, in the original form)
   ENGNAME := French (The name of the language, in English)

2. Create a fr_FR.po translation file by running:
   make newlang NEWLANG=fr_FR
   A new PO file will be created at po/fr_FR.po.

3. Edit the PO file to translate.

4. Make a test ISO by running:
   make testiso

5. You can commit the new translation if all of the following conditions
   are met:
   - Once booted, the new language is shown in the language selection menu.
   - Once selected, the entire menu text will be translated.

endef

# aosc-mklive/boot/grub
TOP := $(realpath .)

# Base directory to install everything.
PREFIX := /boot/grub

# Destination directory to install everything.
DESTDIR ?= $(shell realpath -m $(TOP)/../../iso)

# To make adding new languages by simply writing new Makefiles possible.
LANGS = $(foreach l,$(foreach f,$(wildcard langs/*.mk),$(notdir $(f))),$(basename $(l)))

# Default language to be highlighted.
DEFAULT_LANG := zh_CN

# What this disk is (LiveKit or Installer)
TARGET := installer

PODIR := po

# POT file
POT := $(PODIR)/aosc-live-media-menu.pot

# GRUB script which contains translatable strings
MENUS := installer.cfg livekit.cfg

# Other GRUB config files.
OTHERCFGS := grub.cfg init.cfg installer-flat.cfg livekit-flat.cfg

# Generated language selection menu.
LANGSEL := langsel.cfg

# Other files
OTHERFILES := fonts/unicode.pf2

# PO files
PO = $(wildcard po/*.po)

.ONESHELL:

# The procedure which produces GRUB menu entries.
define gen_menuentry
	$(eval include langs/$(1).mk)
	echo -e 'menuentry "$(DISPNAME)" --id lang-$(1) {
	\tset lang=$(1)
	\tset kernel_lang_param='LANG=$(1).UTF-8'
	\texport kernel_lang_param
	\tconfigfile $$prefix/$$tgt.cfg
	}' >> $(LANGSEL)
	count=$$(($$count +1))
endef

# Procedure to install other files.
define install-other-files
	install -Dvm644 $(1) $(DESTDIR)$(PREFIX)/$(1)
endef

.PHONY: all
all: langsel.cfg $(foreach l,$(foreach f,$(PO),$(notdir $(f))),po/$(basename $(l)).mo)

.PHONY: langsel.cfg
langsel.cfg:
	@echo -e "\033[1;36m>>> \033[0;1mGenerating language selection menu ...\033[0m"
	@count=0
	@echo    "set default=lang-$(DEFAULT_LANG)" > $(LANGSEL)
	@echo -e "menuentry 'Welcome to AOSC OS - Select your language:' {
	\ttrue
	}" >> $(LANGSEL)
	@echo -e "menuentry ' ' {
	\ttrue
	}" >> $(LANGSEL)
	@$(foreach l,$(LANGS),$(call gen_menuentry,$(l)))
	@echo -e "\033[1;36m>>> \033[0;1mMenu contains $$count languages.\033[0m"

.PHONY: newlang
newlang: $(POT)
	if [ "x$(NEWLANG)" = "x" ] ; then
		echo -e "\033[1;31m!!! \033[0;1mPlease set a language code via NEWLANG= .\033[0m"
		exit 1
	fi
	msginit -i $(POT) -o po/$(NEWLANG).po
	echo -e "\033[1;36m>>> \033[0;1mNow you can edit po/$(NEWLANG).po to add translations."

.PHONY: update-pot
update-pot: $(POT)

$(POT): $(MENUS)
	xgettext $(MENUS) -o $@ \
		--language=Shell \
		--copyright-holder="AOSC OS Maintainers <maintainers@aosc.io>" \
		--package-name="aosc-os-live-media-menu" \
		--package-version="0.1.0" \
		2>/dev/null

.PHONY: update-po
update-po: po/%.po

# msgmerge -U does not update the mtime of the PO file.
# We must touch the PO file after msgmerge to make sure it is newer than POT.
po/%.po: $(POT)
	msgmerge -U $@ $(POT)
	touch $@

po/%.mo: po/%.po
	msgfmt -o $@ $<

.PHONY: clean

clean:
	$(foreach f,$(wildcard po/*.mo),rm $(f) ;)
	rm -rf $(DESTDIR)

install: all
	install -dv $(DESTDIR)$(PREFIX)/locales-aosc
	install -Dvm644 -t $(DESTDIR)$(PREFIX)/locales-aosc $(wildcard po/*.mo)
	install -Dvm644 -t $(DESTDIR)$(PREFIX) $(MENUS) $(OTHERCFGS) $(LANGSEL)
	$(foreach f,$(OTHERFILES),$(call install-other-files,$(f)))
	sed -i -e 's|set tgt=installer|set tgt=$(TARGET)|g' $(DESTDIR)$(PREFIX)/grub.cfg

TESTISO ?= /tmp/test.iso

testiso: install
	pushd $(TOP)/../..
	grub-mkrescue -o $(TESTISO) iso -- -volid LiveKit
	echo -e "\033[1;36m>>> \033[0;1mSueccessfully generated test ISO file at $(TESTISO)."

.PHONY: help
.SILENT: help
help:
	cat << EOF
	$(USAGE)
	EOF
