.PHONY: all

SDCARD=/media/7C4C-449E
BIN=magbot

all: deploy

deploy:
	cp $(BIN) $(SDCARD)/sl4a/scripts/mbot.pl
	cp -rf extlib/lib/perl5/* $(SDCARD)/com.googlecode.perlforandroid/extras/perl/site_perl

install:
	cp $(BIN) $(HOME)/bin

uninstall:
	rm $(HOME)/bin/$(BIN)
