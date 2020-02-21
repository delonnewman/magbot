# NAME

magbot - For fetching media from jw.org feeds

# SYNOPSIS

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

# DESCRIPTION

For fetching media from jw.org from the command-line prints
Gtk notifications, to standard output, and to Syslog.

# DEPENDENCIES

    YAML
    XML::LibXML
    Gtk2::Notify (optional)
    HTTP::Tiny

# AUTHOR

Delon Newman <contact@delonewman.name>
