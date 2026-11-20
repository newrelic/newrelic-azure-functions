'use strict';

const {
  LOGGER,
  MESSAGE,
  config,
  validate,
  slotSeq,
  blobName,
  buildRecord,
  emit,
} = require('../a2q/function/lib');

const baseCfg = {
  container: 'c',
  runId: 'run1',
  lineIntervalSeconds: 300,
  recordBytes: 512,
  linesPerBlob: 1,
};

// Stand-in for an @azure/storage-blob ContainerClient.
function fakeContainer(behaviour = {}) {
  const uploads = [];
  return {
    uploads,
    getBlockBlobClient: (name) => ({
      upload: async (body, length, options) => {
        if (behaviour.error) throw behaviour.error;
        uploads.push({ name, body, length, options });
      },
    }),
  };
}

describe('config', () => {
  it('uses the defaults', () => {
    expect(config({ CONTAINER_NAME: 'c', RUN_ID: 'r' })).toEqual({
      container: 'c',
      runId: 'r',
      lineIntervalSeconds: 300,
      recordBytes: 512,
      linesPerBlob: 1,
    });
  });

  it('reads overrides and ignores empty values', () => {
    const cfg = config({
      LINE_INTERVAL_SECONDS: '60',
      RECORD_BYTES: '256',
      LINES_PER_BLOB: '3',
    });
    expect(cfg.lineIntervalSeconds).toBe(60);
    expect(cfg.recordBytes).toBe(256);
    expect(cfg.linesPerBlob).toBe(3);
    expect(config({ LINES_PER_BLOB: '' }).linesPerBlob).toBe(1);
  });
});

describe('validate', () => {
  it('accepts a valid config', () => {
    expect(() => validate(baseCfg)).not.toThrow();
  });

  it.each([
    [{ container: '' }, 'CONTAINER_NAME is required'],
    [{ runId: undefined }, 'RUN_ID is required'],
    [{ lineIntervalSeconds: 0 }, 'LINE_INTERVAL_SECONDS must be greater'],
    [{ linesPerBlob: 0 }, 'LINES_PER_BLOB must be a whole number'],
    [{ linesPerBlob: 1.5 }, 'LINES_PER_BLOB must be a whole number'],
    [{ linesPerBlob: 5000 }, 'LINES_PER_BLOB x RECORD_BYTES'],
  ])('rejects %j', (override, message) => {
    expect(() => validate({ ...baseCfg, ...override })).toThrow(message);
  });
});

describe('slotSeq', () => {
  it('returns the epoch second of the interval mark', () => {
    expect(slotSeq(1795113600000, 300)).toBe(1795113600);
    expect(slotSeq(1795113600123, 300)).toBe(1795113600);
    expect(slotSeq(1795113899999, 300)).toBe(1795113600);
    expect(slotSeq(1795113900000, 300)).toBe(1795113900);
  });

  it('works for other intervals', () => {
    expect(slotSeq(1795113659000, 60)).toBe(1795113660 - 60);
  });
});

describe('blobName', () => {
  it('is derived from the run id and seq', () => {
    expect(blobName('run1', 1795113600)).toBe('a2q/run1/1795113600.json');
  });
});

describe('buildRecord', () => {
  const now = new Date('2026-11-19T18:40:00.123Z');

  it('is exactly recordBytes long, one line, valid JSON', () => {
    const line = buildRecord(baseCfg, 1795113600, now);
    expect(Buffer.byteLength(line)).toBe(512);
    expect(line.endsWith('\n')).toBe(true);
    expect(line.trim().split('\n')).toHaveLength(1);
    const rec = JSON.parse(line);
    expect(rec).toMatchObject({
      level: 'INFO',
      logger: LOGGER,
      message: MESSAGE,
      seq: 1795113600,
      run_id: 'run1',
      blob: 'a2q/run1/1795113600.json',
      generated_at: '2026-11-19T18:40:00.123Z',
      time: '2026-11-19 18:40:00.123',
    });
  });

  it('has the same size whatever the seq or run id', () => {
    const a = buildRecord(baseCfg, 1795113600, now);
    const b = buildRecord(
      { ...baseCfg, runId: 'a-much-longer-run-id' },
      1,
      now
    );
    expect(Buffer.byteLength(a)).toBe(Buffer.byteLength(b));
  });

  it('adds line and msg_id only for multi-line blobs', () => {
    const single = JSON.parse(buildRecord(baseCfg, 10, now));
    expect(single).not.toHaveProperty('line');
    expect(single).not.toHaveProperty('msg_id');
    const multi = JSON.parse(buildRecord(baseCfg, 10, now, 2, 3));
    expect(multi.line).toBe(2);
    expect(multi.msg_id).toBe('10-2');
    expect(Buffer.byteLength(buildRecord(baseCfg, 10, now, 2, 3))).toBe(512);
  });

  it('throws if recordBytes is too small', () => {
    expect(() => buildRecord({ ...baseCfg, recordBytes: 50 }, 1, now)).toThrow(
      'RECORD_BYTES 50 too small'
    );
  });
});

describe('emit', () => {
  const now = new Date('2026-11-19T18:40:02.000Z');
  const seq = 1795113600;

  it('writes one new blob with one line, write-once', async () => {
    const container = fakeContainer();
    const result = await emit(baseCfg, container, now);
    expect(result).toMatchObject({
      seq,
      lines: 1,
      blob: `a2q/run1/${seq}.json`,
      written: true,
      bytes: 512,
    });
    expect(container.uploads).toHaveLength(1);
    const [upload] = container.uploads;
    expect(upload.name).toBe(`a2q/run1/${seq}.json`);
    expect(upload.length).toBe(512);
    expect(upload.options.conditions).toEqual({ ifNoneMatch: '*' });
    expect(upload.options.blobHTTPHeaders.blobContentType).toBe(
      'application/json'
    );
  });

  it('writes N lines with unique msg_id in one blob', async () => {
    const container = fakeContainer();
    const result = await emit({ ...baseCfg, linesPerBlob: 3 }, container, now);
    expect(result).toMatchObject({ seq, lines: 3, written: true, bytes: 1536 });
    const lines = container.uploads[0].body.trim().split('\n');
    expect(lines).toHaveLength(3);
    const records = lines.map((l) => JSON.parse(l));
    expect(records.map((r) => r.msg_id)).toEqual([
      `${seq}-0`,
      `${seq}-1`,
      `${seq}-2`,
    ]);
    expect(new Set(records.map((r) => r.seq))).toEqual(new Set([seq]));
  });

  it('reports exists when the blob is already there', async () => {
    const error = Object.assign(new Error('exists'), { statusCode: 409 });
    const result = await emit(baseCfg, fakeContainer({ error }), now);
    expect(result).toMatchObject({ seq, written: false });
  });

  it('also recognises the BlobAlreadyExists code', async () => {
    const error = Object.assign(new Error('exists'), {
      code: 'BlobAlreadyExists',
    });
    const result = await emit(baseCfg, fakeContainer({ error }), now);
    expect(result.written).toBe(false);
  });

  it('rethrows other errors', async () => {
    const error = Object.assign(new Error('denied'), { statusCode: 403 });
    await expect(emit(baseCfg, fakeContainer({ error }), now)).rejects.toThrow(
      'denied'
    );
  });
});
