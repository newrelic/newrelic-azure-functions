'use strict';

/**
 * VNet Flow Logs Forwarder — Flow Log Parser
 *
 * Parses PT1H.json delta fragments into structured log records
 * suitable for New Relic ingestion.
 *
 * PT1H.json structure (VNet Flow Logs v2):
 * {
 *   "records": [
 *     {
 *       "time": "2024-01-01T00:00:00.0000000Z",
 *       "flowLogVersion": 4,
 *       "flowLogGUID": "...",
 *       "macAddress": "...",
 *       "category": "FlowLogFlowEvent",
 *       "flowLogResourceID": "/subscriptions/.../...",
 *       "targetResourceID": "/subscriptions/.../...",
 *       "operationName": "FlowLogFlowEvent",
 *       "flowRecords": {
 *         "flows": [
 *           {
 *             "aclID": "...",
 *             "flowGroups": [
 *               {
 *                 "rule": "...",
 *                 "flowTuples": [
 *                   "1699990055,10.0.0.4,10.0.0.5,12345,443,6,O,A,C,1,100,1,80"
 *                 ]
 *               }
 *             ]
 *           }
 *         ]
 *       }
 *     }
 *   ]
 * }
 *
 * Flow Tuple CSV format (VNet Flow Logs):
 *   0: Timestamp (Unix epoch seconds)
 *   1: Source IP
 *   2: Destination IP
 *   3: Source Port
 *   4: Destination Port
 *   5: Protocol (6=TCP, 17=UDP, 1=ICMP)
 *   6: Direction (I=Inbound, O=Outbound)
 *   7: Action (A=Allowed, D=Denied)
 *   8: State (B=Begin, C=Continuing, E=End)
 *   9: Packets (source to destination)
 *   10: Bytes (source to destination)
 *   11: Packets (destination to source)
 *   12: Bytes (destination to source)
 */

const config = require('./config');

const PROTOCOL_MAP = {
  6: 'TCP',
  17: 'UDP',
  1: 'ICMP',
};

const DIRECTION_MAP = {
  I: 'Inbound',
  O: 'Outbound',
};

const ACTION_MAP = {
  A: 'Allowed',
  D: 'Denied',
};

const STATE_MAP = {
  B: 'Begin',
  C: 'Continuing',
  E: 'End',
};

/**
 * Parse a raw delta string from the PT1H.json blob into an array of records.
 *
 * The delta is a JSON fragment — it may start/end mid-array. We handle:
 * - Complete JSON (first block set)
 * - Fragment starting with comma + records (appended blocks)
 * - Fragment with trailing comma or incomplete trailing record
 *
 * @param {string} rawDelta - Raw text downloaded from delta blocks
 * @returns {Array<Object>} Parsed record objects from the "records" array
 */
function parseRawDelta(rawDelta) {
  if (!rawDelta || rawDelta.trim().length === 0) {
    return [];
  }

  let text = rawDelta.trim();

  // Strategy 1: Try parsing as complete JSON
  try {
    const parsed = JSON.parse(text);
    if (parsed.records && Array.isArray(parsed.records)) {
      return parsed.records;
    }
    if (Array.isArray(parsed)) {
      return parsed;
    }
    return [parsed];
  } catch {
    // Not complete JSON — handle as fragment
  }

  // Strategy 2: Fragment from appended blocks
  // The delta often looks like: ,{"time":"...","flowRecords":{...}}\n]}\n
  // or: ,{"time":"..."},{"time":"..."}
  // Strip leading/trailing structural chars and wrap as array

  // Remove leading comma if present
  if (text.startsWith(',')) {
    text = text.slice(1);
  }

  // Remove trailing incomplete structures
  // If ends with "]}" it's the file close — strip it
  if (text.endsWith(']}')) {
    text = text.slice(0, -2);
  } else if (text.endsWith(']\n}')) {
    text = text.slice(0, -3);
  } else if (text.endsWith(']\r\n}')) {
    text = text.slice(0, -4);
  }

  // Trim trailing commas
  text = text.replace(/,\s*$/, '');

  // Wrap in array and parse
  try {
    const records = JSON.parse(`[${text}]`);
    return records;
  } catch {
    // Strategy 3: Try to salvage line by line
    return parseLineByLine(text);
  }
}

/**
 * Fallback: parse individual JSON objects separated by commas/newlines.
 */
function parseLineByLine(text) {
  const records = [];
  // Split on },{ boundaries
  const parts = text.split(/\}\s*,\s*\{/);
  for (let i = 0; i < parts.length; i++) {
    let part = parts[i];
    if (i > 0) part = '{' + part;
    if (i < parts.length - 1) part = part + '}';
    try {
      records.push(JSON.parse(part));
    } catch {
      // Skip unparseable fragments
    }
  }
  return records;
}

/**
 * Extract metadata from a blob path.
 *
 * Example path: resourceId=/SUBSCRIPTIONS/{sub}/RESOURCEGROUPS/{rg}/PROVIDERS/
 *   MICROSOFT.NETWORK/NETWORKSECURITYGROUPS/{name}/y=2024/m=01/d=15/h=10/
 *   m=00/macAddress={mac}/PT1H.json
 *
 * @param {string} blobPath - The blob name within the container
 * @returns {Object} Extracted metadata
 */
