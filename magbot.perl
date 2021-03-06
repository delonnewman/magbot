#!/usr/bin/env perl
use v5.10;
use strict;
use warnings;

binmode STDOUT, ':utf8';

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

Delon Newman <contact@delonewman.name>

=cut

use YAML;
use HTTP::Tiny;
use XML::LibXML;
use Getopt::Long;
use Data::Dump qw{ dump };

use File::Spec;
use File::Basename;

#
# Settings
#

my $VERSION   = '0.7.0';
my $APP_NAME  = 'MagBot';
my $ROOT_URL  = 'http://www.jw.org/apps/index.xjp';
my $FILE_URL  = 'http://download.jw.org/files/media_magazines';
my $MAGS      = config_or_defaults('mags');
my $DIR       = config_or_defaults('dir');
my $VERBOSE   = 0;
my $HOME      = $ENV{HOME} || "$ENV{HOMEDRIVE}$ENV{HOMEPATH}";

# Valid mags, languages, formats
my %MAGS = (
    g  => 'Awake!',
    w  => 'Watchtower',
    wp => 'Watchtower (Public Edition)'
);

my %MAGS_DAYS = (
    g  => '',
    w  => '15',
    wp => '01',
);

# map valid formats to basic 'type'
my %FORMATS = (
    MP3  => 'audio',
    M4B  => 'audio',
    AAC  => 'audio',
    EPUB => 'pub',
    PDF  => 'pub'
);

my %FORMATS_EXTENSIONS = (
    MP3  => 'mp3.zip',
    M4B  => 'm4b',
    AAC  => 'm4b',
    EPUB => 'epub',
    PDF  => 'pdf'
);

my %FORMAT_EQUIVALENTS = (
    AAC => 'M4B'
);

my %LANGUAGES = (
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
    KO  => '한국어', 
);


# some important functions
BEGIN {
    #
    # Print messages with Gtk2::Notify, to syslog, and to STDOUT
    # any of which are available.
    #
    my $gtk;
    eval {
        require Gtk2::Notify;
        Gtk2::Notify->import(-init, basename $0);
        $gtk = 1;  
    };

    my $syslog;

    sub notify {
        if ( $gtk ) {
            Gtk2::Notify->new($APP_NAME . ' says:', join('', @_))->show;
        }

        print @_, "\n"
    }


    #
    # Error Reporting
    #
    sub notify_fatal {
        if ( $gtk ) {
            Gtk2::Notify->new($APP_NAME . ' says:', join('', @_))->show;
        }

        print STDERR @_, "\n";
    }

    #
    # Consise, cross-platform path building
    #
    sub path { File::Spec->join(@_) }

    # replace but don't destory
    sub replace($$$) {
        my ($str, $pat, $replace) = @_;

        $str =~ s/$pat/$replace/;

        $str;
    }

    # replace but don't destory
    sub greplace($$$) {
        my ($str, $pat, $replace) = @_;

        $str =~ s/$pat/$replace/g;

        $str;
    }

    sub fatal($) {
        print STDERR @_, "\n";
    }
}

#
# Constants
#
use constant HOME        => $^O =~ /win32/i ? "$ENV{HOMEDRIVE}\\$ENV{HOMEPATH}" : $ENV{HOME};
use constant CONFIG_FILE => path(HOME, '.magbot' => 'config');
use constant LOG_FILE    => path(HOME, '.magbot' => 'log');
use constant DEFAULTS    => {
    mags => {
        w  => { E => [qw{ EPUB M4B }] },
        wp => { E => [qw{ EPUB M4B }] },
        g  => { E => [qw{ EPUB M4B }] }
    },
    dir => {
        audio  => path(HOME, 'Podcasts'),
        pub    => path(HOME, 'Reading')
    }
};

sub log {
    open my $l, '>>', LOG_FILE or
        die "Can't append to file ", LOG_FILE, ": $!";
    say @_ if $VERBOSE;
    say $l @_;
}

#
# Functions for accessing configuration
#

