const Nrdb = require('./lib/nrdb');
const { v4: uuidv4 } = require('uuid');
const { requireEnvironmentVariable } = require('./lib/environmentVariables');
const { waitForLogMessageContaining, countAll } = require('./lib/test-util');

const { beforeEach } = require('node:test');
const { ONE_MINUTE } = require('./lib/time');

process.env.NR_LICENSE_KEY = requireEnvironmentVariable('LICENSE_KEY');
process.env.NR_ENDPOINT = requireEnvironmentVariable('LOGS_API');
process.env.NR_TAGS = 'test:azureUnit;test2:success';
const blobForwader = require('../LogForwarder/index');

/**
 * This tests all things directly configurable from the Infrastructure Agent.
 *
 * See https://docs.newrelic.com/docs/logs/forward-logs/forward-your-logs-using-infrastructure-agent.
 */
describe('Blob Forwader tests', () => {
  let nrdb;
  let context = {};
  const OLD_ENV = process.env;

  beforeAll(() => {
    context.log = (message) => console.log(message);
    context.log.info = (message) => console.log(message);
    context.log.warn = (message) => console.log(message);
    context.log.error = (message) => console.log(message);
    context.executionContext = {
      functionName: 'Blob Forwarding',
      invocationid: 'Test function',
    };

    const accountId = requireEnvironmentVariable('ACCOUNT_ID');
    const apiKey = requireEnvironmentVariable('API_KEY');
    const nerdGraphUrl = requireEnvironmentVariable('NERD_GRAPH_URL');

    // Read configuration
    nrdb = new Nrdb({
      accountId,
      apiKey,
      nerdGraphUrl,
    });
  });

  beforeEach(() => {
    process.env = { ...OLD_ENV };
  });

  afterAll(() => {
    process.env = OLD_ENV; // Restore old environment
  });

  test('a simple blob forwarding', async () => {
    // Create a string with a unique value in it so that we can find it later
    const uuid = uuidv4();
    const line = `Lorem Ipsum is simply dummy text of the printing and typesetting industry - ${uuid}`;
    let buffer = Buffer.from(line);

    await blobForwader(context, buffer);
    // Wait for that log line to show up in NRDB
    await waitForLogMessageContaining(nrdb, line);
  }, 20000);

  test('a simple blob forwarding count test', async () => {
    // Create a string with a unique value in it so that we can find it later
    const uuid = uuidv4();

    let nLine = 5;
    let line = generateNLines(
      `Lorem Ipsum is simply dummy text of the printing and typesetting industry - ${uuid}`,
      nLine
    );
    let buffer = Buffer.from(line);

    await blobForwader(context, buffer);
    // Wait for that log line to show up in NRDB
    await countAll(
      nrdb,
      `Lorem Ipsum is simply dummy text of the printing and typesetting industry - ${uuid}`,
      nLine
    );
  }, 20000);

  test(
    'a huge blob forwarding divide and conquer test',
    async () => {
      // Create a string with a unique value in it so that we can find it later
      const uuid = uuidv4();

      let nLine = 500000;
      let line = generateNLines(
        `Lorem Ipsum is simply dummy text of the printing and typesetting industry - ${uuid}`,
        nLine
      );

      let buffer = Buffer.from(line);

      await blobForwader(context, buffer);
      // Wait for that log line to show up in NRDB
      await countAll(
        nrdb,
        `Lorem Ipsum is simply dummy text of the printing and typesetting industry - ${uuid}`,
        nLine
      );
    },
    10 * ONE_MINUTE
  );

  test(
    'compressed single line > 1MB test',
    async () => {
      // Create a string with a unique value in it so that we can find it later
      const uuid = uuidv4();

      let nLine = 500000;
      let line = '';
      while (nLine--) {
        line +=
          `Lorem Ipsum is simply dummy text of the printing and typesetting industry - ${uuid} - ` +
          nLine;
      }

      let buffer = Buffer.from(line);

      try {
        await blobForwader(context, buffer);
      } catch (e) {
        expect(e.message).toBe(
          'Cannot send the payload as the size of single line exceeds the limit'
        );
      }
    },
    10 * ONE_MINUTE
  );
});

const generateNLines = (content, nLine) => {
  let lines = '';
  while (nLine--) {
    lines += content + nLine + '\n';
  }
  return lines;
};
