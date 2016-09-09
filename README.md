# ML-region-search
A demo app showing off MarkLogic's new geospatial region search capability.

## Setup

1. Clone the repository to a local directory.
2. Navigate to the local directory and run `setup.sh --host=localhost` to configure the database and app-servers.
3. Load some data. You will need to put your polygons in the `foo:region` tag, where the namespace `foo="http://marklogic.com/foo"`.
3. Navigate to http://localhost:3333/ (substituting your hostname and port number).
4. Draw some shapes, and do some searches.

## Etc.

Feel free to fork or send a pull request!
