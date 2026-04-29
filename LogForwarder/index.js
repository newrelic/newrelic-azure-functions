/**
 * Azure function to read from Blob Storage and forward logs to New Relic.
 */

'use strict';

var https = require('https');
var url = require('url');
var zlib = require('zlib');
const { app } = require('@azure/functions');

const VERSION = '0.0.0-development';

// Global constants
const NR_LICENSE_KEY = process.env.NR_LICENSE_KEY;
const NR_INSERT_KEY = process.env.NR_INSERT_KEY;
const NR_ENDPOINT =
  process.env.NR_ENDPOINT || 'https://log-api.newrelic.com/log/v1';
const NR_TAGS = process.env.NR_TAGS; // Semicolon-seperated tags
const NR_LOGS_SOURCE = 'azure';
const NR_MAX_PAYLOAD_SIZE = 1000 * 1024;
const NR_MAX_RETRIES = process.env.NR_MAX_RETRIES || 3;
const NR_RETRY_INTERVAL = process.env.NR_RETRY_INTERVAL || 2000; // default: 2 seconds

// Deployment context for easy identification in logs
const DEPLOYMENT_CONTEXT_ENABLED = process.env.DEPLOYMENT_CONTEXT_ENABLED === 'true';
const DEPLOYMENT_NAME = process.env.DEPLOYMENT_NAME || 'unknown';
const DEPLOYMENT_VNET_NAME = process.env.DEPLOYMENT_VNET_NAME || 'unknown';
const DEPLOYMENT_LOCATION = process.env.DEPLOYMENT_LOCATION || 'unknown';
const DEPLOYMENT_TYPE = process.env.DEPLOYMENT_TYPE || 'unknown';
const DEPLOYMENT_METHOD = process.env.DEPLOYMENT_METHOD || 'unknown';

function getDeploymentContext() {
  if (!DEPLOYMENT_CONTEXT_ENABLED) {
    return null;
  }
  return {
    deploymentName: DEPLOYMENT_NAME,
    vnetName: DEPLOYMENT_VNET_NAME,
    location: DEPLOYMENT_LOCATION,
    deploymentType: DEPLOYMENT_TYPE,
    deploymentMethod: DEPLOYMENT_METHOD
  };
}

if (process.env.EVENTHUB_FORWARDER_ENABLED === 'true') {
  app.eventHub('EventHubForwarder', {
    eventHubName: process.env.EVENTHUB_NAME,
    connection: 'EVENTHUB_CONSUMER_CONNECTION',
    cardinality: 'many',
    consumerGroup: process.env.EVENTHUB_CONSUMER_GROUP,
    handler: async (messages, context) => {
      await main(messages, context);
    },
  });
}

if (process.env.BLOB_FORWARDER_ENABLED === 'true') {
  app.storageBlob('BlobForwarder', {
    path: process.env.CONTAINER_NAME + '/{name}',
    connection: 'TargetAccountConnection',
    handler: async (blob, context) => {
      await main(blob, context);
    },
  });
}

if (process.env.VNETFLOWLOGS_FORWARDER_ENABLED === 'true') {
  app.eventHub('VNetFlowLogsForwarder', {
    eventHubName: process.env.EVENTHUB_NAME,
    connection: 'EVENTHUB_CONSUMER_CONNECTION',
    cardinality: 'many',
    consumerGroup: process.env.EVENTHUB_CONSUMER_GROUP,
    handler: async (messages, context) => {
      await vnetFlowLogsHandler(messages, context);
    },
  });
}

