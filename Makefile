.PHONY: all

SDCARD=/media/7C4C-449E

all: deploy

deploy:
	cp mbot $(SDCARD)/sl4a/scripts/mbot.pl
	cp -rf extlib/lib/perl5/* $(SDCARD)/com.googlecode.perlforandroid/extras/perl/site_perl

install:
	cp mbot $(HOME)/bin

uninstall:
	rm $(HOME)/bin/mbot
