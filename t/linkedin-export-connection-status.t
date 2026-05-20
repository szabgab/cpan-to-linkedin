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

my $assert_summary = sub {
    my ($lines, $expected_total, $expected_unique, $expected_status_counts, $message) = @_;

    my %summary;
    my ($total_line) = grep { /^Total entries:/ } @{$lines};
    my ($unique_line) = grep { /^Unique authors:/ } @{$lines};

    like($total_line // '', qr/^Total entries: \d+\z/, "$message: total line present");
    like($unique_line // '', qr/^Unique authors: \d+\z/, "$message: unique line present");

    my ($total)  = ($total_line  // '') =~ /^Total entries: (\d+)\z/;
    my ($unique) = ($unique_line // '') =~ /^Unique authors: (\d+)\z/;
    is($total,  $expected_total,  "$message: total entries");
    is($unique, $expected_unique, "$message: unique authors");

    for my $line (@{$lines}) {
        next if $line !~ /^  ([^:]+):\s*(\d+)\z/;
        $summary{$1} = $2;
    }

    is_deeply(\%summary, $expected_status_counts, "$message: status counts");
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
is scalar @lines, 7, 'by default prints header, only not_found rows, and summary stats';

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

$assert_summary->(
    \@lines,
    2,
    2,
    {
        connected => 1,
        excluded  => 0,
        not_found => 1,
    },
    'default output',
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
is scalar @lines, 8, '--all prints header, all result rows, and summary stats';

is_deeply(
    [ split /\t/, $lines[1], -1 ],
    [
        $lead_columns->('FOOBAR', 'Dist-Connected', 'Foo Bar', 'connected'),
        'https://www.linkedin.com/in/foobar',
    ],
    '--all includes connected entries',
);

$assert_summary->(
    \@lines,
    2,
    2,
    {
        connected => 1,
        excluded  => 0,
        not_found => 1,
    },
    '--all output',
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
is scalar @lines, 9, 'excluded+connected author prints by default (rows + summary stats)';

is_deeply(
    [ split /\t/, $lines[1], -1 ],
    [
        $lead_columns->('FOOBAR', 'Dist-Connected', 'Foo Bar', 'excluded_connected'),
        'https://www.linkedin.com/in/foobar',
    ],
    'author in exclude.csv who is also connected is reported as excluded_connected with profile URL',
);

$assert_summary->(
    \@lines,
    2,
    2,
    {
        connected          => 0,
        excluded           => 0,
        excluded_connected => 1,
        not_found          => 1,
    },
    'default output with excluded_connected',
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
is scalar @lines, 6, 'excluded-but-not-connected default output still prints summary stats';

$assert_summary->(
    \@lines,
    1,
    1,
    {
        connected => 0,
        excluded  => 1,
        not_found => 0,
    },
    'default output with excluded author only',
);

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
is scalar @lines, 7, 'excluded-but-not-connected with --all prints row and summary stats';

is_deeply(
    [ split /\t/, $lines[1], -1 ],
    [
        $lead_columns->('SOMEONEELSE', 'Dist-Excluded-Only', 'Different Person', 'excluded'),
        '',
    ],
    'author in exclude.csv who is not connected is reported as excluded with --all',
);

$assert_summary->(
    \@lines,
    1,
    1,
    {
        connected => 0,
        excluded  => 1,
        not_found => 0,
    },
    '--all output with excluded author only',
);

my @emoji_name_releases = (
    {
        distribution => 'Dist-Emoji-Jane',
        author       => 'JANEDOE',
    },
    {
        distribution => 'Dist-Emoji-Joe',
        author       => 'JOEOTHER',
    },
);
my %emoji_author_names = (
    JANEDOE  => 'Jane Doe',
    JOEOTHER => 'Joe Other',
);

$stdout = '';
{
    no warnings 'redefine';

    local *App::CPANToLinkedIn::create_metacpan_client = sub { return bless {}, 'Local::MetaCPAN' };
    local *App::CPANToLinkedIn::fetch_recent_releases = sub { return \@emoji_name_releases };
    local *App::CPANToLinkedIn::fetch_author_name = sub {
        my (undef, $author_id) = @_;
        return $emoji_author_names{$author_id} // '';
    };

    open my $out_fh, '>', \$stdout or die "Could not open in-memory STDOUT: $!";
    local *STDOUT = $out_fh;

    is(
        App::CPANToLinkedIn::run('--count', 2, '--all', '--linkedin-export', "$Bin/../linkedin-export"),
        0,
        'run succeeds when LinkedIn export names include emojis',
    );
}

@lines = split /\n/, $stdout;
is scalar @lines, 8, 'emoji-inclusive LinkedIn names are matched as connected and include summary stats';

is_deeply(
    [ split /\t/, $lines[1], -1 ],
    [
        $lead_columns->('JANEDOE', 'Dist-Emoji-Jane', 'Jane Doe', 'connected'),
        'https://www.linkedin.com/in/janedoe',
    ],
    'matches author name to LinkedIn first name containing emoji suffix',
);

$assert_summary->(
    \@lines,
    2,
    2,
    {
        connected => 2,
        excluded  => 0,
        not_found => 0,
    },
    'emoji-name output',
);

is_deeply(
    [ split /\t/, $lines[2], -1 ],
    [
        $lead_columns->('JOEOTHER', 'Dist-Emoji-Joe', 'Joe Other', 'connected'),
        'https://www.linkedin.com/in/joeother',
    ],
    'matches author name to LinkedIn first name containing emoji prefix',
);

done_testing();
