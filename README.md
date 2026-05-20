# cpan-to-linkedin

`script/cpan-to-linkedin` fetches the authors of the most recent CPAN releases
from MetaCPAN and tries to find matching LinkedIn profiles.

## Usage

```bash
perl script/cpan-to-linkedin
perl script/cpan-to-linkedin --count 50
perl script/cpan-to-linkedin --count 50 --linkedin-cookie-file ~/.linkedin-cookie
```

Without LinkedIn authentication the script can still try a direct LinkedIn
search, but `connection_status` is reported as `unknown`. To inspect
connection status, pass a raw LinkedIn `Cookie` header either with
`--linkedin-cookie`, `--linkedin-cookie-file`, or the `LINKEDIN_COOKIE`
environment variable.

## Dependencies

The script uses `MetaCPAN::Client` for the MetaCPAN queries.

```bash
cpanm --installdeps .
```
