use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

use App::CPANToLinkedIn;

my $options = App::CPANToLinkedIn::parse_args();
is $options->{count}, 20, 'default count is 20';

$options = App::CPANToLinkedIn::parse_args('--count', 5);
is $options->{count}, 5, 'count can be overridden';

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

done_testing();
