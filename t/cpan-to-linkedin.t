use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

use App::CPANToLinkedIn;

my $options = App::CPANToLinkedIn::parse_args('--linkedin-search');
is $options->{count}, 20, 'default count is 20';
is $options->{user_agent}, "cpan-to-linkedin/$App::CPANToLinkedIn::VERSION",
    'default user agent version matches module version';

$options = App::CPANToLinkedIn::parse_args('--linkedin-search', '--count', 5);
is $options->{count}, 5, 'count can be overridden';

$options = App::CPANToLinkedIn::parse_args('--linkedin-export', '/tmp/export');
is $options->{linkedin_export}, '/tmp/export', 'linkedin-export option is accepted';

# Neither mode selected → must die
eval { App::CPANToLinkedIn::parse_args() };
like $@, qr/Must specify exactly one workmode/, 'dies when no workmode is selected';

eval { App::CPANToLinkedIn::parse_args('--count', 5) };
like $@, qr/Must specify exactly one workmode/, 'dies when no workmode is selected with --count';

# Both modes selected → must die
eval { App::CPANToLinkedIn::parse_args('--linkedin-export', '/tmp/export', '--linkedin-search') };
like $@, qr/Cannot use --linkedin-export together with/, 'dies when both --linkedin-export and --linkedin-search are given';

eval { App::CPANToLinkedIn::parse_args('--linkedin-export', '/tmp/export', '--linkedin-cookie', 'tok') };
like $@, qr/Cannot use --linkedin-export together with/, 'dies when both --linkedin-export and --linkedin-cookie are given';

eval { App::CPANToLinkedIn::parse_args('--linkedin-export', '/tmp/export', '--linkedin-cookie-file', '/tmp/c') };
like $@, qr/Cannot use --linkedin-export together with/, 'dies when both --linkedin-export and --linkedin-cookie-file are given';

# Cookie without --linkedin-search → must die
eval { App::CPANToLinkedIn::parse_args('--linkedin-cookie', 'tok') };
like $@, qr/require --linkedin-search/, 'dies when --linkedin-cookie is given without --linkedin-search';

eval { App::CPANToLinkedIn::parse_args('--linkedin-cookie-file', '/tmp/c') };
like $@, qr/require --linkedin-search/, 'dies when --linkedin-cookie-file is given without --linkedin-search';

{
    package Local::Release;

    sub new { bless $_[1], $_[0] }
    sub distribution { $_[0]->{distribution} }
    sub author       { $_[0]->{author} }
    sub date         { $_[0]->{date} }
}

{
    package Local::ResultSet;

    sub new {
        my ($class, @items) = @_;
        return bless { items => \@items }, $class;
    }

    sub next {
        my ($self) = @_;
        return shift @{ $self->{items} };
    }
}

my $packages = App::CPANToLinkedIn::releases_from_resultset(
    Local::ResultSet->new(
        Local::Release->new(
            {
                distribution => 'Example-One',
                author       => 'AUTHOR1',
                date         => '2026-05-20T00:00:00',
            }
        ),
        Local::Release->new(
            {
                distribution => 'Example-Two',
                author       => 'AUTHOR2',
                date         => '2026-05-20T00:01:00',
            }
        ),
    )
);

is_deeply(
    $packages,
    [
        {
            distribution => 'Example-One',
            author       => 'AUTHOR1',
            date         => '2026-05-20T00:00:00',
        },
        {
            distribution => 'Example-Two',
            author       => 'AUTHOR2',
            date         => '2026-05-20T00:01:00',
        },
    ],
    'recent package extraction from MetaCPAN resultset keeps distribution and author',
);

is(
    App::CPANToLinkedIn::first_linkedin_profile_url(
        q{<a href="https://www.linkedin.com/in/example-person/">Example</a>}
    ),
    'https://www.linkedin.com/in/example-person/',
    'finds first LinkedIn profile URL',
);

is(
    App::CPANToLinkedIn::first_linkedin_profile_url(
        q{<a href="/in/wrapped-profile/">Wrapped</a>}
    ),
    'https://www.linkedin.com/in/wrapped-profile/',
    'finds LinkedIn URL in direct LinkedIn search result',
);

ok(
    !defined App::CPANToLinkedIn::first_linkedin_profile_url(
        q{<a href="https://www.linkedin.com/in/bad%zzprofile/">Bad</a>}
    ),
    'rejects malformed percent-encoded LinkedIn profile URL',
);

ok(
    !defined App::CPANToLinkedIn::first_linkedin_profile_url(
        q{<a href="/in/bad%zzprofile/">Bad relative</a>}
    ),
    'rejects malformed percent-encoded relative LinkedIn profile URL',
);

is(
    App::CPANToLinkedIn::connection_status_from_search_html(
        q{<span>1st</span>}
    ),
    'connected',
    'detects first-degree connection',
);

is(
    App::CPANToLinkedIn::connection_status_from_search_html(
        q{<span>2nd</span>}
    ),
    '2nd',
    'detects second-degree connection',
);

is(
    App::CPANToLinkedIn::connection_status_from_search_html(
        q{<span>Out of network</span>}
    ),
    'out_of_network',
    'detects out-of-network search result',
);

is(
    App::CPANToLinkedIn::linkedin_search_url('Foo Bar'),
    'https://www.linkedin.com/search/results/all/?keywords=Foo+Bar',
    'builds LinkedIn search URL for not-found names',
);

my $connections = App::CPANToLinkedIn::load_linkedin_connections("$Bin/../linkedin-export");
is ref($connections), 'ARRAY', 'load_linkedin_connections returns an array ref';
is scalar @$connections, 1, 'loads one connection from test CSV';
is $connections->[0]{first_name},   'Foo',                                      'parses first name';
is $connections->[0]{last_name},    'Bar',                                      'parses last name';
is $connections->[0]{url},          'https://www.linkedin.com/in/foobar',       'parses URL';
is $connections->[0]{connected_on}, '28 Mar 2026',                              'parses connected_on date';

done_testing();