# read from configuration file or from defaults
sub config_or_defaults {
    if ( wantarray ) {
        my $ref = config(@_) || defaults(@_);
        if ( ref $ref eq 'HASH' || ref $ref eq 'ARRAY' ) { @{$ref} }
        else                                             {  ($ref) }
    }
    else {
        config(@_) || defaults(@_);
    }
}

# read from configuration file
{
    my $config;
    sub config {
        $config //= do {
            my $dir = dirname CONFIG_FILE;
            mkdir $dir unless -e $dir;
            my $f = CONFIG_FILE;
            if ( -e $f && (my $yaml = YAML::LoadFile($f)) ) { $yaml }
            else {
                open my $fh, '>', $f or die "can't write to $f";
                print $fh YAML::Dump(DEFAULTS);
                close $fh;
                YAML::LoadFile($f);
            }
        };
    
        if ( wantarray ) { @{read_config($config, @_)} }
        else             {   read_config($config, @_) }
    }
}

# read from defaults
sub defaults { 
    if ( wantarray ) { @{read_config(DEFAULTS, @_)} }
    else             {   read_config(DEFAULTS, @_)  }
}

# read from configuration data structure
sub read_config {
    my ($config, @attrs) = @_;

    if ( @attrs == 1 ) {
        my $ref = $config->{$attrs[0]};
        if ( wantarray ) {
            if    ( ref $ref eq 'HASH' )  { %{$ref} }
            elsif ( ref $ref eq 'ARRAY' ) { @{$ref} }
            else                          {  ($ref) }
        }
        else {
            $ref
        }
    }
    else {
        read_config($config->{shift @attrs}, @attrs);
    }
}


#
# Some monkey business for IO
#

# get content from HTTP
sub get {
    my $res = eval { HTTP::Tiny->new->get(@_) };

    if ( $@ ) {
        say "Can't fetch '", @_, '\' ', $@;
        notify_fatal "Can't download feed, exiting.";
    }

    if ( $res->{content} =~ qr{File not found.} ) {
        notify_fatal "When fetching ", @_, ":\n  ", $res->{content};
    }
    else {
        $res->{content};
    }
}

# get and store content from HTTP to a file
sub getstore {
    my ($url, $file) = @_;

    my $content = get($url); # allows to die before writing file
    open my $fh, '>', $file or die "can't write to $file: $!";
    print $fh $content;
}

#
# For parsing feeds
#

# Feed constructor
sub Feed {
    my %feed = @_;
    
    $feed{title} // die "title is required";
    $feed{url}   // die "url is required";
    $feed{items} // notify_fatal "Didn't find any items in feed";

    bless \%feed, 'Feed';
}

