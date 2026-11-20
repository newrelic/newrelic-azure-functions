# a2q: Azure Blob Storage forwarder test generator

Writes one fixed-size, sequence-numbered JSON line per interval as a new blob, so the Azure Blob Storage log forwarder (`LogForwarder/`) can be validated with real traffic. Every line is marked `logger: a2q.azure.blob`.

- `function/lib.js`: shared core. Record format, stateless slot `seq` (`floor(now / interval) * interval`), write-once upload (`ifNoneMatch: '*'`, so a blob is never overwritten and the forwarder never re-sends it).
- `function/index.js`: timer-triggered Azure Function (default every 5 minutes). Deploy it to its own Function App, not the forwarder's.
- `generate.js`: command-line version of the same logic.

## Run from a terminal

```bash
cd a2q && npm install
export AZURE_STORAGE_CONNECTION_STRING='<connection string of the watched storage account>'
export CONTAINER_NAME=<container watched by the forwarder>
export RUN_ID=<new id for every run>
node generate.js            # first line now, then one per interval mark, until Ctrl+C
node generate.js --dry-run /tmp/out   # write to a local folder instead of Azure
```

Settings (environment variables): `LINE_INTERVAL_SECONDS` (300), `RECORD_BYTES` (512), `LINES_PER_BLOB` (1; with more than 1, each line also gets `line` and `msg_id`), `MAX_LINES` (0 = run until stopped; counts blobs written).

## Run as an Azure Function

App settings: `A2Q_TARGET_CONNECTION` (connection string of the watched storage account), `CONTAINER_NAME`, `RUN_ID`, and optionally `LINE_INTERVAL_SECONDS`, `RECORD_BYTES`, `LINES_PER_BLOB`, `A2Q_SCHEDULE`. If you change `LINE_INTERVAL_SECONDS` or `A2Q_SCHEDULE`, change the other to match. Install dependencies with `cd function && npm install --omit=dev`, then deploy the `function/` folder.

Never reuse a `RUN_ID` for a different run, and never commit connection strings.

## Checking the data in New Relic

Count by `seq` (or `msg_id` with `LINES_PER_BLOB` above 1). Consecutive slots differ by exactly `LINE_INTERVAL_SECONDS`, so a run is gap-free when `((max(seq) - min(seq)) / LINE_INTERVAL_SECONDS + 1) - uniqueCount(seq)` is 0 (multiply the first term by `LINES_PER_BLOB` and use `uniqueCount(msg_id)` for multi-line blobs).
