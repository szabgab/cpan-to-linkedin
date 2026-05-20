use strict;
use warnings;

use FindBin qw($Bin);
use Test::More;

require "$Bin/../script/cpan-to-linkedin";

my $options = App::CPANToLinkedIn::parse_args();
is $options->{count}, 20, 'default count is 20';

$options = App::CPANToLinkedIn::parse_args('--count', 5);
is $options->{count}, 5, 'count can be overridden';

my $packages = App::CPANToLinkedIn::recent_packages_from_search_response(
    {
        hits => {
            hits => [
                {
                    _source => {
                        distribution => 'Example-One',
                        author       => 'AUTHOR1',
                        date         => '2026-05-20T00:00:00',
                    },
                },
                {
                    _source => {
                        distribution => 'Example-Two',
                        author       => 'AUTHOR2',
                        date         => '2026-05-20T00:01:00',
                    },
                },
            ],
        },
    }
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
    'recent package extraction keeps distribution and author',
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
        q{<a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.linkedin.com%2Fin%2Fwrapped-profile%2F">Wrapped</a>}
    ),
    'https://www.linkedin.com/in/wrapped-profile/',
    'finds LinkedIn URL in wrapped DuckDuckGo result',
);

ok(
    !defined App::CPANToLinkedIn::first_linkedin_profile_url(
        q{<a href="https://www.linkedin.com/in/bad%zzprofile/">Bad</a>}
    ),
    'rejects malformed percent-encoded LinkedIn profile URL',
);

ok(
    !defined App::CPANToLinkedIn::first_linkedin_profile_url(
        q{<a href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.linkedin.com%2Fin%2Fbad%zzprofile%2F">Bad wrapped</a>}
    ),
    'rejects malformed percent-encoded wrapped LinkedIn profile URL',
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
