'use strict';

/**
 * VNet Flow Logs Forwarder — New Relic Delivery
 *
 * Handles batching, compression, and HTTP delivery of log payloads
 * to the New Relic Logs API with retry logic.
 */

const https = require('https');
const url = require('url');
const zlib = require('zlib');
const config = require('./config');

// Reuse TCP connections across requests within the same function invocation
const httpsAgent = new https.Agent({ keepAlive: true });

/**
 * Build the New Relic payload envelope.
 *
 * @param {Array<Object>} logEntries - Array of log entry objects
 * @param {Object} context - Azure Function context
 * @returns {Array<Object>} NR Logs API payload
 */
function buildPayload(logEntries, context) {
  const tags = parseTags(config.nrTags);
  return [
    {
      common: {
        attributes: {
          plugin: {
            type: 'azure',
            version: config.version,
          },
          azure: {
            forwardername: context.functionName || 'VNetFlowConsumer',
            invocationid: context.invocationId || '',
          },
          tags,
        },
      },
      logs: logEntries,
    },
  ];
}

/**
 * Parse semicolon-separated tags string into an object.
 * Format: "key1:value1;key2:value2"
 */
function parseTags(tagsStr) {
  const tagsObj = {};
  if (!tagsStr) return tagsObj;
  const tags = tagsStr.split(';');
  for (const tag of tags) {
    const [key, ...valueParts] = tag.split(':');
    if (key && valueParts.length > 0) {
      tagsObj[key.trim()] = valueParts.join(':').trim();
    }
  }
  return tagsObj;
}

/**
 * Compress data with gzip.
 * @param {string} data - JSON string to compress
 * @returns {Promise<Buffer>} Compressed buffer
 */
function compress(data) {
  return new Promise((resolve, reject) => {
    zlib.gzip(data, (err, result) => {
      if (err) reject(err);
      else resolve(result);
    });
  });
}

/**
 * Send log entries to New Relic with batching, compression, and retry.
 * Recursively splits payloads that exceed the size limit.
 *
 * @param {Array<Object>} logEntries - Log entries to send
 * @param {Object} context - Azure Function context
 * @returns {Promise<void>}
 */
async function sendToNewRelic(logEntries, context) {
  if (!logEntries || logEntries.length === 0) {
    return;
  }

  // Split into message-count batches
  const batches = [];
  for (let i = 0; i < logEntries.length; i += config.maxMessagesPerPayload) {
    batches.push(logEntries.slice(i, i + config.maxMessagesPerPayload));
  }

  for (const batch of batches) {
    await compressAndSend(batch, context);
  }
}

/**
 * Compress a batch and send it. If too large, split recursively.
 */
async function compressAndSend(logEntries, context) {
  const payload = buildPayload(logEntries, context);
  const jsonStr = JSON.stringify(payload);
  const compressed = await compress(jsonStr);

  if (compressed.length > config.maxPayloadSize) {
    if (logEntries.length === 1) {
      context.error(
        `Single log entry exceeds max payload size (${compressed.length} bytes compressed). Skipping.`
      );
      return;
    }
    // Split in half and retry both
    const mid = Math.floor(logEntries.length / 2);
    await compressAndSend(logEntries.slice(0, mid), context);
    await compressAndSend(logEntries.slice(mid), context);
    return;
  }

  await retryWithBackoff(
    () => httpSend(compressed, context),
    config.nrMaxRetries,
    config.nrRetryInterval,
    context
  );
}

/**
 * Send compressed payload via HTTPS to New Relic.
 *
 * @param {Buffer} compressedData
 * @param {Object} context
 * @returns {Promise<void>}
 */
function httpSend(compressedData, context) {
  return new Promise((resolve, reject) => {
    const urlObj = url.parse(config.nrEndpoint);
    const options = {
      hostname: urlObj.hostname,
      port: 443,
      path: urlObj.pathname,
      protocol: urlObj.protocol,
      method: 'POST',
      agent: httpsAgent,
      headers: {
        'Content-Type': 'application/json',
        'Content-Encoding': 'gzip',
        [config.getApiKeyHeader()]: config.getApiKey(),
      },
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        body += chunk;
      });
      res.on('end', () => {
        if (res.statusCode === 202) {
          resolve();
        } else {
          reject(new Error(`NR API returned ${res.statusCode}: ${body}`));
        }
      });
    });

    req.on('error', (err) => {
      reject(err);
    });

    req.write(compressedData);
    req.end();
  });
}

/**
 * Retry a function with fixed interval.
 *
 * @param {Function} fn - Async function to retry
 * @param {number} maxRetries
 * @param {number} interval - Milliseconds between retries
 * @param {Object} context
 * @returns {Promise<void>}
 */
async function retryWithBackoff(fn, maxRetries, interval, context) {
  let lastError;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      await fn();
      return;
    } catch (err) {
      lastError = err;
      if (attempt < maxRetries) {
        context.warn(
          `NR delivery attempt ${attempt + 1} failed: ${
            err.message
          }. Retrying in ${interval}ms...`
        );
        await sleep(interval);
      }
    }
  }
  throw lastError;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

module.exports = {
  sendToNewRelic,
  buildPayload,
  parseTags,
  compress,
  httpSend,
  retryWithBackoff,
};
