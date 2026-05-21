'use strict';

/**
 * VNet Flow Logs Forwarder — Event Hub Consumer Function
 *
 * Triggered by Event Hub messages (originally relayed from Event Grid).
 * For each message (representing a BlobCreated event):
 *   1. Reads the cursor from Table Storage
 *   2. Downloads only new blocks from the blob (delta)
 *   3. Parses VNet flow log records
 *   4. Sends to New Relic
 *   5. Commits the new cursor on success
 */

const config = require('./config');
const cursor = require('./cursor');
const delta = require('./delta');
const parser = require('./parser');
const delivery = require('./delivery');

/**
 * Consumer handler: processes a batch of Event Hub messages.
 * Each message contains a blob path that needs delta processing.
 *
 * @param {Array<Object>} messages - Array of Event Hub message bodies
 * @param {Object} context - Azure Function context
 */
async function consumerHandler(messages, context) {
  const msgArray = Array.isArray(messages) ? messages : [messages];
  let totalRecords = 0;
  let totalBytes = 0;
  let processedEvents = 0;
  let skippedEvents = 0;
  let erroredEvents = 0;

  for (const message of msgArray) {
    try {
      const result = await processEvent(message, context);
      if (result) {
        totalRecords += result.records;
        totalBytes += result.bytes;
        processedEvents++;
      } else {
        skippedEvents++;
      }
    } catch (err) {
      erroredEvents++;
      const blobPath = message?.subject || message?.data?.url || 'unknown';
      context.error(
        `Error processing event for blob "${blobPath}": ${err.message}`
      );
      // Increment failure counter for poison event protection
      try {
        const { lastBlockId, failureCount } = await cursor.getCursor(blobPath);
        await cursor.incrementFailure(blobPath, lastBlockId, failureCount);
      } catch (cursorErr) {
        context.warn(
          `Failed to increment failure counter: ${cursorErr.message}`
        );
      }
    }
  }

  context.log(
    `VNetFlowLogs batch complete: ${processedEvents} processed, ${skippedEvents} skipped, ${erroredEvents} errors. ` +
      `Total records: ${totalRecords}, bytes downloaded: ${totalBytes}`
  );
}

/**
 * Process a single blob event: cursor -> delta -> parse -> send -> commit.
 *
 * @param {Object} message - Event Hub message body (contains subject/blobPath)
 * @param {Object} context - Azure Function context
 * @returns {Promise<{records: number, bytes: number} | null>} Processing stats or null if skipped
 */
async function processEvent(message, context) {
  // Event Grid sends events as an array — unwrap if needed
  const event = Array.isArray(message) ? message[0] : message;
  if (!event) {
    context.warn('Consumer: empty message. Skipping.');
    return null;
  }

  const blobPath = event.subject || event.data?.url || '';
  if (!blobPath) {
    context.warn('Consumer: message has no blob path. Skipping.');
    return null;
  }

  if (config.debugEnabled) {
    context.log(`Consumer: processing ${blobPath}`);
  }

  // Step 1: Parse the blob path
  const { containerName, blobName } = delta.parseBlobPath(blobPath);

  // Step 2: Read cursor and check for poison event
  const { lastBlockId, failureCount } = await cursor.getCursor(blobPath);
  if (failureCount >= 3) {
    context.error(
      `Consumer: blob "${blobPath}" has failed ${failureCount} consecutive times. Skipping (poison event).`
    );
    return null;
  }
  if (config.debugEnabled) {
    context.log(`Consumer: cursor for ${blobPath} = ${lastBlockId}`);
  }

  // Step 3: Download delta
  let deltaResult;
  try {
    deltaResult = await delta.downloadDelta(
      containerName,
      blobName,
      lastBlockId
    );
  } catch (err) {
    if (err.statusCode === 404) {
      context.warn(`Consumer: blob not found (deleted?): ${blobPath}`);
      return null;
    }
    throw err;
  }

  if (!deltaResult) {
    if (config.debugEnabled) {
      context.log(`Consumer: no new blocks for ${blobPath}. Skipping.`);
    }
    return null;
  }

  const { data, lastBlockId: newLastBlockId } = deltaResult;

  // Step 4: Parse the delta into flow log records
  const records = parser.parseRawDelta(data);
  if (records.length === 0) {
    context.warn(`Consumer: parsed 0 records from delta of ${blobPath}`);
    // Still advance cursor to avoid re-processing empty deltas
    await cursor.setCursor(blobPath, newLastBlockId);
    return { records: 0, bytes: data.length };
  }

  // Step 5: Transform records into NR log entries
  const pathMetadata = parser.extractMetadataFromPath(blobName);
  const logEntries = parser.transformRecords(records, pathMetadata);

  if (config.debugEnabled) {
    context.log(
      `Consumer: ${records.length} records -> ${logEntries.length} log entries from ${blobPath}`
    );
  }

  // Step 6: Send to New Relic
  await delivery.sendToNewRelic(logEntries, context);

  // Step 7: Commit cursor (only after successful delivery)
  await cursor.setCursor(blobPath, newLastBlockId);

  if (config.debugEnabled) {
    context.log(
      `Consumer: cursor advanced to block ${newLastBlockId} for ${blobPath}`
    );
  }

  return { records: logEntries.length, bytes: data.length };
}

module.exports = {
  consumerHandler,
  processEvent,
};
