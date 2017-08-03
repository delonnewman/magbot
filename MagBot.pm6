#!/usr/bin/env perl6

use v6;

unit package MagBot;

#binmode STDOUT, ':utf8';

=begin pod

=head1 NAME

magbot - For fetching media from jw.org feeds

=head1 SYNOPSIS

    > magbot
    # downloads magazines as specified in the $HOME/.magbot configuration file

    > magbot -d
    # starts in daemon mode and checks for new downloads each day

    > magbot -c
    # checks for new items in feeds in the $HOME/.magbot configuration file reports
    # the results on the screen and exits

    > magbot -c g E MP3
    # checks the current English Awake! feed and exits

    > magbot g E MP3
    # downloads the current English Awake! magazines in MP3 format

    > magbot w J PDF
    # downloads the current Japanese Watchtower magazines in PDF format

    > magbot w AL PDF 2012-08
    # downloads August 2012 Albanian Watchtower magazine in PDF format

=head1 DESCRIPTION

For fetching media from jw.org from the command-line prints
Gtk notifications, to standard output, and to Syslog.

=head1 DEPENDENCIES

    YAML
    XML::LibXML
    Gtk2::Notify (optional)
    HTTP::Tiny

=head1 AUTHOR

Delon Newman <delon.newman@gmail.com>

=end pod

use lib './vendor/yamlish/lib';
use XML;
use YAMLish;
use Getopt::Tiny;
use HTTP::Tinyish;

#
# Constants
#
my $HOME        := $*KERNEL.name ~~ 'win32' ?? %*ENV<HOMEDRIVE> ~ %*ENV<HOMEPATH> !! %*ENV<HOME>;
my $CONFIG_FILE := path $HOME, '.magbot', 'config';
my $LOG_FILE    := path $HOME, '.magbot', 'log';
my $DEFAULTS    := {
    mags => {
        w  => { E => qw{ EPUB M4B } },
        wp => { E => qw{ EPUB M4B } },
        g  => { E => qw{ EPUB M4B } }
    },
    dir => {
        audio  => path($HOME, 'Podcasts'),
        pub    => path($HOME, 'Reading')
    }
};

#
# Settings
#

my $VERSION   := '0.7.0';
my $APP_NAME  := 'MagBot';
my $ROOT_URL  := 'http://www.jw.org/apps/index.xjp';
my $FILE_URL  := 'http://download.jw.org/files/media_magazines';
my %MAGS      := config_or_defaults('mags');
my %DIR       := config_or_defaults('dir');
my $VERBOSE   := True;

# Valid mags, languages, formats
my %MAG_NAMES := {
    g  => 'Awake!',
    w  => 'Watchtower',
    wp => 'Watchtower (Public Edition)'
};

my %MAGS_DAYS := {
    g  => '',
    w  => '15',
    wp => '01'
};

# map valid formats to basic 'type'
my %FORMATS := {
    MP3  => 'audio',
    M4B  => 'audio',
    AAC  => 'audio',
    EPUB => 'pub',
    PDF  => 'pub'
};

my %FORMATS_EXTENSIONS := {
    MP3  => 'mp3.zip',
    M4B  => 'm4b',
    AAC  => 'm4b',
    EPUB => 'epub',
    PDF  => 'pdf'
};

my %EXTENSIONS_FORMATS = %FORMATS_EXTENSIONS.map({ .value => .key });

my %FORMAT_EQUIVALENTS := {
    AAC => 'M4B'
};

