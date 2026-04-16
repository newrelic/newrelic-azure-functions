'use strict';

const https = require('https');
const zlib = require('zlib');
const { EventEmitter } = require('events');

jest.mock('https');

const OLD_ENV = process.env;
process.env = {
  ...OLD_ENV,
  NR_LICENSE_KEY: 'test-license-key',
  NR_ENDPOINT: 'https://log-api.newrelic.com/log/v1',
  NR_TAGS: 'env:prod;team:myTeam',
  NR_MAX_RETRIES: '3',
  NR_RETRY_INTERVAL: '10',
};

const main = require('../LogForwarder/index');
const {
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
} = main._test;

afterAll(() => {
  process.env = OLD_ENV;
});

function createMockContext() {
  return {
    functionName: 'TestFunction',
    invocationId: 'test-invocation-id',
    log: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  };
}

function mockHttpResponse(statusCode, body = '') {
  https.request.mockImplementation((_options, callback) => {
    const res = new EventEmitter();
    res.statusCode = statusCode;
    res.setEncoding = jest.fn();

    callback(res);

    process.nextTick(() => {
      res.emit('data', body);
      res.emit('end');
    });

    const req = new EventEmitter();
    req.write = jest.fn();
    req.end = jest.fn();
    return req;
  });
}

function mockHttpError(error) {
  https.request.mockImplementation(() => {
    const req = new EventEmitter();
    req.write = jest.fn();
    req.end = jest.fn();

    process.nextTick(() => {
      req.emit('error', error);
    });

    return req;
  });
}

describe('addMetadata', () => {
  test('extracts subscriptionId, resourceGroup, and source from valid resourceId', () => {
    const logEntry = {
      resourceId:
        '/subscriptions/sub-123/resourceGroups/my-rg/providers/microsoft.compute/virtualMachines/my-vm',
    };
    const result = addMetadata(logEntry);
    expect(result.metadata).toBeDefined();
    expect(result.metadata.subscriptionId).toBe('sub-123');
    expect(result.metadata.resourceGroup).toBe('my-rg');
    expect(result.metadata.source).toBe('azure.compute');
  });

  test('replaces microsoft. prefix with azure. in source', () => {
    const logEntry = {
      resourceId:
        '/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/accounts/sa',
    };
    const result = addMetadata(logEntry);
    expect(result.metadata.source).toBe('azure.storage');
  });

  test('returns logEntry unchanged when resourceId is missing', () => {
    const logEntry = { message: 'hello' };
    const result = addMetadata(logEntry);
    expect(result.metadata).toBeUndefined();
    expect(result).toEqual({ message: 'hello' });
  });

  test('returns logEntry unchanged when resourceId is not a string', () => {
    const logEntry = { resourceId: 12345 };
    const result = addMetadata(logEntry);
    expect(result.metadata).toBeUndefined();
  });

  test('returns logEntry unchanged when resourceId does not start with /subscriptions/', () => {
    const logEntry = { resourceId: '/some/other/path' };
    const result = addMetadata(logEntry);
    expect(result.metadata).toBeUndefined();
  });
});

describe('addTimestamp', () => {
  test('sets timestamp from valid "time" field', () => {
    const logEntry = { time: '2024-01-15T10:30:00Z' };
    const result = addTimestamp(logEntry);
    expect(result.timestamp).toBe(Date.parse('2024-01-15T10:30:00Z'));
  });

  test('sets timestamp from valid "timeStamp" field', () => {
    const logEntry = { timeStamp: '2024-06-01T00:00:00Z' };
    const result = addTimestamp(logEntry);
    expect(result.timestamp).toBe(Date.parse('2024-06-01T00:00:00Z'));
  });

  test('prefers "time" over "timeStamp" when both are present', () => {
    const logEntry = {
      time: '2024-01-01T00:00:00Z',
      timeStamp: '2024-06-01T00:00:00Z',
    };
    const result = addTimestamp(logEntry);
    expect(result.timestamp).toBe(Date.parse('2024-01-01T00:00:00Z'));
  });

  test('does not set timestamp for invalid date string', () => {
    const logEntry = { time: 'not-a-date' };
    const result = addTimestamp(logEntry);
    expect(result.timestamp).toBeUndefined();
  });

  test('does not set timestamp when no time field exists', () => {
    const logEntry = { message: 'hello' };
    const result = addTimestamp(logEntry);
    expect(result.timestamp).toBeUndefined();
  });

  test('does not set timestamp when time is not a string', () => {
    const logEntry = { time: 12345 };
    const result = addTimestamp(logEntry);
    expect(result.timestamp).toBeUndefined();
  });
});

