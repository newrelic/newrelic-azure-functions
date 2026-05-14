'use strict';

/**
 * Unit tests for VNet Flow Logs Forwarder
 */

// Mock environment before requiring modules
process.env.NR_LICENSE_KEY = 'test-license-key';
process.env.SOURCE_STORAGE_CONNECTION = 'DefaultEndpointsProtocol=https;AccountName=test;AccountKey=dGVzdA==;EndpointSuffix=core.windows.net';
process.env.CURSOR_STORAGE_CONNECTION = 'DefaultEndpointsProtocol=https;AccountName=test;AccountKey=dGVzdA==;EndpointSuffix=core.windows.net';
process.env.EVENTHUB_CONNECTION = 'Endpoint=sb://test.servicebus.windows.net/;SharedAccessKeyName=test;SharedAccessKey=dGVzdA==';
process.env.EVENTHUB_NAME = 'eh-vnetflow';
process.env.CURSOR_TABLE_NAME = 'cursors';
process.env.VNETFLOW_RELAY_ENABLED = 'true';
process.env.VNETFLOW_CONSUMER_ENABLED = 'true';

const parser = require('../VNetFlowForwarder/parser');
const cursor = require('../VNetFlowForwarder/cursor');
const delta = require('../VNetFlowForwarder/delta');
const delivery = require('../VNetFlowForwarder/delivery');
const config = require('../VNetFlowForwarder/config');

// ─── Parser Tests ───────────────────────────────────────────────────────────