# Item constructor
sub Item {
    my %item = @_;

    $item{link}  // die "link is required";
    $item{title} // die "title is required";
    $item{date}  // die "date is required";
    $item{feed}  // die "feed is required";

    $item{format} = do {
        my ($f, $ext) = split(/\./, basename $item{link});
        my ($format)  = grep { $FORMATS_EXTENSIONS{$_} eq $ext } keys %FORMATS_EXTENSIONS;
        $format;
    };

    bless \%item, 'Item';
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
sub parse_feed {
    my ($xml) = @_;
    my %feed  = ();

    my $dom  = XML::LibXML->load_xml(string => $xml);
    my $chan = $dom->getElementsByTagName('channel')->get_node(0);
    
    sub child {
        my ($parent, %args) = @_;
        
        my @tags  = @{$args{tags}} if $args{tags};
        my $tag   = $args{tag} // shift @tags;
        my $nodes = $parent->getChildrenByTagName($tag);

        if ( $nodes->size > 1 ) {
            my @elems = $nodes->get_nodelist;
            wantarray ? @elems : \@elems;
        }
        elsif ( $nodes->size == 1 ) {
            my $elem = $nodes->get_node(0);

            if    ( $args{attr} ) { $elem->getAttribute($args{attr}) }
            elsif ( !@tags )      { $elem->textContent }
            else                  { child($elem, tags => \@tags) }
        }
        else {
            undef;
        }
    }

    sub items {
        my ($feed, @elems) = @_;

        return undef if (@elems == 1 && grep !defined $_, @elems); 

        my @items = map {
          Item(title => child($_, tag => 'title'),
               link  => child($_, tag => 'link'),
               date  => child($_, tag => 'pubDate'),
               feed  => $feed);
        } @elems;

        \@items;
    }
    
    $feed{title}       = child $chan, tag  => 'title';
    $feed{description} = child $chan, tag  => 'description';
    $feed{language}    = child $chan, tag  => 'language';
    $feed{image}       = child $chan, tags => ['image', 'url'];
    $feed{url}         = child $chan, tag  => 'atom:link', attr => 'href';
    $feed{items}       = items(\%feed, child($chan, tag => 'item'));

    (my $pub, $feed{format}) = split ' ', $feed{description};
    $pub =~ /([a-z]+)([A-Z]+)/;
    ($feed{mag_code}, $feed{lang}) = ($1, $2);
    $feed{mag} = Mag($feed{mag_code}, $feed{lang}, $feed{format});

    Feed(%feed);
}

#
# Some functions for accessing directory structure
#

sub feed_dir {
    my $feed = shift;

    $feed->{dir} //= do {
        my $dir = greplace $feed->{title}, qr/(?:JW: )|[:\(\)]/ => '';
        path(root_dir($feed) => $dir);
    };

    $feed->{dir};
}

sub root_dir {
    my $arg = shift;
    my $type = do {
        if ( $arg && ref $arg && $arg->{format} ) {
            $FORMATS{$arg->{format}};
        }
        else {
            $FORMATS{$arg};
        }
    } // die 'cannot find root directory for: ', $arg;

    if ( ref $DIR eq 'HASH' ) {
        if ( ref $DIR->{$type} eq 'ARRAY' ) {
            if ( -e $DIR->{$type}->[0] ) { $DIR->{$type}->[0] }
            else                         { $DIR->{$type}->[1] }
        }
        else { $DIR->{$type} }
    }
    else { $DIR }
}

sub issue_dir {
    my ($item, $feed_dir) = @_;

    my $dir = greplace $item->{date}, qr/( \d{2}:\d{2}:\d{2} \w{3})|[,:]/ => '';
    path($feed_dir => $dir);
}

sub item_dir {
    my ($item) = @_;
    my $issue_dir = issue_dir $item => feed_dir($item->{feed});

    $item->{dir} //= path($issue_dir => item_file($item));

    $item->{dir}
}

sub item_file  {
    my ($item) = @_;

    $item->{file} //= basename $item->{link} if $item->{link};

    $item->{file};
}

#
# Top-Level Functions
#

sub doeach($$) {
    my ($urls, $fn, @args) = @_;

    sub download($$@) {
        my ($url, $fn, @args) = @_;
        $fn->($url, @args);
    }

    sub worker {
        my ($fn, $q, @args) = @_;
        my $kid;
        while ( my $url = $q->dequeue ) {
            $kid = download $url => $fn, @args;
            last if !$kid;
        }

        if ( threads->list > 1 ) {
            my @threads = threads->list;
            for my $t (threads->list) {
                next if $t->tid == threads->tid;
                next if $t->is_detached;

                eval { $t->join };
                if ( $@ ) { &log($@) }
            }
        }
    }

    #if ( @$urls > 1 ) {
    #    my $q = Thread::Queue->new(@$urls, undef);
    #    worker($fn, $q, @args);
    #}
    #else {
        download($urls->[0] => $fn, @args); #->join;
        #}
}

sub find_new {
    map  {  $_->[1] }
    grep { !$_->[0] }
    map  {
        map {
            [ -e item_dir($_), $_ ]
        } @{$_->{items}}
    } @_;
}

sub has_items {
    my ($feed) = @_;

    if ( $feed->{items} ) { 1 }
    else {
        notify "No items found for ", $feed->{title};
        0;
    }
}

