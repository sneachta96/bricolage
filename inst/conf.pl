#!/usr/bin/perl -w

=head1 NAME

conf.pl - installation script to write configuration files in conf/

=head1 VERSION

$Revision: 1.9 $

=head1 DATE

$Date: 2002-11-13 22:58:52 $

=head1 DESCRIPTION

This script is called by "make install" to write out configuration
files based on information gathered by "make".  Rather than using
template files, conf.pl uses the sample configuration files directly.

=head1 AUTHOR

Sam Tregar <stregar@about-inc.com>

=head1 SEE ALSO

L<Bric::Admin>

=cut


use strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use Bric::Inst qw(:all);
use File::Spec::Functions qw(:ALL);
use File::Copy qw(copy);
use Time::HiRes qw(time);
use Digest::MD5 qw(md5_base64);
use Data::Dumper;

# read in user config settings
our $CONFIG;
do "./config.db" or die "Failed to read config.db : $!";
our $AP;
do "./apache.db" or die "Failed to read apache.db : $!";
our $PG;
do "./postgres.db" or die "Failed to read postgres.db : $!";
our $REQ;
do "./required.db" or die "Failed to read required.db : $!";

# check if we're upgrading
our $UPGRADE;
$UPGRADE = 1 if $ARGV[0] and $ARGV[0] eq 'UPGRADE';

# get version from Makefile
our $VERSION = $ARGV[1];

print "\n\n==> Creating Bricolage Conf Files <==\n\n";

create_bricolage_conf() unless $UPGRADE;
create_httpd_conf()     unless $UPGRADE;
create_install_db();

print "\n\n==> Finished Creating Bricolage Conf Files <==\n\n";
exit 0;

# create conf/bricolage.conf
sub create_bricolage_conf {
    # read in default config file
    print "Reading conf/bricolage.conf...\n";
    open(CONF, "conf/bricolage.conf") 
	or die "Cannot read conf/bricolage.conf : $!";
    my $conf = join('',<CONF>);
    close(CONF);

    # lots of regexes to come
    study($conf);

    # simple settings
    set_bric_conf_var(\$conf, APACHE_BIN      => $REQ->{APACHE_EXE});
    set_bric_conf_var(\$conf, LISTEN_PORT     => $AP->{port});
    set_bric_conf_var(\$conf, SSL_PORT        => $AP->{ssl_port});
    set_bric_conf_var(\$conf, SSL_ENABLE      => $AP->{ssl} ? $AP->{ssl} : 'Off');
    set_bric_conf_var(\$conf, SSL_CERTIFICATE_FILE	=> $AP->{ssl_cert});
    set_bric_conf_var(\$conf, SSL_CERTIFICATE_KEY_FILE	=> $AP->{ssl_key});
    set_bric_conf_var(\$conf, SYS_USER        => $AP->{user});
    set_bric_conf_var(\$conf, SYS_GROUP       => $AP->{group});
    set_bric_conf_var(\$conf, DB_NAME         => $PG->{db_name});
    set_bric_conf_var(\$conf, DBI_USER        => $PG->{sys_user});
    set_bric_conf_var(\$conf, DBI_PASS        => $PG->{sys_pass});


    # path settings
    my $root = $CONFIG->{BRICOLAGE_ROOT};
    set_bric_conf_var(\$conf, APACHE_CONF     => catfile($root, "conf", "httpd.conf"));
    set_bric_conf_var(\$conf, MASON_COMP_ROOT => $CONFIG->{MASON_COMP_ROOT});
    set_bric_conf_var(\$conf, MASON_DATA_ROOT => $CONFIG->{MASON_DATA_ROOT});
    set_bric_conf_var(\$conf, BURN_ROOT       => catdir($CONFIG->{MASON_DATA_ROOT}, "burn"));
    set_bric_conf_var(\$conf, TEMP_DIR        => $CONFIG->{TEMP_DIR});
			  
    # setup auth secret to some fairly random string
    srand (time ^ $$ ^ unpack "%L*", `ps axww | gzip`);
    set_bric_conf_var(\$conf, AUTH_SECRET     => md5_base64(rand()) . 
		                                 md5_base64(rand()) .
		                                 md5_base64(rand()) .
		                                 md5_base64(rand()) .
		                                 md5_base64(rand()));

    # write out new conf in final resting place
    print "Writing $CONFIG->{BRICOLAGE_ROOT}/conf/bricolage.conf...\n";
    open(CONF, ">$CONFIG->{BRICOLAGE_ROOT}/conf/bricolage.conf")
	or die "Cannot open $CONFIG->{BRICOLAGE_ROOT}/conf/bricolage.conf : $!";
    print CONF $conf;
    close CONF;

}

# changes the setting of a single conf var in $$conf
sub set_bric_conf_var {
    my ($conf, $var, $val) = @_;
    unless ($$conf =~ s/^(\s*$var\s+=\s*).*$/$1$val/mi) {
	hard_fail("Unable to set bricolage.conf variable $var to \"$val\".");
    }
}

