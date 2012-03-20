.PHONY: all install uninstall doc deploy clean_doc install-deps

SDCARD=/media/7C4C-449E
BIN=magbot
DIR=/usr/local/bin
DOC=/usr/local/share/man/man1
PKG_BIN=apt-get install
CPAN_BIN=cpanm
PERL_DEPS=LWP::Simple Gtk2::Notify
SYS_DEPS=libgtk2-notify-perl

all: deploy

deploy:
	cp $(BIN) $(SDCARD)/sl4a/scripts/mbot.pl
	cp -rf extlib/lib/perl5/* $(SDCARD)/com.googlecode.perlforandroid/extras/perl/site_perl

install: install-deps
	cp $(BIN) $(DIR)
	cp $(BIN).1 $(DOC)
	cp nook-script $(DIR)

install-deps:
	$(PKG_BIN) $(SYS_DEPS)
	$(CPAN_BIN) $(PERL_DEPS)

uninstall:
	rm $(DIR)/$(BIN)
	rm $(DOC)/$(BIN).1
	rm $(DIR)/nook-script

doc: clean_doc README $(BIN).1

clean_doc:
	rm README # force update
	rm $(BIN).1 # force update

README:
	pod2text $(BIN) > README

$(BIN).1:
	pod2man -c MagBot $(BIN) > $(BIN).1