describe('getTags', () => {
  test('parses semicolon-separated key:value tags', () => {
    const tags = getTags();
    expect(tags).toEqual({ env: 'prod', team: 'myTeam' });
  });

  test('all returned tags have both key and value', () => {
    const tags = getTags();
    Object.entries(tags).forEach(([key, value]) => {
      expect(key).toBeTruthy();
      expect(value).toBeTruthy();
    });
  });
});

describe('parseData', () => {
  let context;

  beforeEach(() => {
    context = createMockContext();
  });

  test('parses a valid JSON string into an object', () => {
    const result = parseData('{"key":"value"}', context);
    expect(result).toEqual({ key: 'value' });
  });

  test('returns raw string when JSON parsing fails', () => {
    const result = parseData('not json', context);
    expect(result).toBe('not json');
    expect(context.warn).toHaveBeenCalledWith('cannot parse logs to JSON');
  });

  test('parses array of JSON strings', () => {
    const result = parseData(['{"a":1}', '{"b":2}'], context);
    expect(result).toEqual([{ a: 1 }, { b: 2 }]);
  });

  test('returns original array when JSON parsing of elements fails', () => {
    const input = ['not json 1', 'not json 2'];
    const result = parseData(input, context);
    expect(result).toEqual(input);
  });

  test('returns original array when elements are already objects', () => {
    const input = [{ a: 1 }, { b: 2 }];
    const result = parseData(input, context);
    expect(result).toEqual(input);
  });
});

describe('transformData', () => {
  let context;

  beforeEach(() => {
    context = createMockContext();
  });

  test('extracts records from a single JSON string with .records', () => {
    const input = JSON.stringify({
      records: [{ message: 'log1' }, { message: 'log2' }],
    });
    const result = transformData(input, context);
    expect(result).toEqual([{ message: 'log1' }, { message: 'log2' }]);
  });

  test('wraps a single JSON string without .records in array', () => {
    const input = JSON.stringify({ key: 'value' });
    const result = transformData(input, context);
    expect(result).toEqual([{ key: 'value' }]);
  });

  test('extracts records from array of JSON strings with .records', () => {
    const input = [
      JSON.stringify({ records: [{ msg: 'a' }] }),
      JSON.stringify({ records: [{ msg: 'b' }] }),
    ];
    const result = transformData(input, context);
    expect(result).toEqual([{ msg: 'a' }, { msg: 'b' }]);
  });

  test('wraps array of JSON objects without .records in {message}', () => {
    const input = [JSON.stringify({ foo: 'bar' }), JSON.stringify({ baz: 1 })];
    const result = transformData(input, context);
    expect(result).toEqual([
      { message: { foo: 'bar' } },
      { message: { baz: 1 } },
    ]);
  });

  test('wraps array of plain strings in {message}', () => {
    const input = ['log line 1', 'log line 2'];
    const result = transformData(input, context);
    expect(result).toEqual([
      { message: 'log line 1' },
      { message: 'log line 2' },
    ]);
  });

  test('returns empty array for empty input', () => {
    const result = transformData([], context);
    expect(result).toEqual([]);
  });

  test('returns empty array when parsed data is not array or object', () => {
    const result = transformData(['42'], context);
    expect(result).toEqual([]);
  });
});

describe('getPayload', () => {
  test('wraps logs in New Relic API format', () => {
    const context = createMockContext();
    const logs = [{ message: 'test' }];
    const payload = getPayload(logs, context);

    expect(Array.isArray(payload)).toBe(true);
    expect(payload).toHaveLength(1);
    expect(payload[0].common).toBeDefined();
    expect(payload[0].logs).toEqual(logs);
  });

  test('includes correct common attributes', () => {
    const context = createMockContext();
    const payload = getPayload([], context);
    const attrs = payload[0].common.attributes;

    expect(attrs.plugin.type).toBe('azure');
    expect(attrs.azure.forwardername).toBe('TestFunction');
    expect(attrs.azure.invocationid).toBe('test-invocation-id');
    expect(attrs.tags).toEqual(getTags());
  });
});