async function vnetFlowLogsHandler(messages, context) {
  const deploymentCtx = getDeploymentContext();

  context.log('==== VNetFlowLogsForwarder Triggered ====');
  if (deploymentCtx) {
    context.log(`📍 Deployment: ${deploymentCtx.deploymentName}`);
    context.log(`🌐 VNet: ${deploymentCtx.vnetName}`);
    context.log(`📍 Location: ${deploymentCtx.location}`);
    context.log(`🔧 Method: ${deploymentCtx.deploymentMethod}`);
  }
  context.log(`Received ${messages.length} Event Grid event(s)`);

  const validationLogs = [];

  for (let i = 0; i < messages.length; i++) {
    const message = messages[i];
    context.log(`\n--- Processing Message ${i + 1}/${messages.length} ---`);

    try {
      // Parse Event Grid event - message can be string or object
      let eventData =
        typeof message === 'string' ? JSON.parse(message) : message;

      // Event Grid events come as an array
      const events = Array.isArray(eventData) ? eventData : [eventData];

      context.log(`Found ${events.length} Event Grid event(s) in message`);

      // Process each Event Grid event
      for (let j = 0; j < events.length; j++) {
        const event = events[j];

        context.log(`\n  -- Event ${j + 1}/${events.length} --`);
        context.log('  Event Type:', event.eventType);
        context.log('  Event Subject:', event.subject);
        context.log('  Event Time:', event.eventTime);

        // Extract blob information from Event Grid event
        if (event.eventType === 'Microsoft.Storage.BlobCreated') {
          const blobUrl = event.data?.url || event.subject;
          const blobSize = event.data?.contentLength || 0;
          const blobType = event.data?.contentType || 'unknown';

          context.log(`  Blob URL: ${blobUrl}`);
          context.log(`  Blob Size: ${blobSize} bytes`);

          // Check if it's a PT1H.json file (VNet Flow Log)
          if (blobUrl && blobUrl.includes('PT1H.json')) {
            context.log(
              '  ✓ VALIDATED: This is a VNet Flow Log file (PT1H.json)'
            );
            context.log('  ✓ Event Grid → Event Hub flow is working!');

            // Create validation log for New Relic
            const validationLog = {
              message: 'VNet Flow Logs E2E Validation - Event Received',
              logtype: 'azure.vnet.flowlog.validation',
              validation: {
                status: 'success',
                step: 'event-grid-to-eventhub',
                description:
                  'Event Grid successfully forwarded blob creation event to Event Hub',
              },
              event: {
                eventType: event.eventType,
                eventTime: event.eventTime,
                subject: event.subject,
              },
              blob: {
                url: blobUrl,
                size: blobSize,
                contentType: blobType,
                isPT1HFile: true,
                isFlowLogContainer: blobUrl.includes(
                  'insights-logs-flowlogflowevent'
                ),
              },
              deployment: deploymentCtx,
              timestamp: new Date().toISOString(),
            };

            validationLogs.push(validationLog);
            context.log('  ✓ Validation log prepared for New Relic');
          } else {
            context.log('  ⚠ Not a PT1H.json file, skipping');
          }
        } else {
          context.log('  ⚠ Event type:', event.eventType || 'unknown');
        }
      }
    } catch (error) {
      context.error('Error processing message:', error.message);
    }
  }

  // Send validation logs to New Relic
  if (validationLogs.length > 0) {
    context.log(
      `\n==== Sending ${validationLogs.length} validation log(s) to New Relic ====`
    );

    // Use the existing compressAndSend function
    const logLines = validationLogs.map((log) => {
      log.timestamp = log.timestamp || Date.now();
      return log;
    });

    await compressAndSend(logLines, context);
  }

  context.log('==== VNetFlowLogsForwarder Completed ====\n');
}

async function main(logMessages, context) {
  if (!NR_LICENSE_KEY && !NR_INSERT_KEY) {
    context.error(
      'You have to configure either your LICENSE key or insights insert key. ' +
        'Please follow the instructions in README'
    );
    return;
  }
  let logs;
  if (typeof logMessages === 'string') {
    logs = logMessages.trim().split('\n');
  } else if (Buffer.isBuffer(logMessages)) {
    logs = logMessages.toString('utf8').trim().split('\n');
  } else if (!Array.isArray(logMessages)) {
    logs = JSON.stringify(logMessages).trim().split('\n');
  } else {
    logs = logMessages;
  }
  let buffer = transformData(logs, context);
  if (buffer.length === 0) {
    context.warn('logs format is invalid');
    return;
  }
  let logLines = appendMetaDataToAllLogLines(buffer);
  logLines = appendTimestampToAllLogLines(logLines);
  await compressAndSend(logLines, context);
}