describe('Parser', () => {
  describe('parseFlowTuple', () => {
    it('should parse a complete flow tuple CSV', () => {
      const tuple = '1699990055,10.0.0.4,10.0.0.5,12345,443,6,O,A,C,10,1500,8,1200';
      const result = parser.parseFlowTuple(tuple);

      expect(result.timestamp).toBe(1699990055000);
      expect(result.srcAddr).toBe('10.0.0.4');
      expect(result.destAddr).toBe('10.0.0.5');
      expect(result.srcPort).toBe(12345);
      expect(result.destPort).toBe(443);
      expect(result.protocol).toBe('TCP');
      expect(result.direction).toBe('Outbound');
      expect(result.action).toBe('Allowed');
      expect(result.state).toBe('Continuing');
      expect(result.packetsSrcToDest).toBe(10);
      expect(result.bytesSrcToDest).toBe(1500);
      expect(result.packetsDestToSrc).toBe(8);
      expect(result.bytesDestToSrc).toBe(1200);
    });

    it('should handle UDP inbound denied', () => {
      const tuple = '1699990100,192.168.1.1,10.0.0.1,8080,53,17,I,D,B,1,64,0,0';
      const result = parser.parseFlowTuple(tuple);

      expect(result.protocol).toBe('UDP');
      expect(result.direction).toBe('Inbound');
      expect(result.action).toBe('Denied');
      expect(result.state).toBe('Begin');
    });

    it('should handle tuple with missing optional fields', () => {
      const tuple = '1699990055,10.0.0.4,10.0.0.5,12345,443,6,O,A,E';
      const result = parser.parseFlowTuple(tuple);

      expect(result.timestamp).toBe(1699990055000);
      expect(result.state).toBe('End');
      expect(result.packetsSrcToDest).toBeUndefined();
    });
  });

  describe('parseRawDelta', () => {
    it('should parse complete PT1H.json', () => {
      const json = JSON.stringify({
        records: [
          {
            time: '2024-01-01T00:00:00Z',
            macAddress: 'AABBCCDDEEFF',
            flowRecords: { flows: [] },
          },
        ],
      });
      const result = parser.parseRawDelta(json);
      expect(result).toHaveLength(1);
      expect(result[0].macAddress).toBe('AABBCCDDEEFF');
    });

    it('should parse a JSON fragment (appended blocks)', () => {
      const fragment = ',{"time":"2024-01-01T01:00:00Z","macAddress":"112233445566","flowRecords":{"flows":[]}}]}';
      const result = parser.parseRawDelta(fragment);
      expect(result).toHaveLength(1);
      expect(result[0].macAddress).toBe('112233445566');
    });

    it('should parse multiple records in a fragment', () => {
      const fragment = ',{"time":"T1","macAddress":"AA"},{"time":"T2","macAddress":"BB"}]}';
      const result = parser.parseRawDelta(fragment);
      expect(result).toHaveLength(2);
      expect(result[0].macAddress).toBe('AA');
      expect(result[1].macAddress).toBe('BB');
    });

    it('should return empty array for empty input', () => {
      expect(parser.parseRawDelta('')).toEqual([]);
      expect(parser.parseRawDelta(null)).toEqual([]);
      expect(parser.parseRawDelta('   ')).toEqual([]);
    });

    it('should handle array input', () => {
      const json = JSON.stringify([{ time: 'T1' }, { time: 'T2' }]);
      const result = parser.parseRawDelta(json);
      expect(result).toHaveLength(2);
    });
  });

  describe('extractMetadataFromPath', () => {
    it('should extract all metadata from a VNet flow log path', () => {
      const path =
        'resourceId=/SUBSCRIPTIONS/sub-123/RESOURCEGROUPS/rg-prod/PROVIDERS/MICROSOFT.NETWORK/VIRTUALNETWORKS/myVnet/y=2024/m=03/d=15/h=10/m=00/macAddress=AABBCCDDEEFF/PT1H.json';
      const meta = parser.extractMetadataFromPath(path);

      expect(meta.subscriptionId).toBe('sub-123');
      expect(meta.resourceGroup).toBe('rg-prod');
      expect(meta.resourceType).toBe('VIRTUALNETWORKS');
      expect(meta.resourceName).toBe('myVnet');
      expect(meta.macAddress).toBe('AABBCCDDEEFF');
      expect(meta.year).toBe('2024');
      expect(meta.month).toBe('03');
      expect(meta.day).toBe('15');
      expect(meta.hour).toBe('10');
    });

    it('should handle NSG flow log path', () => {
      const path =
        'resourceId=/SUBSCRIPTIONS/abc/RESOURCEGROUPS/rg1/PROVIDERS/MICROSOFT.NETWORK/NETWORKSECURITYGROUPS/myNsg/y=2024/m=01/d=01/h=00/m=00/macAddress=001122334455/PT1H.json';
      const meta = parser.extractMetadataFromPath(path);

      expect(meta.resourceType).toBe('NETWORKSECURITYGROUPS');
      expect(meta.resourceName).toBe('myNsg');
    });

    it('should handle partial paths gracefully', () => {
      const meta = parser.extractMetadataFromPath('some/random/path.json');
      expect(meta.subscriptionId).toBeUndefined();
      expect(meta.macAddress).toBeUndefined();
    });
  });

  describe('transformRecords', () => {
    it('should transform records with flow tuples into log entries', () => {
      const records = [
        {
          time: '2024-01-01T00:00:00Z',
          macAddress: 'AABBCCDDEEFF',
          category: 'FlowLogFlowEvent',
          flowLogVersion: 4,
          flowLogGUID: 'guid-123',
          flowLogResourceID: '/sub/rg/provider/res',
          targetResourceID: '/sub/rg/provider/target',
          operationName: 'FlowLogFlowEvent',
          flowRecords: {
            flows: [
              {
                aclID: 'acl-1',
                flowGroups: [
                  {
                    rule: 'AllowAll',
                    flowTuples: [
                      '1699990055,10.0.0.4,10.0.0.5,12345,443,6,O,A,C,10,1500,8,1200',
                      '1699990060,10.0.0.4,10.0.0.6,12346,80,6,O,A,B,1,100,0,0',
                    ],
                  },
                ],
              },
            ],
          },
        },
      ];
      const meta = { subscriptionId: 'sub-1', resourceGroup: 'rg-1' };
      const entries = parser.transformRecords(records, meta);

      expect(entries).toHaveLength(2);
      expect(entries[0].timestamp).toBe(1699990055000);
      expect(entries[0].attributes['flow.srcAddr']).toBe('10.0.0.4');
      expect(entries[0].attributes['flow.destPort']).toBe(443);
      expect(entries[0].attributes['flow.protocol']).toBe('TCP');
      expect(entries[0].attributes['azure.subscriptionId']).toBe('sub-1');

      expect(entries[1].timestamp).toBe(1699990060000);
      expect(entries[1].attributes['flow.destAddr']).toBe('10.0.0.6');
    });

    it('should handle records with no flow tuples', () => {
      const records = [
        {
          time: '2024-01-01T00:00:00Z',
          macAddress: 'AABB',
          flowRecords: { flows: [] },
        },
      ];
      const entries = parser.transformRecords(records, {});
      // Falls back to emitting the record itself
      expect(entries).toHaveLength(1);
      expect(entries[0].timestamp).toBe(Date.parse('2024-01-01T00:00:00Z'));
    });
  });
});

// ─── Cursor Tests ───────────────────────────────────────────────────────────

