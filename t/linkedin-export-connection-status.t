use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Cwd qw(getcwd);
use File::Temp qw(tempdir);
use Test::More;

use App::CPANToLinkedIn;

my @mock_releases = (
    {
        distribution => 'Dist-Connected',
        author       => 'FOOBAR',
    },
    {
        distribution => 'Dist-Not-Connected',
        author       => 'SOMEONEELSE',
    },
);

my %mock_author_names = (
    FOOBAR      => 'Foo Bar',
    SOMEONEELSE => 'Different Person',
);

my $stdout = '';
{
    no warnings 'redefine';

    local *App::CPANToLinkedIn::create_metacpan_client = sub { return bless {}, 'Local::MetaCPAN' };
    local *App::CPANToLinkedIn::fetch_recent_releases = sub { return \@mock_releases };
    local *App::CPANToLinkedIn::fetch_author_name = sub {
        my (undef, $author_id) = @_;
        return $mock_author_names{$author_id} // '';
    };

    open my $out_fh, '>', \$stdout or die "Could not open in-memory STDOUT: $!";
    local *STDOUT = $out_fh;

    is(
        App::CPANToLinkedIn::run('--count', 2, '--linkedin-export', "$Bin/../linkedin-export"),
        0,
        'run succeeds with mocked releases and LinkedIn export',
    );
}

my @lines = split /\n/, $stdout;
is scalar @lines, 3, 'prints header and two result rows';

is(
    $lines[0],
    "distribution\tauthor_id\tauthor_name\tlinkedin_profile\tconnection_status",
    'prints expected TSV header',
);

is_deeply(
    [ split /\t/, $lines[1], -1 ],
    [
        'Dist-Connected',
        'FOOBAR',
        'Foo Bar',
        'https://www.linkedin.com/in/foobar',
        'connected',
    ],
    'author listed in Connections.csv is reported connected',
);

is_deeply(
    [ split /\t/, $lines[2], -1 ],
    [
        'Dist-Not-Connected',
        'SOMEONEELSE',
        'Different Person',
        '',
        'not_found',
    ],
    'author missing from Connections.csv is reported as not found',
);

my $tempdir = tempdir(CLEANUP => 1);
my $cwd = getcwd();
chdir $tempdir or die "Could not chdir to $tempdir: $!";
open my $exclude_fh, '>:encoding(UTF-8)', 'exclude.csv'
    or die "Could not create exclude.csv: $!";
print {$exclude_fh} "FOOBAR,already_checked\n";
close $exclude_fh;

$stdout = '';
{
    no warnings 'redefine';

    local *App::CPANToLinkedIn::create_metacpan_client = sub { return bless {}, 'Local::MetaCPAN' };
    local *App::CPANToLinkedIn::fetch_recent_releases = sub { return \@mock_releases };
    local *App::CPANToLinkedIn::fetch_author_name = sub {
        my (undef, $author_id) = @_;
        return $mock_author_names{$author_id} // '';
    };

    open my $out_fh, '>', \$stdout or die "Could not open in-memory STDOUT: $!";
    local *STDOUT = $out_fh;

    is(
        App::CPANToLinkedIn::run('--count', 2, '--linkedin-export', "$Bin/../linkedin-export"),
        0,
        'run succeeds with exclude.csv present',
    );
}
chdir $cwd or die "Could not restore current directory to $cwd: $!";

@lines = split /\n/, $stdout;
is_deeply(
    [ split /\t/, $lines[1], -1 ],
    [
        'Dist-Connected',
        'FOOBAR',
        'Foo Bar',
        '',
        'excluded',
    ],
    'author listed in exclude.csv is skipped',
);

done_testing();
