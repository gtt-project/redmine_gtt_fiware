# Redmine GTT FIWARE Plugin

The Geo-Task-Tracker (GTT) FIWARE plugin adds support for [FIWARE](https://www.fiware.org/)
open standards:

- TBD

## Requirements

Redmine GTT FIWARE **requires PostgreSQL/PostGIS** and will not work with SQLite
or MariaDB/MySQL!!!

- Redmine >= 5.0.0
- [redmine_gtt](https://github.com/gtt-project/redmine_gtt/) plugin

## Installation

To install Redmine GTT FIWARE plugin, download or clone this repository in your
Redmine installation plugins directory!

```sh
cd path/to/plugin/directory
git clone https://github.com/gtt-project/redmine_gtt_fiware.git
```

Then run

```sh
bundle install
bundle exec rake redmine:plugins:migrate
```

After restarting Redmine, you should be able to see the Redmine GTT FIWARE
plugin in the Plugins page.

More information on installing (and uninstalling) Redmine plugins can be found
[here](http://www.redmine.org/wiki/redmine/Plugins).

## How to use

- Make sure REST web services is enabled: http://localhost:3000/settings?tab=api
- Enable the plugin in project settings

TBD

### "Context" API endpoint

```txt
http://localhost:3000/fiware/ngsi/ld/context.jsonld
```

### "Data Model" API endpoint

```txt
http://localhost:3000/fiware/data-models/[tracker_id]/context.jsonld
```

### NGSI-LD "Issue" API endpoint

```txt
http://localhost:3000/issues/[issue_id].jsonld
```

## Contributing and Support

The GTT Project appreciates any [contributions](https://github.com/gtt-project/.github/blob/main/CONTRIBUTING.md)!
Feel free to contact us for [reporting problems and support](https://github.com/gtt-project/.github/blob/main/CONTRIBUTING.md).

## Version History

See [all releases](https://github.com/gtt-project/redmine_gtt_fiware/releases)
with release notes.

## Authors

- [Daniel Kastl](https://github.com/dkastl)
- ... [and others](https://github.com/gtt-project/redmine_gtt_fiware/graphs/contributors)

## LICENSE

This program is free software. See [LICENSE](LICENSE) for more information.
