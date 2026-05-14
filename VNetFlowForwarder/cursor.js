'use strict';

/**
 * VNet Flow Logs Forwarder — Cursor Management
 *
 * Uses Azure Table Storage to persist per-blob block-ID cursors.
 * Each cursor tracks the last processed block ID for a specific
 * PT1H.json blob, enabling delta-only reads with precise tracking.
 */

const { TableClient } = require('@azure/data-tables');
const config = require('./config');

let tableClient = null;

/**
 * Get or create the Table Storage client (lazy singleton).
 */
function getTableClient() {
  if (!tableClient) {
    tableClient = TableClient.fromConnectionString(
      config.cursorStorageConnection,
      config.cursorTableName
    );
  }
  return tableClient;
}

/**
 * Encode a blob path into safe Table Storage keys.
 * Table Storage disallows: / \ # ? and control chars in keys.
 * We use a two-level key: partitionKey groups by date-hour,
 * rowKey identifies the specific blob.
 */
function encodeKeys(blobPath) {
  // Replace disallowed characters with pipe-delimited hex
  const encoded = blobPath
    .replace(/[/\\#?]/g, (ch) => `|${ch.charCodeAt(0).toString(16)}|`);

  // Use a fixed partition to keep queries simple; rowKey is the encoded path
  return {
    partitionKey: 'vnetflow',
    rowKey: encoded,
  };
}

/**
 * Retrieve the cursor (last processed block ID) for a blob.
 * Returns null if no cursor exists (first run for this blob).
 *
 * @param {string} blobPath - Full blob path (container/path/to/PT1H.json)
 * @returns {Promise<{lastBlockId: string|null, failureCount: number}>}
 */
async function getCursor(blobPath) {
  const { partitionKey, rowKey } = encodeKeys(blobPath);
  const client = getTableClient();

  try {
    const entity = await client.getEntity(partitionKey, rowKey);
    return {
      lastBlockId: entity.lastBlockId || null,
      failureCount: entity.failureCount || 0,
    };
  } catch (err) {
    if (err.statusCode === 404) {
      // First time processing this blob
      return { lastBlockId: null, failureCount: 0 };
    }
    throw err;
  }
}

/**
 * Update (upsert) the cursor for a blob after successful processing.
 * Resets the failure count on success.
 *
 * @param {string} blobPath - Full blob path
 * @param {string} lastBlockId - The ID of the last processed block
 * @returns {Promise<void>}
 */
async function setCursor(blobPath, lastBlockId) {
  const { partitionKey, rowKey } = encodeKeys(blobPath);
  const client = getTableClient();

  await client.upsertEntity(
    {
      partitionKey,
      rowKey,
      lastBlockId,
      failureCount: 0,
      updatedAt: new Date().toISOString(),
    },
    'Replace'
  );
}

/**
 * Increment the failure counter for a blob after a processing error.
 *
 * @param {string} blobPath - Full blob path
 * @param {string|null} lastBlockId - Current last block ID (preserved)
 * @param {number} currentFailureCount - Current failure count
 * @returns {Promise<void>}
 */
async function incrementFailure(blobPath, lastBlockId, currentFailureCount) {
  const { partitionKey, rowKey } = encodeKeys(blobPath);
  const client = getTableClient();

  await client.upsertEntity(
    {
      partitionKey,
      rowKey,
      lastBlockId: lastBlockId || '',
      failureCount: currentFailureCount + 1,
      updatedAt: new Date().toISOString(),
    },
    'Replace'
  );
}

/**
 * Reset the table client (for testing).
 */
function resetClient() {
  tableClient = null;
}

module.exports = {
  getCursor,
  setCursor,
  incrementFailure,
  encodeKeys,
  resetClient,
  // Exposed for testing
  _getTableClient: getTableClient,
};