sub get_new_items($$) {
    my ($urls, $fn)  = @_;

    doeach $urls => sub {
    my ($url)   = @_;
    my $content = get $url;
        my $feed    = parse_feed($content);
        if ( has_items $feed ) {
            my @items = find_new $feed;
            $fn->($feed->{mag}, @items);
        }
    };
}

sub download_media {
    my @urls = @_;

    get_new_items [@urls] => sub {
        my ($mag, @items) = @_;

        if ( @items == 0 ) {
            notify_fatal report_mags($mag), "\n", ' ' x 4, "No new items found.\n";
        }
        else {
            notify report_mags($mag),
                   "\n", ' ' x 4,
                   int(@items), " items found, downloading...\n";
        }
        
        doeach [@items] => sub {
            my ($item) = @_;
            my $root_dir = root_dir $item->{format};
            mkdir $root_dir unless -e $root_dir;
    
            my $feed_dir = feed_dir $item->{feed};
            mkdir $feed_dir unless -e $feed_dir;
    
            my $issue_dir = issue_dir $item, $feed_dir;
            mkdir $issue_dir unless -e $issue_dir;
    
            my $path = item_dir $item;
            if ( $item->{link} ) {
                getstore($item->{link}, $path) unless -e $path;
                say "  OK - downloaded '", $item->{title}, "' to \n  --> ", $path, "\n";
            }
        };
    };
    
    notify "Okay the work is complete! ;-)";
}

# Yaay!! Gen them URLs
sub gen_urls {
    my (@mags) = @_;
    map {
        my ($mag, $lang, $format) = ($_->{mag}, $_->{lang}, $_->{format});

        my %types = (
            audio => 'sFFZRQVNZNT',
            pub   => 'sFFCsVrGZNT'
        );

        my $type = $FORMATS{$format};

        $format = $FORMAT_EQUIVALENTS{$format} if $FORMAT_EQUIVALENTS{$format};

        "$ROOT_URL?option=$types{$type}&rln=$lang&rmn=$mag&rfm=$format";
    } @mags;
}

sub parse_date {
    local ($_) = @_;

    # pad month with zero
    my $m = sub {
        local ($_) = @_;
        if ( /\d{2,2}/ ) {   $_  }
        else             { "0$_" }
    };

    # YYYY-MM
    if    ( /(\d\d\d\d)-(\d{1,2})/  ) { ($1, $m->($2)) }

    # MM/YYYY
    elsif ( /(\d{1,2})\/(\d\d\d\d)/ ) { ($2, $m->($1)) }

    # MM
    elsif ( /(\d{1,2})/             ) {
        my ($s, $min, $h, $d, $mon, $year) = localtime;
        ($year + 1900, $m->($1))
    }
    else { @_ }
}

sub gen_file_url {
    my ($m) = @_;

    my $ext = $FORMATS_EXTENSIONS{$m->{format}} //
    notify_fatal "'", $m->{format}, "' is not a valid format";

    my ($year, $month) = parse_date($m->{date});

    sprintf "%s/%s_%s_%s%s%s.%s",
            $FILE_URL,
            $m->{mag},
            $m->{lang},
            $year,
            $month,
            $MAGS_DAYS{$m->{mag}},
            $ext;
}


# a higer order function for creating lists composed of
# magazine components ($mag, $language, and $format)
# from magazine data structures
sub magmap($$) {
    my ($mags, $fn) = @_;
    my @mags = keys %$mags;
    map {
        my $mag   = $_;
        my @langs = keys %{$mags->{$mag}};

        map {
            my $lang    = $_;
            my @formats = @{$mags->{$mag}->{$lang}};
            
            map {
                my $format = $_;
                $fn->($mag, $lang, $format);
            } @formats

        } @langs

    } @mags
}

# Mag constructor
sub Mag {
    my ($mag, $lang, $format, $date) = @_;

    $mag // fatal "magazine code is required";
    fatal "'$mag' is an invalid magazine" unless $MAGS{$mag};

    $lang // fatal "language is required";
    fatal "'$lang' is an invalid language" unless $LANGUAGES{$lang};

    $format // fatal "format is required";
    fatal "'$format' is an invalid format" unless $FORMATS{$format};

    bless { mag    => $mag, 
            lang   => $lang,
            format => $format,
            date   => $date }, 'Mag';
}

