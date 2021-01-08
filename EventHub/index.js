/**
 * This is an azure function to collect logs data from EventHub and send it to New Relic logs API.
 *    Author: Amine Benzaied
 *    Team: Expert Services
 */

'use strict';

var https = require('https');
var url = require('url');
var zlib = require('zlib');

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

module.exports = async function main(context, eventHubMessages) {
  if (!NR_LICENSE_KEY && !NR_INSERT_KEY) {
    context.log.error(
      'You have to configure either your LICENSE key or insights INSERT key. ' +
        'Please follow the instructions in README'
    );
    return;
  }
  let buffer = transformData(eventHubMessages, context);
  if (buffer.length === 0) {
    context.log.warn('logs format is invalid');
    return;
  }
  let compressedPayload;
  let payloads = generatePayloads(buffer, context);
  for (const payload of payloads) {
    try {
      compressedPayload = await compressData(JSON.stringify(payload));
      try {
        await retryMax(httpSend, NR_MAX_RETRIES, NR_RETRY_INTERVAL, [
          compressedPayload,
          context,
        ]);
        context.log('Logs payload successfully sent to New Relic.');
      } catch(e) {
        context.log.error(
          'Max retries reached: failed to send logs payload to New Relic'
        );
        context.log.error('Exception:', JSON.stringify(e));
      }
    } catch(e) {
      context.log.error('Error during payload compression.');
      context.log.error('Exception:', JSON.stringify(e));
    }
  }
};

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

function generatePayloads(logs, context) {
  const common = {
    attributes: {
      plugin: {
        type: NR_LOGS_SOURCE,
        version: VERSION,
      },
      azure: {
        forwardername: context.executionContext.functionName,
        invocationid: context.executionContext.invocationId,
      },
      tags: getTags(),
    },
  };
  let payload = [
    {
      common: common,
      logs: [],
    },
  ];
  let payloads = [];

  logs.forEach((logLine) => {
    const log = addMetadata(logLine);
    if (
      JSON.stringify(payload).length + JSON.stringify(log).length <
      NR_MAX_PAYLOAD_SIZE
    ) {
      payload[0].logs.push(log);
    } else {
      payloads.push(payload);
      payload = [
        {
          common: common,
          logs: [],
        },
      ];
      payload[0].logs.push(log);
    }
  });
  payloads.push(payload);
  return payloads;
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

  if (typeof parsedLogs[0] === 'object') {
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
  let newLogs = logs;

  if (!Array.isArray(logs)) {
    try {
      newLogs = JSON.parse(logs); // for strings let's see if we can parse it into Object
    } catch {
      context.log.warn('cannot parse logs to JSON');
    }
  } else {
    newLogs = logs.map((log) => {
      // for arrays let's see if we can parse it into array of Objects
      try {
        return JSON.parse(log);
      } catch {
        return log;
      }
    });
  }

  return newLogs;
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
