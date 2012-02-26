.PHONY: all install uninstall doc deploy

SDCARD=/media/7C4C-449E
BIN=magbot
DIR=/usr/bin
DOC=/usr/share/man/man1

all: deploy

deploy:
	cp $(BIN) $(SDCARD)/sl4a/scripts/mbot.pl
	cp -rf extlib/lib/perl5/* $(SDCARD)/com.googlecode.perlforandroid/extras/perl/site_perl

install:
	cp $(BIN) $(DIR)
	cp $(BIN).1 $(DOC)

uninstall:
	rm $(DIR)/$(BIN)

doc: README $(BIN).1

README:
	pod2text $(BIN) > README

$(BIN).1:
	pod2man $(BIN) > $(BIN).1