module.exports = main;

/**
 * Compress and send logs with Promise
 * @param {Object[]} data - array of JSON object containing log message and meta data
 * @param {Object} context - context object passed while invoking this function
 * @returns {Promise} A promise that resolves when logs are successfully sent.
 */

function compressAndSend(data, context) {
  return compressData(JSON.stringify(getPayload(data, context)))
    .then((compressedPayload) => {
      if (compressedPayload.length > NR_MAX_PAYLOAD_SIZE) {
        if (data.length === 1) {
          context.error(
            'Cannot send the payload as the size of single line exceeds the limit'
          );
          return;
        }

        let halfwayThrough = Math.floor(data.length / 2);

        let arrayFirstHalf = data.slice(0, halfwayThrough);
        let arraySecondHalf = data.slice(halfwayThrough, data.length);

        return Promise.all([
          compressAndSend(arrayFirstHalf, context),
          compressAndSend(arraySecondHalf, context),
        ]);
      } else {
        return retryMax(httpSend, NR_MAX_RETRIES, NR_RETRY_INTERVAL, [
          compressedPayload,
          context,
        ])
          .then(() =>
            context.log('Logs payload successfully sent to New Relic.')
          )
          .catch((e) => {
            context.error(
              'Max retries reached: failed to send logs payload to New Relic'
            );
            context.error('Exception: ', JSON.stringify(e));
          });
      }
    })
    .catch((e) => {
      context.error('Error during payload compression.');
      context.error('Exception: ', JSON.stringify(e));
    });
}

function compressData(data) {
  return new Promise((resolve, reject) => {
    zlib.gzip(data, (e, compressedData) => {
      if (!e) {
        resolve(compressedData);
      } else {
        reject({ error: e, res: null });
      }
    });
  });
}

function appendMetaDataToAllLogLines(logs) {
  return logs.map((log) => addMetadata(log));
}

function appendTimestampToAllLogLines(logs) {
  return logs.map((log) => addTimestamp(log));
}

function getPayload(logs, context) {
  return [
    {
      common: getCommonAttributes(context),
      logs: logs,
    },
  ];
}

function getCommonAttributes(context) {
  const deploymentCtx = getDeploymentContext();

  const attributes = {
    plugin: {
      type: NR_LOGS_SOURCE,
      version: VERSION,
    },
    azure: {
      forwardername: context.functionName,
      invocationid: context.invocationId,
    },
    tags: getTags(),
  };

  // Add deployment context to all logs
  if (deploymentCtx) {
    attributes.deployment = deploymentCtx;
  }

  return { attributes };
}

function getTags() {
  const tagsObj = {};
  if (NR_TAGS) {
    const tags = NR_TAGS.split(';');
    tags.forEach((tag) => {
      const keyValue = tag.split(':');
      if (keyValue.length > 1) {
        tagsObj[keyValue[0]] = keyValue[1];
      }
    });
  }
  return tagsObj;
}

function addMetadata(logEntry) {
  if (
    logEntry.resourceId !== undefined &&
    typeof logEntry.resourceId === 'string' &&
    logEntry.resourceId.toLowerCase().startsWith('/subscriptions/')
  ) {
    let resourceId = logEntry.resourceId.toLowerCase().split('/');
    if (resourceId.length > 2) {
      logEntry.metadata = {};
      logEntry.metadata.subscriptionId = resourceId[2];
    }
    if (resourceId.length > 4) {
      logEntry.metadata.resourceGroup = resourceId[4];
    }
    if (resourceId.length > 6 && resourceId[6]) {
      logEntry.metadata.source = resourceId[6].replace('microsoft.', 'azure.');
    }
  }
  return logEntry;
}

// Add log generation time as a timestamp
function addTimestamp(logEntry) {
  if (
    logEntry.time !== undefined &&
    typeof logEntry.time === 'string' &&
    !isNaN(Date.parse(logEntry.time))
  ) {
    logEntry.timestamp = Date.parse(logEntry.time);
  } else if (
    logEntry.timeStamp !== undefined &&
    typeof logEntry.timeStamp === 'string' &&
    !isNaN(Date.parse(logEntry.timeStamp))
  ) {
    logEntry.timestamp = Date.parse(logEntry.timeStamp);
  }

  return logEntry;
}

