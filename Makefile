.PHONY: all

SDCARD=/media/7C4C-449E

all: deploy

deploy:
	cp magbot $(SDCARD)/sl4a/scripts/magbot.pl
	cp -rf extlib/lib/perl5/* $(SDCARD)/com.googlecode.perlforandroid/extras/perl/site_perl
