.PHONY: all install uninstall doc deploy clean_doc install-deps

# files
BIN=magbot
SRC=magbot.perl
MAN=$(BIN).1
SCRIPT=nook-script
RULE=10-nook.rules
PP=$(shell which pp)

# dirs
DIR=/usr/local/bin
DOC=/usr/local/share/man/man1
UDEV=/etc/udev/rules.d

# dependencies
PKG_BIN=apt-get install
CPAN_BIN=cpanm

all: $(BIN) doc

$(BIN):
	$(PP) -o $(BIN) $(SRC)

install:
	cp $(BIN) $(DIR)
	cp $(MAN) $(DOC)

deps:
	$(CPAN_BIN) $(PERL_DEPS)

uninstall:
	rm $(DIR)/$(BIN)
	rm $(DOC)/$(MAN)
	rm $(DIR)/$(SCRIPT)
	rm $(UDEV)/$(RULE)

doc: README.md $(BIN).1

clean_doc:
	rm README.md # force update
	rm $(BIN).1 # force update

clean: clean_doc
	rm $(BIN)

README.md:
	pod2markdown $(SRC) > README.md

$(BIN).1:
	pod2man -c MagBot $(SRC) > $(BIN).1
