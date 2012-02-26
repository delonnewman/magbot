.PHONY: all

SDCARD=/media/7C4C-449E
BIN=magbot
DIR=/usr/bin

all: deploy

deploy:
	cp $(BIN) $(SDCARD)/sl4a/scripts/mbot.pl
	cp -rf extlib/lib/perl5/* $(SDCARD)/com.googlecode.perlforandroid/extras/perl/site_perl

install:
	cp $(BIN) $(DIR)

uninstall:
	rm $(DIR)/$(BIN)
