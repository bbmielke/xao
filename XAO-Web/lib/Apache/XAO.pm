=head1 NAME

Apache::XAO - Apache XAO handler

=head1 SYNOPSIS

In httpd.conf or <VirtualHost ..> section:

 PerlFreshRestart   On
 PerlSetVar         SiteName        testsite
 SetHandler         perl-script
 PerlTransHandler   Apache::XAO

=head1 DESCRIPTION

Apache::XAO is provides a clean way to integrate XAO::Web based web
sites into mod_perl for maximum performance. The same site can still be
used in CGI mode (see L<XAO::Web::Intro> for configuration samples).

Apache::XAO must be installed as PerlTransHandler, not as a
PerlHandler.

If some areas of the tree need to be excluded from XAO::Web (as it
usually happens with images -- /images or something similar) these
areas need to be configured in the site's configuration. This is
described in details below.

As a convenience, there is also simple way to exclude certain locations
using Apache configuration only. Most common is ExtFilesMap:

 PerlSetVar         ExtFilesMap     /images

This tells Apache::XAO to map everything under /images location in
URI to physical files in 'images' directory off the project home
directory. For a site named 'testsite' this is roughly the same as the
following, only you do not have to worry about exact path to site's home
directory:

 Alias              /images         /usr/local/xao/projects/testsite/images

To achieve the same effect from the site configuration you need:

 path_mapping_table => {
     '/images' => {
         type        => 'maptodir',
     },
 },

More generic way is to just disable Apache::XAO from handling some area
altogether:

 PerlSetVar         ExtFiles        /images

In this case no mapping is performed and generally Apache::XAO does
nothing and lets Apache handle the files.

Site configuration equivalent is:

 path_mapping_table => {
     '/images' => {
         type        => 'external',
     },
 },

More then one prefix can be listed using ':' as separator:

 PerlSetVar         ExtFilesMap     /images:/icons:/ftp

=head2 PERFORMANCE

Using Apache::XAO gives of course incomparable with CGI mode
performance, but even in comparision with mod_rewrite/mod_perl
combination we got 5 to 10 percent boost in performance in tests.

Not to mention clearer looking config files and reduced server memory
footprint -- no need to load mod_rewrite.

For additional improvement in memory size it is recommended to add
the following line into the main Apache httpd.conf (not into any
VirtualHost):

 PerlModule XAO::PreLoad

This way most of XAO modules will be pre-compiled and shared between all
apache child thus saving memory and child startup time:

=cut

###############################################################################
package Apache::XAO;
use strict;
use warnings;
use XAO::Utils;
use XAO::Web;

###############################################################################

use mod_perl 1.26;
use constant MP2 => ($mod_perl::VERSION && $mod_perl::VERSION >= 1.99);

BEGIN {
    if(MP2) {
        require Apache::Const;
        Apache::Const->import(qw(:common OK DECLINED SERVER_ERROR NOT_FOUND));

        ##
        # Required to bring in methods used below
        #
        require Apache::Server;
        Apache::Server->import();
        require Apache::ServerUtil;
        Apache::ServerUtil->import();
        require Apache::Log;
        Apache::Log->import();
        require Apache::RequestRec;
        Apache::RequestRec->import();
        require Apache::RequestIO;
        Apache::RequestIO->import();

        ##
        # Asking dprint/eprint to use Apache logging
        #
        #XXX#TODO#
    }
    else {
        require Apache::Constants;
        Apache::Constants->import(qw(OK DECLINED SERVER_ERROR NOT_FOUND));
    }
}

###############################################################################

sub handler_content ($);
sub server_error ($$;$);

###############################################################################

