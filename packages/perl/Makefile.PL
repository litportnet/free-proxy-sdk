use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'WebService::Litportnet::FreeProxy',
    VERSION_FROM     => 'lib/WebService/Litportnet/FreeProxy.pm',
    ABSTRACT_FROM    => 'lib/WebService/Litportnet/FreeProxy.pm',
    AUTHOR           => 'Litport <litport@cpan.org>',
    LICENSE          => 'mit',
    MIN_PERL_VERSION => '5.016',
    PREREQ_PM        => {
        'HTTP::Tiny'   => 0,
        'JSON::PP'     => 0,
        'Time::Local'  => 0,
        'Scalar::Util' => 0,
        'POSIX'        => 0,

        # The default snapshot endpoint is https, and HTTP::Tiny needs both of
        # these to speak TLS at all.
        'IO::Socket::SSL' => '1.42',
        'Net::SSLeay'     => '1.49',
    },
    TEST_REQUIRES => {
        'Test::More' => 0,
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            homepage   => 'https://litport.net/free-proxy',
            repository => {
                type => 'git',
                url  => 'https://github.com/litportnet/free-proxy-sdk.git',
                web  => 'https://github.com/litportnet/free-proxy-sdk/tree/main/packages/perl',
            },
            bugtracker => {
                web => 'https://github.com/litportnet/free-proxy-sdk/issues',
            },
        },
        x_documentation => 'https://litport.net/docs/free-proxy-api',
    },
);
