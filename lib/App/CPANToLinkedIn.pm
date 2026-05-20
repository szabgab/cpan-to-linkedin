package App::CPANToLinkedIn;

use strict;
use warnings;

use Exporter 'import';
use Getopt::Long qw(GetOptionsFromArray);
use HTTP::Tiny;
use Text::CSV;

our $VERSION = '0.1';

our @EXPORT_OK = qw(
    create_metacpan_client
    load_linkedin_connections
    parse_args
    releases_from_resultset
    first_linkedin_profile_url
    connection_status_from_search_html
    linkedin_search_url
    run
);

sub parse_args {
    my (@argv) = @_;

    my %options = (
        count      => 20,
        user_agent => "cpan-to-linkedin/$VERSION",
    );

    GetOptionsFromArray(
        \@argv,
        'count|n=i'              => \$options{count},
        'all'                    => \$options{all},
        'linkedin-cookie=s'      => \$options{linkedin_cookie},
        'linkedin-cookie-file=s' => \$options{linkedin_cookie_file},
        'linkedin-export=s'      => \$options{linkedin_export},
        'linkedin-search'        => \$options{linkedin_search},
        'help'                   => \$options{help},
    ) or die usage();

    die "--count must be a positive integer\n" if $options{count} < 1;

    my $csv_mode      = defined $options{linkedin_export};
    my $linkedin_mode = $options{linkedin_search};
    my $has_cookie    = defined $options{linkedin_cookie}
                        || defined $options{linkedin_cookie_file};

    die "Cannot use --linkedin-export together with --linkedin-search / --linkedin-cookie / --linkedin-cookie-file.\n"
        . usage()
        if !$options{help} && $csv_mode && ($linkedin_mode || $has_cookie);

    die "--linkedin-cookie and --linkedin-cookie-file require --linkedin-search.\n"
        . usage()
        if !$options{help} && $has_cookie && !$linkedin_mode;

    die "Must specify exactly one workmode: --linkedin-export or --linkedin-search (with optional --linkedin-cookie / --linkedin-cookie-file).\n"
        . usage()
        unless $options{help} || $csv_mode || $linkedin_mode;

    $options{cookie_header} = _cookie_header(\%options);

    return \%options;
}

sub usage {
    return <<'END_USAGE';
Usage: cpan-to-linkedin [--count N] --linkedin-export DIR
       cpan-to-linkedin [--count N] --linkedin-search [--linkedin-cookie COOKIE]
       cpan-to-linkedin [--count N] --linkedin-search [--linkedin-cookie-file FILE]

Exactly one workmode must be selected:
  --linkedin-export DIR     Use the LinkedIn CSV export to look up connections.
  --linkedin-search         Search the LinkedIn website directly.

These two modes are mutually exclusive.

Options:
  --count, -n               Number of recent CPAN releases to inspect.
                            Defaults to 20.
  --all                     Show all results. By default only entries with
                            connection_status "not_found" are printed.
  --linkedin-export         Path to the folder containing the LinkedIn export
                            files (e.g. Connections.csv). When provided, the
                            script looks up authors in the exported connections
                            instead of searching the LinkedIn website.
  --linkedin-search         Search the LinkedIn website for each author.
                            Connection status is reported as "unknown" unless
                            a cookie is also provided.
  --linkedin-cookie         Raw LinkedIn Cookie header for authenticated
                            searches (requires --linkedin-search).
  --linkedin-cookie-file    File containing the raw LinkedIn Cookie header
                            (requires --linkedin-search).
  --help                    Show this help.
END_USAGE
}

