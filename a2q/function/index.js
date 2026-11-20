'use strict';
/**
 * Timer-triggered A2Q generator: one fixed-size line, written as a new blob, per tick.
 * Deploy it to its OWN Function App (not the forwarder's): a timer in the
 * forwarder's app would keep that host awake and hide cold-start delay.
 *
 * App settings:
 *   A2Q_TARGET_CONNECTION  connection string of the storage account the forwarder watches
 *   CONTAINER_NAME         the forwarder's watched container
 *   RUN_ID                 id for this run; change it to start a new run
 *   LINE_INTERVAL_SECONDS  must match the schedule (default 300)
 *   A2Q_SCHEDULE           NCRONTAB; default is every 5 minutes (see below)
 *   RECORD_BYTES           bytes per line (default 512)
 *   LINES_PER_BLOB         lines in each blob (default 1)
 */
const { app } = require('@azure/functions');
const { BlobServiceClient } = require('@azure/storage-blob');
const { config, validate, emit } = require('./lib');

app.timer('a2qGenerator', {
  schedule: process.env.A2Q_SCHEDULE || '0 */5 * * * *',
  handler: async (timer, context) => {
    const cfg = config();
    validate(cfg);
    const conn = process.env.A2Q_TARGET_CONNECTION;
    if (!conn) throw new Error('A2Q_TARGET_CONNECTION is required');
    const container = BlobServiceClient.fromConnectionString(
      conn
    ).getContainerClient(cfg.container);
    const r = await emit(cfg, container);
    context.log(
      JSON.stringify({
        event: r.written ? 'wrote' : 'exists',
        blob: r.blob,
        seq: r.seq,
        lines: r.lines,
        pastDue: timer.isPastDue,
      })
    );
  },
});