function transformData(logs, context) {
  // buffer is an array of JSON objects
  let buffer = [];

  let parsedLogs = parseData(logs, context);

  // type JSON object
  if (
    !Array.isArray(parsedLogs) &&
    typeof parsedLogs === 'object' &&
    parsedLogs !== null
  ) {
    if (parsedLogs.records !== undefined) {
      context.log('Type of logs: records Object');
      parsedLogs.records.forEach((log) => buffer.push(log));
      return buffer;
    }
    context.log('Type of logs: JSON Object');
    buffer.push(parsedLogs);
    return buffer;
  }

  // Bad Format
  if (!Array.isArray(parsedLogs)) {
    return buffer;
  }

  if (typeof parsedLogs[0] === 'object' && parsedLogs[0] !== null) {
    // type JSON records
    if (parsedLogs[0].records !== undefined) {
      context.log('Type of logs: records Array');
      parsedLogs.forEach((message) => {
        message.records.forEach((log) => buffer.push(log));
      });
      return buffer;
    } // type JSON array
    context.log('Type of logs: JSON Array');
    // normally should be "buffer.push(log)" but that will fail if the array mixes JSON and strings
    parsedLogs.forEach((log) => buffer.push({ message: log }));
    // Our API can parse the data in "log" to a JSON and ignore "message", so we are good!
    return buffer;
  }
  if (typeof parsedLogs[0] === 'string') {
    // type string array
    context.log('Type of logs: string Array');
    parsedLogs.forEach((logString) => buffer.push({ message: logString }));
    return buffer;
  }
  return buffer;
}

function parseData(logs, context) {
  if (!Array.isArray(logs)) {
    try {
      return JSON.parse(logs); // for strings let's see if we can parse it into Object
    } catch {
      context.warn('cannot parse logs to JSON');
      return logs;
    }
  }
  try {
    // if there is any exception during JSON.parse,
    // it would be either due to logs in object format itself or log strings in non-json format.
    return logs.map((log) => JSON.parse(log));
  } catch (e) {
    // for both of the above exception cases, return logs would be fine.
    return logs;
  }
}

function httpSend(data, context) {
  return new Promise((resolve, reject) => {
    const urlObj = url.parse(NR_ENDPOINT);
    const options = {
      hostname: urlObj.hostname,
      port: 443,
      path: urlObj.pathname,
      protocol: urlObj.protocol,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Encoding': 'gzip',
      },
    };

    if (NR_LICENSE_KEY) {
      options.headers['X-License-Key'] = NR_LICENSE_KEY;
    } else {
      options.headers['X-Insert-Key'] = NR_INSERT_KEY;
    }

    var req = https.request(options, (res) => {
      var body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        body += chunk; // don't really do anything with body
      });
      res.on('end', () => {
        context.log('Got response:' + res.statusCode);
        if (res.statusCode === 202) {
          resolve(body);
        } else {
          reject({ error: null, res: res });
        }
      });
    });

    req.on('error', (e) => {
      reject({ error: e, res: null });
    });
    req.write(data);
    req.end();
  });
}

/**
 * Retry with Promise
 * fn: the function to try
 * retry: the number of retries
 * interval: the interval in millisecs between retries
 * fnParams: list of params to pass to the function
 * @returns A promise that resolves to the final result
 */

function retryMax(fn, retry, interval, fnParams) {
  return fn.apply(this, fnParams).catch((err) => {
    return retry > 1
      ? wait(interval).then(() => retryMax(fn, retry - 1, interval, fnParams))
      : Promise.reject(err);
  });
}

function wait(delay) {
  return new Promise((fulfill) => {
    setTimeout(fulfill, delay || 0);
  });
}

// Exported for unit testing
module.exports._test = {
  transformData,
  parseData,
  addMetadata,
  addTimestamp,
  getTags,
  getPayload,
  getCommonAttributes,
  compressData,
  compressAndSend,
  httpSend,
  retryMax,
  wait,
};