sub get_mags {
    my @args = @_;

    if ( @args ) {
        if ( !(my @mags = Mag(@args)) ) {
            notify_fatal "Need to specify magazine, language, and format to download.";
        }
        else { @mags }
    }
    else {
        magmap $MAGS => sub { Mag(@_) };
    }
}

sub report_mags {
    my (@mags) = @_;

    join "\n", map {
        my ($m, $l, $f) = ($_->{mag}, $_->{lang}, $_->{format});
        "  $LANGUAGES{$l} $MAGS{$m} in $f format";
    } @mags
}

sub daemonize_or_run($$) {
    my ($cond, $fn) = @_;

    if ( $cond ) {
        my $int = config_or_defaults('check-interval');
        #AE::timer 0, $int => sub {
            $fn->();
        #};
    }
    else { $fn->() }
}

#
# Commands
#

# And now the main event!!
sub main {
    my ($daemonize, @args) = @_;

    daemonize_or_run $daemonize => sub {
        if ( @args < 4 ) {
            my @mags = get_mags(@args);

            notify "Checking for new items and downloading...";
            download_media gen_urls(@mags);
        }
        else {
            my $mag  = Mag(@args);
            my $url  = gen_file_url($mag);
            my $dir  = root_dir($mag->{format});
            my $rpt  = report_mags($mag);
            my $path = File::Spec->join($dir, basename $url);

            if ( -e $path ) { notify "$path already exists." }
            else {
                notify "Downloading:\n", $rpt,
                       "\n    from: ", $url,
                       "\n    to: ", $path, "\n";

                getstore($url => $path);
                notify "download complete :-)";
            }
        }
    };

    exit 0;
}

sub check {
    my ($daemonize, @args) = @_;
    my @mags = get_mags(@args);

    notify "Checking for new items...";

    daemonize_or_run $daemonize => sub {
        get_new_items [gen_urls @mags] => sub {
            my ($mag, @items) = @_;
            if ( @items ) {
                notify report_mags($mag), ":\n",
                       join("\n", map { " " x 4 . $_->{title} } @items), "\n";
            }
            else {
                notify report_mags($mag), ":\n",
                       " " x 4, "No new items found.\n";
            }
        };
    };
}

sub list {
    say "I'm currently configured to watch";
    say report_mags(mags_from_config($MAGS));
    exit 0;
}

sub help {
    say qq{
$APP_NAME $VERSION

Usage: $0 [OPTIONS] [MAG CODE] [LANGUAGE CODE] [FORMAT]

  Options:
    --check, -c
        check for new feed items as sepecified by arguments
        or if none are present by configuration in
        $HOME/.magbot, report and exit

    --list, -l
        list mags that are set to be downloaded in
        configuration file

    --verbose, -v
        flag verbose mode

    --daemonize, -d (not working)
        run as a backgroud process daily

    --help, -h
        display this message

  Other arguments
    MAG CODE:
        Used to indicate which magazine to download valid
        values are 'w' (Watchtower), 'g' (Awake!), and 'wp'
        (Watchtower - Public Edition).

    LANGUAGE CODE:
        Used to indicate which language edition of the
        specified magazine should be downloaded.

    FORMAT:
        Used to indicate which file format to download the
        magazine in.  Valid values are 'MP3', 'M4B', 'AAC',
        'EPUB', and 'PDF'.\n};

    exit 0;
}


if ( __FILE__ eq $0 ) {
    my $daemonize = 0;

    GetOptions(
        'daemonize|d' => sub { $daemonize = 1 }, # run daily
        'help|h'      => sub { help() },
        'check|c'     => sub { check($daemonize, @ARGV); exit 0 },
        'list|l'      => sub { list() },
        'verbose|v'   => sub { $VERBOSE = 1 }
    );

    main($daemonize, @ARGV);
}

1;