sub handler {
    my $r=shift;

    ##
    # Request URI
    #
    my $uri=$r->uri;
    ### $r->server->log_error("HANDLER: $uri");

    ##
    # Checking if we were called as a PerlHandler and complaining
    # otherwise.
    #
    if($r->is_initial_req && exists $ENV{REQUEST_METHOD}) {
        return server_error($r,'Use PerlTransHandler',<<EOT);
Please use 'PerlTransHandler Apache::XAO' instead of just PerlHandler.
EOT
    }

    ##
    # By convention we disallow access to /bits/ for security reasons.
    #
    if(index($uri,'/bits/')>=0) {
        ### $r->server->log_error("Attempt of direct access to /bits/ ($uri)");
        return NOT_FOUND;
    }

    ##
    # Getting site name and loading the site configuration
    #
    my $sitename=$r->dir_config('sitename') || $r->dir_config('SiteName');
    if(!$sitename) {
        return server_error($r,'No Site Name',<<EOT);
Please use 'PerlSetVar sitename yoursitename' directive in the
configuration.
EOT
    }
    my $web=XAO::Web->new(sitename => $sitename);

    ##
    # Checking if we need to worry about ExtFilesMap or ExtFiles in the
    # apache config.
    #
    my $efm=$r->dir_config('ExtFilesMap') || '';
    my $ef=$r->dir_config('ExtFiles') || '';
    if($efm || $ef) {
        my $config=$web->config;
        my $pmt=$config->get('path_mapping_table');
        my $pmt_orig=$pmt;
        foreach my $path (split(/:+/,$efm)) {
            $path='/'.$path;
            $path=~s/\/{2,}/\//g;
            $path=~s/\/$//g;
            next if $pmt->{$path};
            $pmt->{$path}={ type => 'maptodir' };
        }
        foreach my $path (split(/:+/,$ef)) {
            $path='/'.$path;
            $path=~s/\/{2,}/\//g;
            $path=~s/\/$//g;
            next if $pmt->{$path};
            $pmt->{$path}={ type => 'external' };
        }
        if(!$pmt_orig) {
            $config->put(path_mapping_table => $pmt);
        }
    }

    ##
    # Checking if we should serve this request at all. If the URI ends
    # with / we always add index.html to the URI before checking.
    #
    my $pagedesc;
    if(substr($uri,-1,1) eq '/') {
        $pagedesc=$web->analyze($uri . 'index.html',$sitename);
    }
    else {
        $pagedesc=$web->analyze($uri,$sitename);
    }
    my $ptype=$pagedesc->{type} || 'xaoweb';
    if($ptype eq 'external') {
        ### $r->server->log_error("EXTERNAL: uri=$uri");
        return Apache::DECLINED;
    }
    elsif($ptype eq 'maptodir') {
        my $dir=$pagedesc->{directory} || '';
        if(!length($dir) || substr($dir,0,1) ne '/') {
            my $phdir=$XAO::Base::projectsdir . "/" . $sitename;
            if(length($dir)) {
                $dir=$phdir . '/' . $dir;
            }
            else {
                $dir=$phdir;
            }
        }
        $dir.='/' . $uri;
        $dir=~s/\/{2,}/\//g;
        $r->filename($dir);
        ### $r->server->log_error("MAPTODIR: => $dir");
        return Apache::OK;
    }

    ##
    # We don't serve subrequests. Don't know why, but they produce
    # double output under some circumstances.
    #
    if(!MP2 && !$r->main) {
        $r->server->log_error("SUBREQ: ignoring (uri=$uri)");
        return Apache::DECLINED;
    }

    ##
    # We pass the knowledge along in the 'notes' table.
    #
    $r->pnotes(sitename  => $sitename);
    $r->pnotes(xaoweb    => $web);
    $r->pnotes(pagedesc  => $pagedesc);

    ##
    # Default is to install a content handler to produce actual
    # output. Under mod_perl 2.x (tested under 1.99 actually) it does
    # not work for some reason.
    #
    # Besides, it could be more optimal to have two always present
    # handlers instead of pushing/popping automatically.
    #
    my $htype=lc($r->dir_config('HandlerType') || 'auto');
    if($htype eq 'auto') {
        $r->push_handlers(PerlHandler => \&handler_content);
        ### $r->server->log_error("TRANS: auto (uri=$uri)");
        return Apache::DECLINED;
    }
    elsif($htype eq 'static') {
        ### $r->server->log_error("TRANS: static (uri=$uri)");
        return Apache::DECLINED;
    }
    else {
        return server_error($r,"Unknown HandlerType '$htype'");
    }
}

###############################################################################

sub handler_content ($) {
    my $r=shift;

    ##
    # Getting the data. If there is no sitename then trans handler
    # was not executed or has declined, so we do not need to do anything.
    #
    my $uri=$r->uri;
    ### $r->server->log_error("CONTENT: uri=$uri");
    my $sitename=$r->pnotes('sitename') ||
        return Apache::DECLINED;
    my $web=$r->pnotes('xaoweb');
    my $pagedesc=$r->pnotes('pagedesc');

    ##
    # It happens on some sub-requests went wrong. Noticed on
    # Apache::Status for instance.
    #
    return Apache::DECLINED unless $web;

    ##
    # Executing
    #
    $web->execute(
        path        => $uri,
        apache      => $r,
        pagedesc    => $pagedesc,
    );

    return Apache::OK;
}

###############################################################################

sub server_error ($$;$) {
    my ($r,$name,$desc)=@_;

    $desc=$name unless $desc;

    $r->server->log_error("*ERROR: Apache::XAO - $name");
    $r->custom_response(SERVER_ERROR,"<H2>XAO::Web System Error: $name</H2>\n$desc");
    return SERVER_ERROR;
}

###############################################################################
1;
__END__

=head1 EXPORTS

Nothing.

=head1 AUTHOR

Copyright (c) 2003 XAO, Inc.

Andrew Maltsev <am@xao.com>.

=head1 SEE ALSO

Recommended reading:
L<XAO::Web::Intro>,
L<XAO::Web>,
L<XAO::DO::Config>,
L<Apache>.