function extractMetadataFromPath(blobPath) {
  const metadata = {};
  const lower = blobPath.toLowerCase();

  // Extract subscription ID
  const subMatch = lower.match(/subscriptions\/([^/]+)/);
  if (subMatch) metadata.subscriptionId = subMatch[1];

  // Extract resource group
  const rgMatch = lower.match(/resourcegroups\/([^/]+)/);
  if (rgMatch) metadata.resourceGroup = rgMatch[1];

  // Extract resource type and name (e.g., virtualNetworks/myVnet or networkSecurityGroups/myNsg)
  const providerMatch = blobPath.match(
    /PROVIDERS\/MICROSOFT\.NETWORK\/([^/]+)\/([^/]+)/i
  );
  if (providerMatch) {
    metadata.resourceType = providerMatch[1];
    metadata.resourceName = providerMatch[2];
  }

  // Extract MAC address
  const macMatch = blobPath.match(/macAddress=([^/]+)/i);
  if (macMatch) metadata.macAddress = macMatch[1];

  // Extract date-hour
  const dateMatch = blobPath.match(
    /y=(\d{4})\/m=(\d{2})\/d=(\d{2})\/h=(\d{2})/
  );
  if (dateMatch) {
    metadata.year = dateMatch[1];
    metadata.month = dateMatch[2];
    metadata.day = dateMatch[3];
    metadata.hour = dateMatch[4];
  }

  return metadata;
}

/**
 * Parse a single flow tuple CSV string into a structured object.
 *
 * @param {string} tuple - CSV string
 * @returns {Object} Structured flow record
 */
function parseFlowTuple(tuple) {
  const fields = tuple.split(',');
  const record = {
    timestamp: parseInt(fields[0], 10) * 1000, // Convert to epoch ms
    srcAddr: fields[1] || '',
    destAddr: fields[2] || '',
    srcPort: parseInt(fields[3], 10) || 0,
    destPort: parseInt(fields[4], 10) || 0,
    protocol: PROTOCOL_MAP[fields[5]] || fields[5] || '',
    direction: DIRECTION_MAP[fields[6]] || fields[6] || '',
    action: ACTION_MAP[fields[7]] || fields[7] || '',
    state: STATE_MAP[fields[8]] || fields[8] || '',
  };

  // Packet/byte counts (may not be present in all versions)
  if (fields[9]) record.packetsSrcToDest = parseInt(fields[9], 10) || 0;
  if (fields[10]) record.bytesSrcToDest = parseInt(fields[10], 10) || 0;
  if (fields[11]) record.packetsDestToSrc = parseInt(fields[11], 10) || 0;
  if (fields[12]) record.bytesDestToSrc = parseInt(fields[12], 10) || 0;

  return record;
}

/**
 * Transform parsed PT1H.json records into New Relic log entries.
 *
 * @param {Array<Object>} records - Parsed JSON records from PT1H.json
 * @param {Object} pathMetadata - Metadata extracted from blob path
 * @returns {Array<Object>} Array of NR log entry objects
 */
function transformRecords(records, pathMetadata) {
  const logEntries = [];

  for (const record of records) {
    const baseAttrs = {
      'azure.subscriptionId': pathMetadata.subscriptionId || '',
      'azure.resourceGroup': pathMetadata.resourceGroup || '',
      'azure.resourceType': pathMetadata.resourceType || '',
      'azure.resourceName': pathMetadata.resourceName || '',
      'azure.macAddress': pathMetadata.macAddress || record.macAddress || '',
      'azure.category': record.category || 'FlowLogFlowEvent',
      'azure.operationName': record.operationName || '',
      'azure.flowLogVersion': record.flowLogVersion || '',
      'azure.flowLogGUID': record.flowLogGUID || '',
      'azure.flowLogResourceID': record.flowLogResourceID || '',
      'azure.targetResourceID': record.targetResourceID || '',
    };

    // Extract flow tuples from nested structure
    const flowRecords = record.flowRecords || {};
    const flows = flowRecords.flows || [];
    let recordHasTuples = false;

    for (const flow of flows) {
      const aclID = flow.aclID || '';
      const flowGroups = flow.flowGroups || [];

      for (const group of flowGroups) {
        const rule = group.rule || '';
        const tuples = group.flowTuples || [];

        for (const tuple of tuples) {
          recordHasTuples = true;
          const parsed = parseFlowTuple(tuple);
          logEntries.push({
            timestamp: parsed.timestamp,
            message: tuple,
            attributes: {
              ...baseAttrs,
              'flow.aclID': aclID,
              'flow.rule': rule,
              'flow.srcAddr': parsed.srcAddr,
              'flow.destAddr': parsed.destAddr,
              'flow.srcPort': parsed.srcPort,
              'flow.destPort': parsed.destPort,
              'flow.protocol': parsed.protocol,
              'flow.direction': parsed.direction,
              'flow.action': parsed.action,
              'flow.state': parsed.state,
              'flow.packetsSrcToDest': parsed.packetsSrcToDest,
              'flow.bytesSrcToDest': parsed.bytesSrcToDest,
              'flow.packetsDestToSrc': parsed.packetsDestToSrc,
              'flow.bytesDestToSrc': parsed.bytesDestToSrc,
            },
          });
        }
      }
    }

    // If no flow tuples found for this record, still emit it as a log entry
    if (!recordHasTuples && record.time) {
      logEntries.push({
        timestamp: Date.parse(record.time),
        message: JSON.stringify(record),
        attributes: baseAttrs,
      });
    }
  }

  return logEntries;
}

module.exports = {
  parseRawDelta,
  extractMetadataFromPath,
  parseFlowTuple,
  transformRecords,
  // Exported for testing
  parseLineByLine,
  PROTOCOL_MAP,
  DIRECTION_MAP,
  ACTION_MAP,
  STATE_MAP,
};
