'use strict';
/**
 * Shared core for the A2Q blob generator. Used by the CLI (../generate.js) and
 * the timer-triggered Azure Function (index.js). Stateless on purpose:
 *
 *  - `seq` is the epoch second of the interval mark (floor(now / interval) * interval),
 *    so it needs no counter and survives restarts and cold starts.
 *  - The blob name is derived from `seq`, and the upload is write-once
 *    (ifNoneMatch: '*'). A second attempt for the same slot is rejected by
 *    Azure, so it cannot overwrite the blob and re-trigger the forwarder.
 *
 * LINES_PER_BLOB (default 1) puts several lines in each blob. Every invocation
 * writes ONE new blob holding that many lines, all stamped with the same slot
 * `seq`. When it is more than 1, each line also carries `line` (0..N-1) and
 * `msg_id` (`<seq>-<line>`), so every line is unique and can be counted.
 */

const LOGGER = 'a2q.azure.blob';
const MESSAGE = 'A2Q Azure Blob Heartbeat';
const MAX_BLOB_BYTES = 1024 * 1024; // forwarder payload limit is about 1000 KiB

function config(env = process.env) {
  const int = (k, d) =>
    env[k] === undefined || env[k] === '' ? d : parseInt(env[k], 10);
  return {
    container: env.CONTAINER_NAME,
    runId: env.RUN_ID,
    lineIntervalSeconds: int('LINE_INTERVAL_SECONDS', 300),
    recordBytes: int('RECORD_BYTES', 512),
    linesPerBlob: int('LINES_PER_BLOB', 1),
  };
}

function validate(cfg) {
  if (!cfg.container) throw new Error('CONTAINER_NAME is required');
  if (!cfg.runId) throw new Error('RUN_ID is required');
  if (!(cfg.lineIntervalSeconds > 0)) {
    throw new Error('LINE_INTERVAL_SECONDS must be greater than 0');
  }
  if (!Number.isInteger(cfg.linesPerBlob) || cfg.linesPerBlob < 1) {
    throw new Error('LINES_PER_BLOB must be a whole number, at least 1');
  }
  if (cfg.linesPerBlob * cfg.recordBytes > MAX_BLOB_BYTES) {
    throw new Error(
      `LINES_PER_BLOB x RECORD_BYTES must be at most ${MAX_BLOB_BYTES} bytes`
    );
  }
}

/** Epoch second of the interval mark that `nowMs` falls in. */
function slotSeq(nowMs, intervalSeconds) {
  return Math.floor(nowMs / (intervalSeconds * 1000)) * intervalSeconds;
}

function blobName(runId, seq) {
  return `a2q/${runId}/${seq}.json`;
}

/**
 * One line, serialized, exactly `recordBytes` long including the trailing \n.
 * `lineIndex` and `count` identify the line inside a multi-line blob.
 */
function buildRecord(cfg, seq, now = new Date(), lineIndex = 0, count = 1) {
  const rec = {
    time: now.toISOString().replace('T', ' ').replace('Z', ''),
    level: 'INFO',
    logger: LOGGER,
    message: MESSAGE,
    seq,
  };
  if (count > 1) {
    rec.line = lineIndex;
    rec.msg_id = `${seq}-${lineIndex}`;
  }
  rec.run_id = cfg.runId;
  rec.blob = blobName(cfg.runId, seq);
  rec.generated_at = now.toISOString();
  rec.pad = '';
  const base = Buffer.byteLength(JSON.stringify(rec)) + 1;
  if (base > cfg.recordBytes) {
    throw new Error(`RECORD_BYTES ${cfg.recordBytes} too small (need ${base})`);
  }
  rec.pad = 'x'.repeat(cfg.recordBytes - base);
  return JSON.stringify(rec) + '\n';
}

/**
 * Writes the current slot's blob: `linesPerBlob` lines, all with the slot `seq`.
 * `containerClient` is an @azure/storage-blob ContainerClient (or a stand-in).
 * Returns { seq, lines, blob, written }. written=false means the slot's blob
 * already existed and was left untouched.
 */
async function emit(cfg, containerClient, now = new Date()) {
  const seq = slotSeq(now.getTime(), cfg.lineIntervalSeconds);
  const blob = blobName(cfg.runId, seq);
  const n = cfg.linesPerBlob;
  const body = Array.from({ length: n }, (_, k) =>
    buildRecord(cfg, seq, now, k, n)
  ).join('');
  const result = { seq, lines: n, blob };
  try {
    await containerClient
      .getBlockBlobClient(blob)
      .upload(body, Buffer.byteLength(body), {
        blobHTTPHeaders: { blobContentType: 'application/json' },
        conditions: { ifNoneMatch: '*' },
      });
  } catch (e) {
    if (e && (e.statusCode === 409 || e.code === 'BlobAlreadyExists')) {
      return { ...result, written: false };
    }
    throw e;
  }
  return { ...result, written: true, bytes: Buffer.byteLength(body) };
}

module.exports = {
  LOGGER,
  MESSAGE,
  config,
  validate,
  slotSeq,
  blobName,
  buildRecord,
  emit,
};
