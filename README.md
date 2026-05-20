# cpan-to-linkedin

`script/cpan-to-linkedin` fetches the authors of the most recent CPAN releases
from MetaCPAN and tries to find matching LinkedIn profiles.

## Usage

```bash
perl script/cpan-to-linkedin
perl script/cpan-to-linkedin --count 50
perl script/cpan-to-linkedin --count 50 --linkedin-export ~/linkedin-export
perl script/cpan-to-linkedin --count 50 --linkedin-cookie-file ~/.linkedin-cookie
```

### Using the LinkedIn CSV export (recommended)

Export your LinkedIn connections data from
[LinkedIn's data export page](https://www.linkedin.com/mypreferences/d/download-my-data)
and pass the folder containing `Connections.csv` with `--linkedin-export`:

```bash
perl script/cpan-to-linkedin --linkedin-export ~/linkedin-export
```

When `--linkedin-export` is provided the script looks up each CPAN author
directly in your exported connections list instead of searching the LinkedIn
website. Matched authors will have `connection_status` set to `connected` and
their LinkedIn profile URL taken from the CSV.

### Using LinkedIn search (legacy)

Without `--linkedin-export` the script searches the LinkedIn website directly.
Without authentication `connection_status` is reported as `unknown`. To inspect
connection status, pass a raw LinkedIn `Cookie` header with `--linkedin-cookie`,
`--linkedin-cookie-file`, or the `LINKEDIN_COOKIE` environment variable.

To skip specific PAUSE IDs entirely, create an optional `exclude.csv` file in
the current working directory. The first column is interpreted as the PAUSE ID;
other columns are ignored.

## Dependencies

The script uses `MetaCPAN::Client` for MetaCPAN queries and `Text::CSV` for
parsing the LinkedIn export file.

```bash
cpanm --installdeps .
```