my %LANGUAGES := {
    AP  => 'Aymara', 
    B   => 'čeština', 
    D   => 'Dansk', 
    X   => 'Deutsch', 
    ST  => 'eesti', 
    E   => 'English', 
    S   => 'español', 
    F   => 'Français', 
    C   => 'hrvatski', 
    YW  => 'Ikinyarwanda', 
    IN  => 'Indonesia', 
    I   => 'italiano', 
    SW  => 'Kiswahili', 
    LT  => 'Latviešu', 
    L   => 'lietuvių', 
    H   => 'magyar', 
    MG  => 'Malagasy', 
    MT  => 'Malti', 
    O   => 'Nederlands', 
    N   => 'Norsk', 
    PA  => 'Papiamentu (Kòrsou)', 
    P   => 'polski', 
    T   => 'Português', 
    QUB => 'Quechua (Bolivia)', 
    M   => 'Română', 
    AL  => 'shqip', 
    V   => 'slovenčina', 
    SV  => 'slovenščina', 
    FI  => 'Suomi', 
    Z   => 'Svenska', 
    TK  => 'Türkçe', 
    G   => 'Ελληνική', 
    BL  => 'български', 
    U   => 'русский', 
    SB  => 'српски', 
    K   => 'українська', 
    GE  => 'ქართული', 
    REA => 'Հայերեն', 
    TL  => 'தமிழ்', 
    MY  => 'മലയാളം', 
    SI  => 'ไทย', 
    J   => '日本語', 
    CHS => '汉语简化字', 
    CH  => '漢語繁體字', 
    KO  => '한국어'
};

# some important functions
sub path { @_.join('/') }

sub log {
    my $fh = open $LOG_FILE, :a;
    say @_ if $VERBOSE;
    spurt $fh, @_;
    $fh.close;
}

#
# Functions for accessing configuration
#

# read from configuration file or from defaults
sub config_or_defaults {
    config(@_) || defaults(@_);
}

# read from configuration file
sub config is export {
    our %config ||= do {
        my $dir := $CONFIG_FILE.IO.dirname;
        mkdir $dir unless $dir.IO ~~ :e;
        my $f = $CONFIG_FILE;
        if $f.IO ~~ :e && (my $yaml = load-yaml(slurp $f)) { $yaml }
        else {
            my $fh := open $f, :w;
            $fh.print(to-yaml($DEFAULTS, ""));
            $fh.close;
            load-yaml($f.IO.slurp);
        }
    };

    read_config(%config, @_);
}

# read from defaults
sub defaults { 
    read_config($DEFAULTS, @_);
}

# read from configuration data structure
sub read_config (%config, @attrs) {
    if @attrs == 1 {
        %config{@attrs[0]};
    }
    else {
        read_config(%config{shift @attrs}, @attrs);
    }
}


#
# Some monkey business for IO
#

# get content from HTTP
sub get {
    my $res = HTTP::Tinyish.new.get(@_);

    CATCH {
        default {
            say .WHAT.perl, do given .backtrace[0] { .file, .line, .subname } if $VERBOSE;
            die "Can't download feed, exiting.";
        }
    }

    if $res<content> !~~ m:s/File not found/ {
        $res<content>;
    }
    else {
        die "When fetching ", @_, ":\n  ", $res<content>;
    }
}

# get and store content from HTTP to a file
sub getstore (Str $url, Str $file) {
    my $content = get($url); # allows to die before writing file
    my $fh = open $file, :w;
    $fh.print($content);
    $fh.close;
}

#
# For parsing feeds
#

# Data types

class Item {
  has Str  $.link is required;
  has Str  $.title is required;
  has Str  $.date is required;
  has      $.feed is required;

  method format {
    my ($f, $ext) = split(/\./, self.filename);
    %EXTENSIONS_FORMATS{$ext};
  }

  method filename {
    $.link.split(/\//).tail
  }

  method dir {
    path(issue-dir(self, $.feed.dir), self.file);
  }
}

class Feed {
  has Str  $.title is required;
  has Str  $.url is required;
  has Item @.items is required;
  has Str  $.description;
  has Str  $.language;
  has Str  $.image;
  has Str  $.format;

  method dir {
    path(root-dir(self), $.title.subst(/ [\:JW:\s] | <[ : \( \) ]> /, ''))
  }
}

sub root-dir ($arg) {
  my $type = $arg && $arg.format
              ?? %FORMATS{$arg.format}
              !! %FORMATS{$arg} || die "cannot find root directory for: $arg";
  
  if not %DIR{$type} ~~ List {
    %DIR{$type}
  }
  else {
    if %DIR{$type}.head.IO ~~ :e { %DIR{$type}[0] }
    else                         { %DIR{$type}[1] }
  }
}

sub issue-dir ($item, $feed-dir) {
  path($feed-dir, $item.title.subst(/ (\s \d ** 2 \: \d ** 2 \: \d ** 2 \w ** 3) | <[ \, \: ]> /, ''))
}

class Mag {
  has Str $.code is required;
  has Str $.lang is required;
  has Str $.format is required;
  has Str $.date;