describe('compressData', () => {
  test('compresses data with gzip and can be decompressed', async () => {
    const input = JSON.stringify({ message: 'test' });
    const compressed = await compressData(input);
    expect(Buffer.isBuffer(compressed)).toBe(true);
    expect(compressed.length).toBeGreaterThan(0);

    const decompressed = await new Promise((resolve, reject) => {
      zlib.gunzip(compressed, (err, data) => {
        if (err) reject(err);
        else resolve(data.toString());
      });
    });
    expect(decompressed).toBe(input);
  });
});

describe('retryMax', () => {
  test('resolves when function succeeds on first try', async () => {
    const fn = jest.fn().mockResolvedValue('success');
    const result = await retryMax(fn, 3, 10, []);
    expect(result).toBe('success');
    expect(fn).toHaveBeenCalledTimes(1);
  });

  test('retries and resolves when function fails then succeeds', async () => {
    const fn = jest
      .fn()
      .mockRejectedValueOnce(new Error('fail'))
      .mockResolvedValue('success');
    const result = await retryMax(fn, 3, 10, []);
    expect(result).toBe('success');
    expect(fn).toHaveBeenCalledTimes(2);
  });

  test('rejects after all retries are exhausted', async () => {
    const fn = jest.fn().mockRejectedValue(new Error('always fails'));
    await expect(retryMax(fn, 2, 10, [])).rejects.toThrow('always fails');
    expect(fn).toHaveBeenCalledTimes(2);
  });

  test('passes fnParams to the function', async () => {
    const fn = jest.fn().mockResolvedValue('ok');
    await retryMax(fn, 1, 10, ['arg1', 'arg2']);
    expect(fn).toHaveBeenCalledWith('arg1', 'arg2');
  });
});

describe('wait', () => {
  test('resolves after the specified delay', async () => {
    const start = Date.now();
    await wait(50);
    const elapsed = Date.now() - start;
    expect(elapsed).toBeGreaterThanOrEqual(40);
  });

  test('resolves immediately when delay is 0', async () => {
    const start = Date.now();
    await wait(0);
    const elapsed = Date.now() - start;
    expect(elapsed).toBeLessThan(50);
  });
});

describe('httpSend', () => {
  let context;

  beforeEach(() => {
    context = createMockContext();
    https.request.mockReset();
  });

  test('resolves on HTTP 202 response', async () => {
    mockHttpResponse(202, 'ok');
    const result = await httpSend(Buffer.from('test'), context);
    expect(result).toBe('ok');
    expect(context.log).toHaveBeenCalledWith('Got response:202');
  });

  test('rejects on non-202 response', async () => {
    mockHttpResponse(500, 'error');
    await expect(httpSend(Buffer.from('test'), context)).rejects.toEqual(
      expect.objectContaining({ error: null })
    );
  });

  test('rejects on network error', async () => {
    mockHttpError(new Error('ECONNREFUSED'));
    await expect(httpSend(Buffer.from('test'), context)).rejects.toEqual(
      expect.objectContaining({
        error: expect.any(Error),
        res: null,
      })
    );
  });

  test('sends X-License-Key header when NR_LICENSE_KEY is set', async () => {
    mockHttpResponse(202);
    await httpSend(Buffer.from('test'), context);

    const requestOptions = https.request.mock.calls[0][0];
    expect(requestOptions.headers['X-License-Key']).toBe('test-license-key');
    expect(requestOptions.headers['X-Insert-Key']).toBeUndefined();
  });

  test('sends correct Content-Type and Content-Encoding headers', async () => {
    mockHttpResponse(202);
    await httpSend(Buffer.from('test'), context);

    const requestOptions = https.request.mock.calls[0][0];
    expect(requestOptions.headers['Content-Type']).toBe('application/json');
    expect(requestOptions.headers['Content-Encoding']).toBe('gzip');
  });
});

