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
is scalar @lines, 2, 'by default prints header and only not_found rows';

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
is scalar @lines, 3, '--all prints header and all result rows';

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
            App::CPANToLinkedIn::run('--count', 2, '--linkedin-export', "$Bin/../linkedin-export"),
            0,
            'run succeeds with exclude.csv present (excluded+connected author)',
        );
    }
    1;
} or $run_error = $@;
chdir $cwd or die "Could not restore current directory to $cwd: $!";
die "Test failed during exclude.csv evaluation: $run_error" if $run_error;

@lines = split /\n/, $stdout;
is scalar @lines, 3, 'excluded+connected author prints by default (header + excluded_connected + not_found)';

is_deeply(
    [ split /\t/, $lines[1], -1 ],
    [
        $lead_columns->('FOOBAR', 'Dist-Connected', 'Foo Bar', 'excluded_connected'),
        'https://www.linkedin.com/in/foobar',
    ],
    'author in exclude.csv who is also connected is reported as excluded_connected with profile URL',
);

is_deeply(
    [ split /\t/, $lines[2], -1 ],
    [
        $lead_columns->('SOMEONEELSE', 'Dist-Not-Connected', 'Different Person', 'not_found'),
        'https://www.linkedin.com/search/results/all/?keywords=Different+Person',
    ],
    'not_found author still printed by default alongside excluded_connected',
);

# Test: author in exclude.csv who is NOT connected stays 'excluded' and is not printed by default
my $tempdir2 = tempdir(CLEANUP => 1);
chdir $tempdir2 or die "Could not chdir to $tempdir2: $!";
my @releases_not_connected = (
    {
        distribution => 'Dist-Excluded-Only',
        author       => 'SOMEONEELSE',
    },
);
my $run_error2;
eval {
    open my $exclude_fh2, '>:encoding(UTF-8)', 'exclude.csv'
        or die "Could not create exclude.csv: $!";
    print {$exclude_fh2} "SOMEONEELSE,already_checked\n";
    close $exclude_fh2;

    $stdout = '';
    {
        no warnings 'redefine';

        local *App::CPANToLinkedIn::create_metacpan_client = sub { return bless {}, 'Local::MetaCPAN' };
        local *App::CPANToLinkedIn::fetch_recent_releases = sub { return \@releases_not_connected };
        local *App::CPANToLinkedIn::fetch_author_name = sub {
            my (undef, $author_id) = @_;
            return $mock_author_names{$author_id} // '';
        };

        open my $out_fh, '>', \$stdout or die "Could not open in-memory STDOUT: $!";
        local *STDOUT = $out_fh;

        is(
            App::CPANToLinkedIn::run('--count', 1, '--linkedin-export', "$Bin/../linkedin-export"),
            0,
            'run succeeds with excluded-but-not-connected author',
        );
    }
    1;
} or $run_error2 = $@;
chdir $cwd or die "Could not restore current directory to $cwd: $!";
die "Test failed during excluded-not-connected evaluation: $run_error2" if $run_error2;

@lines = split /\n/, $stdout;
is scalar @lines, 1, 'excluded-but-not-connected author is not printed by default (only header)';

$stdout = '';
chdir $tempdir2 or die "Could not chdir to $tempdir2: $!";
eval {
    {
        no warnings 'redefine';

        local *App::CPANToLinkedIn::create_metacpan_client = sub { return bless {}, 'Local::MetaCPAN' };
        local *App::CPANToLinkedIn::fetch_recent_releases = sub { return \@releases_not_connected };
        local *App::CPANToLinkedIn::fetch_author_name = sub {
            my (undef, $author_id) = @_;
            return $mock_author_names{$author_id} // '';
        };

        open my $out_fh, '>', \$stdout or die "Could not open in-memory STDOUT: $!";
        local *STDOUT = $out_fh;

        is(
            App::CPANToLinkedIn::run('--count', 1, '--all', '--linkedin-export', "$Bin/../linkedin-export"),
            0,
            'run succeeds with --all for excluded-but-not-connected author',
        );
    }
    1;
} or $run_error2 = $@;
chdir $cwd or die "Could not restore current directory to $cwd: $!";
die "Test failed during excluded-not-connected --all evaluation: $run_error2" if $run_error2;

@lines = split /\n/, $stdout;
is scalar @lines, 2, 'excluded-but-not-connected author printed with --all (header + excluded)';

is_deeply(
    [ split /\t/, $lines[1], -1 ],
    [
        $lead_columns->('SOMEONEELSE', 'Dist-Excluded-Only', 'Different Person', 'excluded'),
        '',
    ],
    'author in exclude.csv who is not connected is reported as excluded with --all',
);

done_testing();
