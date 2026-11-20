#!/usr/bin/env node
/**
 * CLI generator for A2Q coverage of the Blob Storage forwarder.
 * Same core as the Azure Function (function/lib.js): one fixed-size line per
 * interval mark, written as a NEW blob, write-once (never overwritten).
 *
 * Env:
 *   AZURE_STORAGE_CONNECTION_STRING  target storage account (omit with --dry-run)
 *   CONTAINER_NAME         container watched by the forwarder      (required)
 *   RUN_ID                 id for this run (default: timestamp)
 *   LINE_INTERVAL_SECONDS  seconds between lines, > 0               (default: 300)
 *   RECORD_BYTES           serialized bytes per line, incl. \n      (default: 512)
 *   MAX_LINES              stop after N blobs, 0 = run forever      (default: 0)
 *   LINES_PER_BLOB         lines in each blob                       (default: 1)
 *
 * The first line is written immediately, in the current interval slot; later
 * lines are written on the interval marks (UTC clock). Two writes to the same
 * slot of the same RUN_ID are safe: the second is rejected and reported as
 * "exists".
 *
 * Usage: node generate.js [--dry-run <dir>]
 */
const fs = require('fs');
const path = require('path');
const { config, validate, emit } = require('./function/lib');

/** Stand-in for a ContainerClient that writes to a local folder (honours write-once). */
function localContainer(dir) {
  return {
    getBlockBlobClient: (name) => ({
      upload: async (body) => {
        const f = path.join(dir, name);
        if (fs.existsSync(f)) {
          const e = new Error('BlobAlreadyExists');
          e.statusCode = 409;
          throw e;
        }
        fs.mkdirSync(path.dirname(f), { recursive: true });
        fs.writeFileSync(f, body);
      },
    }),
  };
}

function azureContainer(name) {
  const { BlobServiceClient } = require('@azure/storage-blob');
  const conn = process.env.AZURE_STORAGE_CONNECTION_STRING;
  if (!conn) throw new Error('AZURE_STORAGE_CONNECTION_STRING is required');
  if (!/AccountName=[^;]+;/.test(conn) || !/AccountKey=[^;]+/.test(conn)) {
    throw new Error(
      'AZURE_STORAGE_CONNECTION_STRING is not a valid connection string ' +
        '(expected DefaultEndpointsProtocol=...;AccountName=...;AccountKey=...;EndpointSuffix=...). ' +
        'Copy the full value from the storage account > Access keys.'
    );
  }
  return BlobServiceClient.fromConnectionString(conn).getContainerClient(name);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const cfg = config();
  cfg.runId = cfg.runId || new Date().toISOString().replace(/[-:.TZ]/g, '');
  const maxLines = parseInt(process.env.MAX_LINES || '0', 10);
  validate(cfg);

  const i = process.argv.indexOf('--dry-run');
  const container =
    i > -1
      ? localContainer(process.argv[i + 1])
      : azureContainer(cfg.container);
  console.log(JSON.stringify({ event: 'start', ...cfg, maxLines }));

  let stopping = false;
  const stop = () => {
    stopping = true;
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);

  const stepMs = cfg.lineIntervalSeconds * 1000;
  for (let n = 0; !stopping && (maxLines === 0 || n < maxLines); n++) {
    if (n > 0) {
      // Wait for the next interval mark, in short steps so Ctrl+C is prompt.
      const next = (Math.floor(Date.now() / stepMs) + 1) * stepMs;
      while (!stopping && Date.now() < next) {
        await sleep(Math.min(next - Date.now(), 1000));
      }
      if (stopping) break;
    }
    const r = await emit(cfg, container);
    console.log(
      JSON.stringify({
        event: r.written ? 'wrote' : 'exists',
        blob: r.blob,
        seq: r.seq,
        lines: r.lines,
        bytes: r.bytes,
      })
    );
  }
  console.log(JSON.stringify({ event: 'done' }));
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