sub run {
    my (@argv) = @_;
    my $options = parse_args(@argv);

    if ($options->{help}) {
        print usage();
        return 0;
    }

    my $http = HTTP::Tiny->new(
        agent      => $options->{user_agent},
        verify_SSL => 1,
        timeout    => 30,
        default_headers => {
            Accept => 'application/json, text/html;q=0.9,*/*;q=0.8',
        },
    );
    my $mcpan = create_metacpan_client();

    my %connections_by_name;
    if ($options->{linkedin_export}) {
        my $connections = load_linkedin_connections($options->{linkedin_export});
        for my $c (@$connections) {
            my $name = lc(join(' ', grep { length $_ } $c->{first_name}, $c->{last_name}));
            $connections_by_name{$name} = $c if $name;
        }
    }

    my $releases = fetch_recent_releases($mcpan, $options->{count});
    my %author_cache;
    my $excluded_author_ids = load_excluded_pause_ids('exclude.csv');

    print sprintf(
        "%-10s %-35s %-30s %-15s\tlinkedin_profile\n",
        qw(author_id distribution author_name connection_status)
    );

    for my $release (@{$releases}) {
        my $author_id = $release->{author} // '';
        my $author_name = $author_cache{$author_id} ||= fetch_author_name($mcpan, $author_id);
        my ($profile_url, $connection_status);

        if ($excluded_author_ids->{$author_id}) {
            $connection_status = 'excluded';
        } elsif ($options->{linkedin_export}) {
            my $entry = $connections_by_name{lc($author_name || '')};
            if ($entry && $entry->{url}) {
                $profile_url       = $entry->{url};
                $connection_status = 'connected';
            } else {
                $connection_status = 'not_found';
            }
        } else {
            my $search_html = fetch_linkedin_search_html(
                $http,
                $author_name || $author_id,
                $options->{cookie_header},
            );
            $profile_url = first_linkedin_profile_url($search_html);
            $connection_status = 'not_found';

            if ($profile_url) {
                $connection_status = $options->{cookie_header}
                    ? connection_status_from_search_html($search_html)
                    : 'unknown';
            }
        }

        if (($connection_status // '') eq 'not_found') {
            $profile_url = linkedin_search_url($author_name || $author_id);
        }

        my $should_print = $options->{all} || ($connection_status // '') eq 'not_found';
        next if !$should_print;

        printf(
            "%-10s %-35s %-30s %-15s\t%s\n",
            ($author_id // ''),
            substr($release->{distribution} // '', 0, 35),
            ($author_name // ''),
            ($connection_status // ''),
            ($profile_url // ''),
        );
    }

    return 0;
}

sub load_excluded_pause_ids {
    my ($file) = @_;
    return {} if !$file || !-e $file;

    open my $fh, '<:encoding(UTF-8)', $file
        or die "Could not open $file: $!\n";

    my $csv = Text::CSV->new({ binary => 1 });
    my %excluded;

    while (my $fields = $csv->getline($fh)) {
        my $author_id = $fields->[0] // '';
        $author_id =~ s/^\s+|\s+\z//g;
        $author_id = uc($author_id);
        next if !$author_id;
        $excluded{$author_id} = 1;
    }

    close $fh;
    return \%excluded;
}

sub create_metacpan_client {
    eval { require MetaCPAN::Client; 1 }
        or die "MetaCPAN::Client is required. Install it with: cpanm MetaCPAN::Client\n";

    return MetaCPAN::Client->new();
}

sub fetch_recent_releases {
    my ($mcpan, $count) = @_;
    my $recent = $mcpan->recent($count);
    return releases_from_resultset($recent);
}

sub releases_from_resultset {
    my ($resultset) = @_;

    my @packages;
    while (my $release = $resultset->next) {
        push @packages, {
            distribution => $release->distribution,
            author       => $release->author,
            date         => $release->date,
        };
    }

    return \@packages;
}

sub fetch_author_name {
    my ($mcpan, $author_id) = @_;
    return '' if !$author_id;

    my $author = eval { $mcpan->author($author_id) };
    return '' if !$author;

    return $author->name || '';
}

sub load_linkedin_connections {
    my ($folder) = @_;
    my $file = "$folder/Connections.csv";

    open my $fh, '<:encoding(UTF-8)', $file
        or die "Could not open $file: $!\n";

    # Skip preamble lines until we reach the real CSV header
    my $header_line;
    while (my $line = <$fh>) {
        chomp $line;
        if ($line =~ /^First Name,/) {
            $header_line = $line;
            last;
        }
    }
    die "Could not find 'First Name' header in $file\n" unless defined $header_line;

    my $csv = Text::CSV->new({ binary => 1 });

    $csv->parse($header_line)
        or die "Could not parse header in $file\n";
    my @headers = $csv->fields();
    my %field_idx;
    for my $i (0 .. $#headers) {
        $field_idx{ $headers[$i] } = $i;
    }

    my @connections;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*$/;
        next unless $csv->parse($line);
        my @fields = $csv->fields();
        push @connections, {
            first_name   => $fields[ $field_idx{'First Name'}   ] // '',
            last_name    => $fields[ $field_idx{'Last Name'}    ] // '',
            url          => $fields[ $field_idx{'URL'}          ] // '',
            email        => $fields[ $field_idx{'Email Address'}] // '',
            company      => $fields[ $field_idx{'Company'}      ] // '',
            position     => $fields[ $field_idx{'Position'}     ] // '',
            connected_on => $fields[ $field_idx{'Connected On'} ] // '',
        };
    }

    close $fh;
    return \@connections;
}

sub fetch_linkedin_search_html {
    my ($http, $query, $cookie_header) = @_;

    my $url = 'https://www.linkedin.com/search/results/people/?keywords='
        . _url_encode($query);

    my %options;
    if ($cookie_header) {
        $options{headers} = {
            Cookie => $cookie_header,
        };
    }

    my $response = $http->get($url, \%options);
    return '' unless $response->{success};

    return $response->{content};
}

sub first_linkedin_profile_url {
    my ($html) = @_;
    return unless defined $html;

    my $profile_path = qr{(?:[A-Za-z0-9._\-]|%[0-9A-Fa-f]{2})+};

    while ($html =~ m{(?:href=|")((?:https?://(?:www\.)?linkedin\.com)?/in/$profile_path/?)(?![A-Za-z0-9._%\-])}g) {
        my $candidate = $1;
        $candidate = "https://www.linkedin.com$candidate" if $candidate =~ m{^/};
        $candidate =~ s/&amp;/&/g;
        return $candidate if $candidate =~ m{^https?://(?:www\.)?linkedin\.com/in/$profile_path/?$};
    }

    return;
}

sub connection_status_from_search_html {
    my ($html) = @_;
    return 'unknown' if !defined $html || $html eq '';

    return 'connected' if $html =~ />\s*1st\s*</i;
    return '2nd'       if $html =~ />\s*2nd\s*</i;
    return '3rd+'      if $html =~ />\s*3rd\s*</i;
    return 'out_of_network' if $html =~ /out of network/i;
    return 'unknown';
}

sub linkedin_search_url {
    my ($query) = @_;
    $query = '' if !defined $query;
    $query =~ s/^\s+|\s+\z//g;
    return '' if $query eq '';

    my $encoded = _url_encode($query);
    $encoded =~ s/%20/+/g;

    return "https://www.linkedin.com/search/results/all/?keywords=$encoded";
}

sub _cookie_header {
    my ($options) = @_;

    return $options->{linkedin_cookie} if $options->{linkedin_cookie};

    if ($options->{linkedin_cookie_file}) {
        open my $fh, '<', $options->{linkedin_cookie_file}
            or die "Could not open $options->{linkedin_cookie_file}: $!\n";
        local $/ = undef;
        my $cookie = <$fh>;
        close $fh;
        $cookie =~ s/\s+\z// if defined $cookie;
        return $cookie;
    }

    return $ENV{LINKEDIN_COOKIE} || '';
}

sub _url_encode {
    my ($value) = @_;
    $value =~ s/([^A-Za-z0-9\-._~])/sprintf('%%%02X', ord($1))/ge;
    return $value;
}

1;
