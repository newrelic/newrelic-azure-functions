const { v4: uuidv4 } = require('uuid');
const { beforeEach } = require('node:test');

const lib = require('logging-integrations-test-lib')({
  serviceName: 'newrelic-azure-functions-tests',
});

const {
  NRDB,
  requireEnvironmentVariable,
  testUtils: { waitForLogMessageContaining, countAll },
} = lib;

process.env.NR_LICENSE_KEY = requireEnvironmentVariable('LICENSE_KEY');
process.env.NR_ENDPOINT = requireEnvironmentVariable('LOGS_API');
process.env.NR_TAGS = 'test:azureUnit;test2:success';
const eventHubForwarder = require('../LogForwarder/index');

/**
 * This tests all things directly configurable from the Infrastructure Agent.
 *
 * See https://docs.newrelic.com/docs/logs/forward-logs/forward-your-logs-using-infrastructure-agent.
 */
describe('Event Hub message Forwader tests', () => {
  let nrdb_instance;
  let context = {};
  const OLD_ENV = process.env;

  beforeAll(() => {
    context.log = (message) => console.log(message);
    context.log.info = (message) => console.log(message);
    context.log.warn = (message) => console.log(message);
    context.log.error = (message) => console.log(message);
    context.executionContext = {
      functionName: 'Event Hub Message Forwarding',
      invocationid: 'Test function',
    };

    const accountId = requireEnvironmentVariable('ACCOUNT_ID');
    const apiKey = requireEnvironmentVariable('API_KEY');
    const nerdGraphUrl = requireEnvironmentVariable('NERD_GRAPH_URL');

    // Read configuration
    nrdb_instance = new NRDB({
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

  test('a simple event hub message forwarding', async () => {
    // Create a string with a unique value in it so that we can find it later
    const uuid = uuidv4();
    const line = `Lorem Ipsum is simply dummy text of the printing and typesetting industry - ${uuid}`;

    await eventHubForwarder(context, [line]);
    // Wait for that log line to show up in NRDB
    await waitForLogMessageContaining(nrdb_instance, line, 'azure');
  }, 20000);

  test('a simple event hub forwarding count test', async () => {
    // Create a string with a unique value in it so that we can find it later
    const uuid = uuidv4();

    let nLine = 5;
    let lines = generateNLines(
      `Lorem Ipsum is simply dummy text of the printing and typesetting industry - ${uuid}`,
      nLine
    );

    await eventHubForwarder(context, lines);
    // Wait for that log line to show up in NRDB
    await countAll(
      nrdb_instance,
      `Lorem Ipsum is simply dummy text of the printing and typesetting industry - ${uuid}`,
      nLine,
      'azure',
      {
        test: 'azureUnit',
        test2: 'success',
      }
    );
  }, 20000);
});

const generateNLines = (content, nLine) => {
  let lines = [];
  while (nLine--) {
    lines.push(content + nLine);
  }
  return lines;
};