# create conf/httpd.conf
sub create_httpd_conf {
    # read in default httpd.conf file
    print "Reading conf/httpd.conf...\n";
    open(HTTPD, "conf/httpd.conf") 
	or die "Cannot read conf/httpd.conf : $!";
    my $httpd = join('',<HTTPD>);
    close(HTTPD);


    # lots of regexes to come
    study($httpd);

    # simple settings
    my $listen80 = set_httpd_var(\$httpd,
			   Listen       => $AP->{port});
    set_httpd_var(\$httpd, User         => $AP->{user});
    set_httpd_var(\$httpd, Group        => $AP->{group});
    set_httpd_var(\$httpd, ServerName   => $AP->{server_name});

    # paths
    my $root    = $CONFIG->{BRICOLAGE_ROOT};
    my $ap_root = $AP->{HTTPD_ROOT};
    my $log     = $CONFIG->{LOG_DIR};

    set_httpd_var(\$httpd, ServerRoot      => $ap_root);
    set_httpd_var(\$httpd, TypesConfig     => $AP->{types_config} ||
		  catfile($ap_root, "conf", "mime.types"));
    set_httpd_var(\$httpd, DocumentRoot    => $CONFIG->{MASON_COMP_ROOT});
    set_httpd_var(\$httpd, PidFile         => $CONFIG->{PID_FILE});
    set_httpd_var(\$httpd, ErrorLog        => catfile($log, "error_log"));
    set_httpd_var(\$httpd, CustomLog       => catfile($log,
						      "access_log combined"));

    # httpsd must listen on another port

    if ($AP->{ssl}) {
	my $rm = '_random_marker_123454321_' . $$;
	$httpd =~ s/$listen80/$rm/;
	set_httpd_var(\$httpd, Listen => $AP->{ssl_port}, 'set all of them');
	$httpd =~ s/$rm/$listen80/;
    }

    # take a stab at SSL settings if ssl is on.  This stuff is
    # probably wrong and probably needs to be probed for explicitly
    # in apache.pl.

    if ($AP->{ssl} =~ /apache_ssl/) {

       my $gc_loc = $AP->{SUEXEC_BIN} || '';
       $gc_loc =~ s/suexec/gcache/;
       set_httpd_var(\$httpd, SSLCacheServerPath => catfile($gc_loc));
       set_httpd_var(\$httpd, SSLCacheServerPort => catfile($log, "gcache_port"));

    } elsif ($AP->{ssl} =~ /mod_ssl/) {

	set_httpd_var(\$httpd, SSLSessionCache => "dbm:" . 
		      catfile($log, "ssl_scache"));
	set_httpd_var(\$httpd, SSLMutex        => "file:" .
		      catfile($log, "ssl_mutex"));
	set_httpd_var(\$httpd, SSLLog          => catfile($log,
							  "ssl_engine_log"));
    }

    # DSO Apache's need that sweet DSO spike in the vein just to get
    # up in the morning
    if ($AP->{dso}) {
	my $dso_section = "# Load DSOs\n\n";
	foreach my $mod (qw(perl log_config mime alias ssl apache_ssl)) {
	    # static modules need no load
	    next if exists $AP->{static_modules}{"mod_$mod"};
	    next if $mod eq 'apache_ssl' && exists $AP->{static_modules}{apache_ssl};

	    if ($mod eq 'log_config') {
		# I want to kill whoever decided this was a good idea
		$dso_section .= "LoadModule \t config_log_module " . 
		    $AP->{load_modules}{"${mod}_module"} . "\n";
		$dso_section .= "AddModule \t mod_$mod.c\n\n";
	    } elsif ($mod eq 'apache_ssl') {
		next unless $AP->{ssl} =~ /apache_ssl/;
		$dso_section .= "LoadModule \t ${mod}_module " .
		    $AP->{load_modules}{"${mod}_module"} . "\n";
		$dso_section .= "AddModule \t apache_ssl.c\n\n";
	    } else {
		next if $mod eq 'ssl' && $AP->{ssl} !~ /mod_ssl/;
		$dso_section .= "LoadModule \t ${mod}_module " . 
		    $AP->{load_modules}{"${mod}_module"} . "\n";
		$dso_section .= "AddModule \t mod_$mod.c\n\n";
	    }
	}
   
	# put DSO loads at the top.  This could be prettier.
	$httpd = $dso_section . "\n\n" . $httpd;
    }

    # write out new httpd.conf in final resting place
    print "Writing $CONFIG->{BRICOLAGE_ROOT}/conf/httpd.conf...\n";
    open(HTTPD, ">$CONFIG->{BRICOLAGE_ROOT}/conf/httpd.conf")
	or die "Cannot open $CONFIG->{BRICOLAGE_ROOT}/conf/httpd.conf : $!";
    print HTTPD $httpd;
    close HTTPD;
}

# changes the setting of multiple or single httpd vars in $$httpd
sub set_httpd_var {
    my ($httpd, $var, $val, $global) = @_;
    if ($global && $$httpd =~ s/^(\s*$var\s+).*$/$1$val/gmi) {
	return "$var $val";
    } elsif ($$httpd =~ s/^(\s*$var\s+).*$/$1$val/mi) {
	return $1.$val;
    } else {
	hard_fail("Unable to set httpd.conf variable $var to \"$val\".");
    }
}

# create the install.db file used by "make upgrade"
sub create_install_db {
    # write out new httpd.conf in final resting place
    print "Writing $CONFIG->{BRICOLAGE_ROOT}/conf/install.db...\n";
    open(DB, ">$CONFIG->{BRICOLAGE_ROOT}/conf/install.db")
	or die "Cannot open $CONFIG->{BRICOLAGE_ROOT}/conf/httpd.conf : $!";
    print DB Data::Dumper->Dump([{ CONFIG  => $CONFIG,
				   AP      => $AP,
				   PG      => $PG,
				   REQ     => $REQ,
				   VERSION => $VERSION }],
				['INSTALL']);
    close DB;
}
