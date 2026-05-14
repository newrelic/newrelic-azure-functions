'use strict';

/**
 * VNet Flow Logs Forwarder — Delta Extraction
 *
 * Downloads only the newly appended blocks from a PT1H.json blob.
 * Uses block list inspection to determine what's new since the last cursor.
 */

const { BlobServiceClient } = require('@azure/storage-blob');
const config = require('./config');

let blobServiceClient = null;

/**
 * Get or create the Blob Service client (lazy singleton).
 */
function getBlobServiceClient() {
  if (!blobServiceClient) {
    blobServiceClient = BlobServiceClient.fromConnectionString(
      config.sourceStorageConnection
    );
  }
  return blobServiceClient;
}

/**
 * Given a blob path, split into container and blob name.
 * Example: "insights-logs-flowlogflowevent/resourceId=.../PT1H.json"
 *   -> container: "insights-logs-flowlogflowevent"
 *   -> blobName: "resourceId=.../PT1H.json"
 *
 * @param {string} blobPath - Full path from Event Grid subject
 * @returns {{containerName: string, blobName: string}}
 */
function parseBlobPath(blobPath) {
  // Event Grid subject format:
  // /blobServices/default/containers/{container}/blobs/{blobName}
  const blobServicesPrefix = '/blobServices/default/containers/';
  if (blobPath.startsWith(blobServicesPrefix)) {
    const rest = blobPath.slice(blobServicesPrefix.length);
    const blobsIdx = rest.indexOf('/blobs/');
    if (blobsIdx !== -1) {
      return {
        containerName: rest.slice(0, blobsIdx),
        blobName: rest.slice(blobsIdx + '/blobs/'.length),
      };
    }
  }

  // Fallback: first segment is container, rest is blob name
  const firstSlash = blobPath.indexOf('/');
  if (firstSlash === -1) {
    throw new Error(`Invalid blob path: ${blobPath}`);
  }
  return {
    containerName: blobPath.slice(0, firstSlash),
    blobName: blobPath.slice(firstSlash + 1),
  };
}

/**
 * Get the committed block list for a blob.
 *
 * @param {string} containerName
 * @param {string} blobName
 * @returns {Promise<{size: number, blocks: Array<{name: string, size: number}>}>}
 */
async function getBlockList(containerName, blobName) {
  const client = getBlobServiceClient();
  const blockBlobClient = client
    .getContainerClient(containerName)
    .getBlockBlobClient(blobName);

  const blockList = await blockBlobClient.getBlockList('committed');
  const blocks = (blockList.committedBlocks || []).map((b) => ({
    name: b.name,
    size: b.size,
  }));

  return { blocks };
}

/**
 * Download the delta bytes from a blob given the last processed block ID.
 *
 * @param {string} containerName
 * @param {string} blobName
 * @param {string|null} lastBlockId - ID of the last processed block, or null for first run
 * @returns {Promise<{data: string, lastBlockId: string} | null>}
 *   Returns null if there are no new blocks.
 */
async function downloadDelta(containerName, blobName, lastBlockId) {
  const { blocks } = await getBlockList(containerName, blobName);

  if (blocks.length === 0) {
    return null;
  }

  // Determine the starting index for new blocks
  let startIndex = 0;
  if (lastBlockId !== null) {
    const cursorIndex = blocks.findIndex((b) => b.name === lastBlockId);
    if (cursorIndex === -1) {
      // Last block ID not found — blob was likely recreated; reprocess from start
      startIndex = 0;
    } else if (cursorIndex === blocks.length - 1) {
      // Already processed up to the last block — no new data
      return null;
    } else {
      startIndex = cursorIndex + 1;
    }
  }

  // Calculate byte offset: sum of sizes of already-processed blocks
  let offset = 0;
  for (let i = 0; i < startIndex; i++) {
    offset += blocks[i].size;
  }

  // Calculate size of new blocks
  let newSize = 0;
  for (let i = startIndex; i < blocks.length; i++) {
    newSize += blocks[i].size;
  }

  const client = getBlobServiceClient();
  const blobClient = client
    .getContainerClient(containerName)
    .getBlobClient(blobName);

  const downloadResponse = await blobClient.download(offset, newSize);
  const data = await streamToString(downloadResponse.readableStreamBody);

  return {
    data,
    lastBlockId: blocks[blocks.length - 1].name,
  };
}

/**
 * Convert a readable stream to a string.
 */
async function streamToString(readableStream) {
  const chunks = [];
  for await (const chunk of readableStream) {
    chunks.push(typeof chunk === 'string' ? Buffer.from(chunk) : chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

/**
 * Reset the blob service client (for testing).
 */
function resetClient() {
  blobServiceClient = null;
}

module.exports = {
  parseBlobPath,
  getBlockList,
  downloadDelta,
  resetClient,
};