describe('Cursor', () => {
  describe('encodeKeys', () => {
    it('should encode slashes in blob paths', () => {
      const path = '/blobServices/default/containers/insights/blobs/resource/PT1H.json';
      const keys = cursor.encodeKeys(path);

      expect(keys.partitionKey).toBe('vnetflow');
      expect(keys.rowKey).not.toContain('/');
      expect(keys.rowKey).not.toContain('\\');
      expect(keys.rowKey).not.toContain('#');
      expect(keys.rowKey).not.toContain('?');
    });

    it('should produce consistent keys for same input', () => {
      const path = 'container/path/to/blob.json';
      const keys1 = cursor.encodeKeys(path);
      const keys2 = cursor.encodeKeys(path);
      expect(keys1.rowKey).toBe(keys2.rowKey);
    });

    it('should produce different keys for different inputs', () => {
      const keys1 = cursor.encodeKeys('container/path1/blob.json');
      const keys2 = cursor.encodeKeys('container/path2/blob.json');
      expect(keys1.rowKey).not.toBe(keys2.rowKey);
    });
  });
});

// ─── Delta Tests ────────────────────────────────────────────────────────────

describe('Delta', () => {
  describe('parseBlobPath', () => {
    it('should parse Event Grid subject format', () => {
      const subject =
        '/blobServices/default/containers/insights-logs-flowlogflowevent/blobs/resourceId=/SUBSCRIPTIONS/sub/RESOURCEGROUPS/rg/PT1H.json';
      const result = delta.parseBlobPath(subject);

      expect(result.containerName).toBe('insights-logs-flowlogflowevent');
      expect(result.blobName).toBe(
        'resourceId=/SUBSCRIPTIONS/sub/RESOURCEGROUPS/rg/PT1H.json'
      );
    });

    it('should handle simple container/blob format', () => {
      const path = 'mycontainer/path/to/file.json';
      const result = delta.parseBlobPath(path);

      expect(result.containerName).toBe('mycontainer');
      expect(result.blobName).toBe('path/to/file.json');
    });

    it('should throw for invalid path with no slash', () => {
      expect(() => delta.parseBlobPath('nocontainer')).toThrow('Invalid blob path');
    });
  });
});

// ─── Delivery Tests ─────────────────────────────────────────────────────────

describe('Delivery', () => {
  describe('parseTags', () => {
    it('should parse semicolon-separated tags', () => {
      const tags = delivery.parseTags('env:production;team:platform;region:us');
      expect(tags.env).toBe('production');
      expect(tags.team).toBe('platform');
      expect(tags.region).toBe('us');
    });

    it('should handle tags with colons in values', () => {
      const tags = delivery.parseTags('url:https://example.com');
      expect(tags.url).toBe('https://example.com');
    });

    it('should return empty object for empty string', () => {
      expect(delivery.parseTags('')).toEqual({});
      expect(delivery.parseTags(null)).toEqual({});
    });
  });

  describe('buildPayload', () => {
    it('should build correct NR payload structure', () => {
      const entries = [
        { timestamp: 1000, message: 'test', attributes: { foo: 'bar' } },
      ];
      const context = {
        functionName: 'VNetFlowConsumer',
        invocationId: 'inv-123',
      };
      const payload = delivery.buildPayload(entries, context);

      expect(payload).toHaveLength(1);
      expect(payload[0].common.attributes.plugin.type).toBe('azure');
      expect(payload[0].common.attributes.plugin.version).toBe(config.version);
      expect(payload[0].common.attributes.azure.forwardername).toBe('VNetFlowConsumer');
      expect(payload[0].common.attributes.azure.invocationid).toBe('inv-123');
      expect(payload[0].logs).toEqual(entries);
    });
  });

  describe('compress', () => {
    it('should compress data with gzip', async () => {
      const data = JSON.stringify({ test: 'hello world'.repeat(100) });
      const compressed = await delivery.compress(data);

      expect(Buffer.isBuffer(compressed)).toBe(true);
      expect(compressed.length).toBeLessThan(data.length);
    });
  });
});

// ─── Config Tests ───────────────────────────────────────────────────────────

describe('Config', () => {
  it('should return license key as API key', () => {
    expect(config.getApiKey()).toBe('test-license-key');
    expect(config.getApiKeyHeader()).toBe('X-License-Key');
  });

  it('should validate successfully with required vars set', () => {
    expect(() => config.validate()).not.toThrow();
  });

  it('should throw if no license key configured', () => {
    const origLicense = config.nrLicenseKey;
    const origInsert = config.nrInsertKey;
    config.nrLicenseKey = '';
    config.nrInsertKey = '';

    expect(() => config.validate()).toThrow('Missing NR_LICENSE_KEY');

    config.nrLicenseKey = origLicense;
    config.nrInsertKey = origInsert;
  });

  it('should throw if no storage connection', () => {
    const orig = config.sourceStorageConnection;
    config.sourceStorageConnection = '';

    expect(() => config.validate()).toThrow('Missing SOURCE_STORAGE_CONNECTION');

    config.sourceStorageConnection = orig;
  });
});