describe('compressAndSend', () => {
  let context;

  beforeEach(() => {
    context = createMockContext();
    https.request.mockReset();
  });

  test('sends payload successfully when under size limit', async () => {
    mockHttpResponse(202);
    const data = [{ message: 'small log' }];
    await compressAndSend(data, context);
    expect(context.log).toHaveBeenCalledWith(
      'Logs payload successfully sent to New Relic.'
    );
  });

  test('logs error when single log exceeds size limit', async () => {
    const crypto = require('crypto');
    const hugeMessage = crypto.randomBytes(1100 * 1024).toString('hex');
    const data = [{ message: hugeMessage }];
    await compressAndSend(data, context);
    expect(context.error).toHaveBeenCalledWith(
      'Cannot send the payload as the size of single line exceeds the limit'
    );
  });

  test('splits and sends both halves when multiple logs exceed size limit', async () => {
    mockHttpResponse(202);
    const crypto = require('crypto');
    const bigMessage = crypto.randomBytes(600 * 1024).toString('hex');
    const data = [{ message: bigMessage }, { message: bigMessage }];
    await compressAndSend(data, context);
    expect(context.error).not.toHaveBeenCalledWith(
      'Cannot send the payload as the size of single line exceeds the limit'
    );
  });

  test('logs error when max retries exceeded on HTTP failure', async () => {
    mockHttpResponse(500, 'Internal Server Error');
    const data = [{ message: 'test' }];
    await compressAndSend(data, context);
    expect(context.error).toHaveBeenCalledWith(
      'Max retries reached: failed to send logs payload to New Relic'
    );
  });
});

describe('main', () => {
  let context;

  beforeEach(() => {
    context = createMockContext();
    https.request.mockReset();
  });

  test('handles string input by splitting on newlines', async () => {
    mockHttpResponse(202);
    await main('line1\nline2', context);
    expect(context.log).toHaveBeenCalledWith(
      'Logs payload successfully sent to New Relic.'
    );
  });

  test('handles Buffer input', async () => {
    mockHttpResponse(202);
    const buffer = Buffer.from('buffered log line');
    await main(buffer, context);
    expect(context.log).toHaveBeenCalledWith(
      'Logs payload successfully sent to New Relic.'
    );
  });

  test('handles array input', async () => {
    mockHttpResponse(202);
    await main(['log1', 'log2'], context);
    expect(context.log).toHaveBeenCalledWith(
      'Logs payload successfully sent to New Relic.'
    );
  });

  test('handles object input', async () => {
    mockHttpResponse(202);
    await main({ key: 'value' }, context);
    expect(context.log).toHaveBeenCalledWith(
      'Logs payload successfully sent to New Relic.'
    );
  });

  test('handles array of JSON objects with records', async () => {
    mockHttpResponse(202);
    const input = [
      JSON.stringify({
        records: [
          {
            message: 'record1',
            time: '2024-01-01T00:00:00Z',
            resourceId:
              '/subscriptions/sub-1/resourceGroups/rg-1/providers/microsoft.compute/vm/my-vm',
          },
        ],
      }),
    ];
    await main(input, context);
    expect(context.log).toHaveBeenCalledWith(
      'Logs payload successfully sent to New Relic.'
    );
  });

  test('returns early with warning when logs format is invalid', async () => {
    await main([], context);
    expect(context.warn).toHaveBeenCalledWith('logs format is invalid');
  });
});

describe('main - no auth keys', () => {
  test('returns early and logs error when no auth keys are configured', async () => {
    jest.resetModules();

    const savedKey = process.env.NR_LICENSE_KEY;
    const savedInsertKey = process.env.NR_INSERT_KEY;
    delete process.env.NR_LICENSE_KEY;
    delete process.env.NR_INSERT_KEY;

    const mainNoAuth = require('../LogForwarder/index');

    process.env.NR_LICENSE_KEY = savedKey;
    if (savedInsertKey) process.env.NR_INSERT_KEY = savedInsertKey;

    const context = createMockContext();
    await mainNoAuth(['test'], context);
    expect(context.error).toHaveBeenCalledWith(
      expect.stringContaining('LICENSE key')
    );
  });
});