  method BEGIN {
    die "'$.code' is an invalid magazine" unless %MAGS{$.code};
    die "'$.lang' is an invalid laguage" unless %LANGUAGES{$.lang};
    die "'$.format' is an invalid format" unless %FORMATS{$.format};
  }
}

# trys to always returns as much of a workable data structure as possible
#
#   $feed = {
#       title       => '',
#       description => '',
#       language    => '',
#       url         => '',
#       image       => '',
#       items       => [
#           {
#               title => '',
#               link  => '',
#               date  => '',
#               feed  => \$feed,
#           },
#           ...
#       ]
#   }
#
sub parse-feed {
    my ($xml) = @_;
    my %feed  = ();

    my $doc  = from-xml($xml);
    my $chan = $doc.elements(:TAG<channel>, :SINGLE);
    
    sub child {
        my ($parent, %args) = @_;
        
        my @tags  = %args<tags> if %args<tags>;
        my $tag   = %args<tag> || shift @tags;
        my @nodes = $parent.getElementsByTagName($tag);

        if    @nodes >  1 { @nodes }
        elsif @nodes == 1 {
            my $elem = @nodes[0];

            if    %args<attr> { $elem{%args<attr>} }
            elsif !@tags      { $elem.contents.map: { .text }.join('') }
            else              { child($elem, tags => @tags) }
        }
        else {
            Nil;
        }
    }

    sub items {
        my ($feed, @elems) = @_;

        return Nil if @elems == 1 && grep { not :defined }, @elems; 

        my @items = map {
          Item.new(title => child($_, tag => 'title'),
                   link  => child($_, tag => 'link'),
                   date  => child($_, tag => 'pubDate'),
                   feed  => $feed);
        }, @elems;

        @items;
    }
    
    %feed<title>       = child $chan, tag  => 'title';
    %feed<description> = child $chan, tag  => 'description';
    %feed<language>    = child $chan, tag  => 'language';
    %feed<image>       = child $chan, tags => ['image', 'url'];
    %feed<url>         = child $chan, tag  => 'atom:link', attr => 'href';
    %feed<items>       = items(%feed, child($chan, tag => 'item'));

    (my $pub, %feed<format>) = split ' ', %feed<description>;
    $pub ~~ /(<[a..z]>+)(<[A..Z]>+)/;
    (%feed<mag_code>, %feed<lang>) = ($1, $2);
    %feed<mag> = Mag.new(code => %feed<mag_code>, lang => %feed<lang>, format => %feed<format>);

    Feed.new(%feed);
}

#
# Top-Level Functions
#

#sub doeach($$) {
#    my ($urls, $fn, @args) = @_;
#
#    sub download($$@) {
#        threads->create(sub {
#            my ($url, $fn, @args) = @_;
#            $fn->($url, @args);
#            threads->exit;
#        }, @_);
#    }
#
#    sub worker {
#        my ($fn, $q, @args) = @_;
#        my $kid;
#        while ( my $url = $q->dequeue ) {
#            $kid = download $url => $fn, @args;
#            last if !$kid;
#        }
#
#        if ( threads->list > 1 ) {
#            my @threads = threads->list;
#            for my $t (threads->list) {
#                next if $t->tid == threads->tid;
#                next if $t->is_detached;
#
#                eval { $t->join };
#                if ( $@ ) { &log($@) }
#            }
#        }
#    }
#
#    if ( @$urls > 1 ) {
#        my $q = Thread::Queue->new(@$urls, undef);
#        worker($fn, $q, @args);
#    }
#    else {
#        download($urls->[0] => $fn, @args)->join;
#    }
#}
#
#sub find_new {
#    map  {  $_->[1] }
#    grep { !$_->[0] }
#    map  {
#        map {
#            [ -e item_dir($_), $_ ]
#        } @{$_->{items}}
#    } @_;
#}
#
#sub has_items {
#    my ($feed) = @_;
#
#    if ( $feed->{items} ) { 1 }
#    else {
#        notify "No items found for ", $feed->{title};
#        0;
#    }
#}
#
#sub get_new_items($$) {
#    my ($urls, $fn)  = @_;
#
#    doeach $urls => sub {
#    my ($url)   = @_;
#    my $content = get $url;
#        my $feed    = parse_feed($content);
#        if ( has_items $feed ) {
#            my @items = find_new $feed;
#            $fn->($feed->{mag}, @items);
#        }
#    };
#}
#
#sub download_media {
#    my @urls = @_;
#
#    get_new_items [@urls] => sub {
#        my ($mag, @items) = @_;
#
#        if ( @items == 0 ) {
#            notify_fatal report_mags($mag), "\n", ' ' x 4, "No new items found.\n";
#        }
#        else {
#            notify report_mags($mag),
#                   "\n", ' ' x 4,
#                   int(@items), " items found, downloading...\n";
#        }
#        
#        doeach [@items] => sub {
#            my ($item) = @_;
#            my $root_dir = root_dir $item->{format};
#            mkdir $root_dir unless -e $root_dir;
#    
#            my $feed_dir = feed_dir $item->{feed};
#            mkdir $feed_dir unless -e $feed_dir;
#    
#            my $issue_dir = issue_dir $item, $feed_dir;
#            mkdir $issue_dir unless -e $issue_dir;
#    
#            my $path = item_dir $item;
#            if ( $item->{link} ) {
#                getstore($item->{link}, $path) unless -e $path;
#                say "  OK - downloaded '", $item->{title}, "' to \n  --> ", $path, "\n";
#            }
#        };
#    };
#    
#    notify "Okay the work is complete! ;-)";
#}
#
## Yaay!! Gen them URLs
#sub gen_urls {
#    my (@mags) = @_;
#    map {
#        my ($mag, $lang, $format) = ($_->{mag}, $_->{lang}, $_->{format});
#
#        my %types = (
#            audio => 'sFFZRQVNZNT',
#            pub   => 'sFFCsVrGZNT'
#        );
#
#        my $type = $FORMATS{$format};
#
#        $format = $FORMAT_EQUIVALENTS{$format} if $FORMAT_EQUIVALENTS{$format};
#
#        "$ROOT_URL?option=$types{$type}&rln=$lang&rmn=$mag&rfm=$format";
#    } @mags;
#}
#
#sub parse_date {
#    local ($_) = @_;
#
#    # pad month with zero
#    my $m = sub {
#        local ($_) = @_;
#        if ( /\d{2,2}/ ) {   $_  }
#        else             { "0$_" }
#    };
#
#    # YYYY-MM
#    if    ( /(\d\d\d\d)-(\d{1,2})/  ) { ($1, $m->($2)) }
#
#    # MM/YYYY
#    elsif ( /(\d{1,2})\/(\d\d\d\d)/ ) { ($2, $m->($1)) }
#
#    # MM
#    elsif ( /(\d{1,2})/             ) {
#        my ($s, $min, $h, $d, $mon, $year) = localtime;
#        ($year + 1900, $m->($1))
#    }
#    else { @_ }
#}
#
#sub gen_file_url {
#    my ($m) = @_;
#
#    my $ext = $FORMATS_EXTENSIONS{$m->{format}} //
#    notify_fatal "'", $m->{format}, "' is not a valid format";
#
#    my ($year, $month) = parse_date($m->{date});
#
#    sprintf "%s/%s_%s_%s%s%s.%s",
#            $FILE_URL,
#            $m->{mag},
#            $m->{lang},
#            $year,
#            $month,
#            $MAGS_DAYS{$m->{mag}},
#            $ext;
#}
#
#
## a higer order function for creating lists composed of
## magazine components ($mag, $language, and $format)
## from magazine data structures
#sub magmap($$) {
#    my ($mags, $fn) = @_;
#    my @mags = keys %$mags;
#    map {
#        my $mag   = $_;
#        my @langs = keys %{$mags->{$mag}};
#
#        map {
#            my $lang    = $_;
#            my @formats = @{$mags->{$mag}->{$lang}};
#            
#            map {
#                my $format = $_;
#                $fn->($mag, $lang, $format);
#            } @formats
#
#        } @langs
#
#    } @mags
#}
#
#sub get_mags {
#    my @args = @_;
#
#    if ( @args ) {
#        if ( !(my @mags = Mag(@args)) ) {
#            notify_fatal "Need to specify magazine, language, and format to download.";
#        }
#        else { @mags }
#    }
#    else {
#        magmap $MAGS => sub { Mag(@_) };
#    }
#}
#
#sub report_mags {
#    my (@mags) = @_;
#
#    join "\n", map {
#        my ($m, $l, $f) = ($_->{mag}, $_->{lang}, $_->{format});
#        "  $LANGUAGES{$l} $MAGS{$m} in $f format";
#    } @mags
#}
#
#sub daemonize_or_run($$) {
#    my ($cond, $fn) = @_;
#
#    if ( $cond ) {
#        my $int = config_or_defaults('check-interval');
#        #AE::timer 0, $int => sub {
#            $fn->();
#        #};
#    }
#    else { $fn->() }
#}
#
##
## Commands
##
#
## And now the main event!!
#sub main {
#    my ($daemonize, @args) = @_;
#
#    daemonize_or_run $daemonize => sub {
#        if ( @args < 4 ) {
#            my @mags = get_mags(@args);
#
#            notify "Checking for new items and downloading...";
#            download_media gen_urls(@mags);
#        }
#        else {
#            my $mag  = Mag(@args);
#            my $url  = gen_file_url($mag);
#            my $dir  = root_dir($mag->{format});
#            my $rpt  = report_mags($mag);
#            my $path = File::Spec->join($dir, basename $url);
#
#            if ( -e $path ) { notify "$path already exists." }
#            else {
#                notify "Downloading:\n", $rpt,
#                       "\n    from: ", $url,
#                       "\n    to: ", $path, "\n";
#
#                getstore($url => $path);
#                notify "download complete :-)";
#            }
#        }
#    };
#
#    exit 0;
#}
#
#sub check {
#    my ($daemonize, @args) = @_;
#    my @mags = get_mags(@args);
#
#    notify "Checking for new items...";
#
#    daemonize_or_run $daemonize => sub {
#        get_new_items [gen_urls @mags] => sub {
#            my ($mag, @items) = @_;
#            if ( @items ) {
#                notify report_mags($mag), ":\n",
#                       join("\n", map { " " x 4 . $_->{title} } @items), "\n";
#            }
#            else {
#                notify report_mags($mag), ":\n",
#                       " " x 4, "No new items found.\n";
#            }
#        };
#    };
#}
#
#sub list {
#    say "I'm currently configured to watch";
#    say report_mags(magmap $MAGS => sub { Mag(@_) });
#    exit 0;
#}
#
#sub help {
#    say qq{
#$APP_NAME $VERSION
#
#Usage: $0 [OPTIONS] [MAG CODE] [LANGUAGE CODE] [FORMAT]
#
#  Options:
#    --check, -c
#        check for new feed items as sepecified by arguments
#        or if none are present by configuration in
#        $HOME/.magbot, report and exit
#
#    --list, -l
#        list mags that are set to be downloaded in
#        configuration file
#
#    --verbose, -v
#        flag verbose mode
#
#    --daemonize, -d (not working)
#        run as a backgroud process daily
#
#    --help, -h
#        display this message
#
#  Other arguments
#    MAG CODE:
#        Used to indicate which magazine to download valid
#        values are 'w' (Watchtower), 'g' (Awake!), and 'wp'
#        (Watchtower - Public Edition).
#
#    LANGUAGE CODE:
#        Used to indicate which language edition of the
#        specified magazine should be downloaded.
#
#    FORMAT:
#        Used to indicate which file format to download the
#        magazine in.  Valid values are 'MP3', 'M4B', 'AAC',
#        'EPUB', and 'PDF'.\n};
#
#    exit 0;
#}
#
#
#if ( __FILE__ eq $0 ) {
#    my $daemonize = 0;
#
#    GetOptions(
#        'daemonize|d' => sub { $daemonize = 1 }, # run daily
#        'help|h'      => sub { help() },
#        'check|c'     => sub { check($daemonize, @ARGV); exit 0 },
#        'list|l'      => sub { list() },
#        'verbose|v'   => sub { $VERBOSE = 1 }
#    );
#
#    main($daemonize, @ARGV);
#}
#
#1;