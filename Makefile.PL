use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'App::CPANToLinkedIn',
    VERSION_FROM => 'lib/App/CPANToLinkedIn.pm',
    PREREQ_PM    => {
        'MetaCPAN::Client' => 0,
        'HTTP::Tiny'       => 0,
        'Getopt::Long'     => 0,
    },
    EXE_FILES    => ['script/cpan-to-linkedin'],
    test         => { TESTS => 't/*.t' },
);
