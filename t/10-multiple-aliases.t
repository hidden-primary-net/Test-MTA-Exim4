#!/usr/bin/perl

use strict;
use warnings;
use File::Spec;
use File::Temp;
use FindBin qw< $Bin >;
use Try::Tiny;

use Test::More;
use Test::MTA::Exim4;

my ( $exim_binary, $exim_cfg_template, $tempdir, $exim_cfg, $aliasfile, $mailboxfile, @domains, %mbs, %als );

BEGIN {
    my $success = try {
        for ( $ENV{DEFAULT_EXIM_PATH}, qw< /usr/local/sbin/exim4 /usr/local/sbin/exim /usr/sbin/exim4 /usr/sbin/exim > )
        {
            next
                unless $_;
            if (-e) {
                $exim_binary = $_;
                last;
            }
        }
        die q(Unable to find exim binary)
            unless $exim_binary;

        $exim_cfg_template = File::Spec->catfile( $Bin => q(exim.conf.tmpl) );
        $tempdir           = File::Temp->newdir( CLEANUP => 1 );
        $exim_cfg          = File::Spec->catfile( $tempdir => q(exim.conf) );
        $aliasfile         = File::Spec->catfile( $tempdir => q(aliases) );
        $mailboxfile       = File::Spec->catfile( $tempdir => q(mailboxes) );

        @domains = qw<
            example1.test1
            example2.test2
            example3.test3
        >;

        ##  construct mailboxes
        my ( $mailbox1, $mailbox2, $mailbox3 ) = (
            join( q(@), q(ac1), $domains[0] ),
            join( q(@), q(ac2), $domains[0] ),
            join( q(@), q(ac3), $domains[1] )
        );
        my @mailboxes = (
            join( q(:), $mailbox1, File::Spec->catdir( $tempdir => q(ac1) ), ),
            join( q(:), $mailbox2, File::Spec->catdir( $tempdir => q(ac2) ), ),
            join( q(:), $mailbox3, File::Spec->catdir( $tempdir => q(ac3) ), ),
        );
        %mbs = map {
            my ( $mb, undef ) = split /:/, $_, 2;
            ( $mb => { router => q(mailbox), transport => q(mailbox), discarded => 0, ok => 1, } )
        } @mailboxes;

        ##  construct some alias edge cases
        my ( $alias1, $alias2, $alias3, $alias4, $alias5, $alias6, $alias7 ) = (
            join( q(@), q(al1), $domains[0] ),
            join( q(@), q(al2), $domains[0] ),
            join( q(@), q(al3), $domains[0] ),
            join( q(@), q(al4), $domains[1] ),
            join( q(@), q(al5), $domains[0] ),
            join( q(@), q(al6), $domains[2] ),
            join( q(@), q(al7), $domains[0] ),
        );
        my @aliases = (
            join( q(:), $alias1, $mailbox1 ),
            join( q(:), $alias2, $alias1 ),
            join( q(:), $alias3, $mailbox3 ),
            join( q(:), $alias4, $alias3 ),
            join( q(:), $alias5, $mailbox3 ),
            join( q(:), $alias6, $alias5 ),
            join( q(:), $alias7, join( q(,), $mailbox1, $mailbox2, $alias5 ) ),
        );
        %als = map {
            my ( $a, $d ) = split /:/, $_, 2;
            (   $a => [
                    map { { router => q(mailbox), transport => q(mailbox), discarded => 0, ok => 1, } } split /,/, $d
                ]
            );
        } @aliases;
        my $dl_local_domains = join q(:), @domains;

        note(qq(Reading template $exim_cfg_template...));
        open my $fh, q(<), $exim_cfg_template
            or die qq(Unable to open $exim_cfg_template for reading: $!);
        my $tmpl = do {
            local $/ = undef;
            <$fh>;
        };
        close $fh;
        $tmpl =~ s{\[%\s*LOCAL_DOMAIN_LIST\s*%]}{$dl_local_domains}g;
        $tmpl =~ s{\[%\s*ALIASFILE\s*%\]}{$aliasfile}g;
        $tmpl =~ s{\[%\s*MAILBOXFILE\s*%\]}{$mailboxfile}g;

        note(qq(Writing exim configfile $exim_cfg...));
        open $fh, q(>), $exim_cfg
            or die qq(Unable to open $exim_cfg for writing: $!);
        print $fh $tmpl;
        close $fh;

        note(qq(Writing exim aliasfile $aliasfile...));
        open $fh, q(>), $aliasfile
            or die qq(Unable to open $aliasfile for writing: $!);
        {
            local $" = $\ = qq(\n);
            print $fh qq(@aliases);
        }
        close $fh;

        note(qq(Writing exim mailboxfile $mailboxfile...));
        open $fh, q(>), $mailboxfile
            or die qq(Unable to open $mailboxfile for writing: $!);
        {
            local $" = $\ = qq(\n);
            print $fh qq(@mailboxes);
        }
        close $fh;
    }
    catch {
        diag(qq(Unable to prepare test configuration: $_));
        ()
    };
    plan skip_all => q(Problems creating test configuration)
        unless $success;
}

my $exim = Test::MTA::Exim4->new(
    {   exim_path   => $exim_binary,
        config_file => $exim_cfg,
        debug       => 0,
    }
);
while ( my ( $a, $d ) = each %mbs ) {
    $exim->routes_as_ok( $a => $d );
}
while ( my ( $a, $d ) = each %als ) {
    $exim->routes_as_ok( $a => $d );
}

done_testing();
