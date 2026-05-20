use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Cwd qw(getcwd);
use File::Temp qw(tempdir);
use Test::More;

use App::CPANToLinkedIn;

my $lead_columns_format = "%-10s %-35s %-30s %-15s";
my $lead_columns = sub {
    my ($author_id, $distribution, $author_name, $connection_status) = @_;
    return sprintf(
        $lead_columns_format,
        ($author_id // ''),
        substr($distribution // '', 0, 35),
        ($author_name // ''),
        ($connection_status // ''),
    );
};

my @mock_releases = (
    {
        distribution => 'Dist-Connected',
        author       => 'FOOBAR',
    },
    {
        distribution => 'Dist-Not-Connected',
        author       => 'SOMEONEELSE',
    },
    {
        distribution => 'Dist-Emoji-Suffix',
        author       => 'JANEDOE',
    },
    {
        distribution => 'Dist-Emoji-Prefix',
        author       => 'JOEOTHER',
    },
);

my %mock_author_names = (
    FOOBAR      => 'Foo Bar',
    SOMEONEELSE => 'Different Person',
    JANEDOE     => 'Jane Doe',
    JOEOTHER    => 'Joe Other',
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
is scalar @lines, 2, 'by default prints header and only not_found row';

is(
    $lines[0],
    sprintf(
        "${lead_columns_format}\tlinkedin_profile",
        qw(author_id distribution author_name connection_status)
    ),
    'prints expected fixed-width header',
);

is_deeply(
    [ split /\t/, $lines[1], -1 ],
    [
        $lead_columns->('SOMEONEELSE', 'Dist-Not-Connected', 'Different Person', 'not_found'),
        'https://www.linkedin.com/search/results/all/?keywords=Different+Person',
    ],
    'default output includes not_found entries with a LinkedIn search URL',
);

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
        App::CPANToLinkedIn::run('--count', 2, '--all', '--linkedin-export', "$Bin/../linkedin-export"),
        0,
        'run succeeds with --all and mocked releases',
    );
}

@lines = split /\n/, $stdout;
is scalar @lines, 5, '--all prints header and all result rows';

is_deeply(
    [ split /\t/, $lines[1], -1 ],
    [
        $lead_columns->('FOOBAR', 'Dist-Connected', 'Foo Bar', 'connected'),
        'https://www.linkedin.com/in/foobar',
    ],
    '--all includes connected entries',
);

is_deeply(
    [ split /\t/, $lines[2], -1 ],
    [
        $lead_columns->('SOMEONEELSE', 'Dist-Not-Connected', 'Different Person', 'not_found'),
        'https://www.linkedin.com/search/results/all/?keywords=Different+Person',
    ],
    '--all includes not_found entries with a LinkedIn search URL',
);

is_deeply(
    [ split /\t/, $lines[3], -1 ],
    [
        $lead_columns->('JANEDOE', 'Dist-Emoji-Suffix', 'Jane Doe', 'connected'),
        'https://www.linkedin.com/in/janedoe',
    ],
    'author name matches a LinkedIn connection when CSV name has emoji suffix',
);

is_deeply(
    [ split /\t/, $lines[4], -1 ],
    [
        $lead_columns->('JOEOTHER', 'Dist-Emoji-Prefix', 'Joe Other', 'connected'),
        'https://www.linkedin.com/in/joeother',
    ],
    'author name matches a LinkedIn connection when CSV name has emoji prefix',
);

my $tempdir = tempdir(CLEANUP => 1);
my $cwd = getcwd();
chdir $tempdir or die "Could not chdir to $tempdir: $!";
my $run_error;
eval {
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
            App::CPANToLinkedIn::run('--count', 2, '--all', '--linkedin-export', "$Bin/../linkedin-export"),
            0,
            'run succeeds with exclude.csv present and --all',
        );
    }
    1;
} or $run_error = $@;
chdir $cwd or die "Could not restore current directory to $cwd: $!";
die "Test failed during exclude.csv evaluation: $run_error" if $run_error;

@lines = split /\n/, $stdout;
is scalar @lines, 5, 'exclude.csv run with --all prints header and all result rows';

is_deeply(
    [ split /\t/, $lines[1], -1 ],
    [
        $lead_columns->('FOOBAR', 'Dist-Connected', 'Foo Bar', 'excluded'),
        '',
    ],
    'author listed in exclude.csv is reported as excluded with --all',
);

is_deeply(
    [ split /\t/, $lines[3], -1 ],
    [
        $lead_columns->('JANEDOE', 'Dist-Emoji-Suffix', 'Jane Doe', 'connected'),
        'https://www.linkedin.com/in/janedoe',
    ],
    'emoji-suffix name still matches in --all run with exclude.csv',
);

is_deeply(
    [ split /\t/, $lines[4], -1 ],
    [
        $lead_columns->('JOEOTHER', 'Dist-Emoji-Prefix', 'Joe Other', 'connected'),
        'https://www.linkedin.com/in/joeother',
    ],
    'emoji-prefix name still matches in --all run with exclude.csv',
);

done_testing();
