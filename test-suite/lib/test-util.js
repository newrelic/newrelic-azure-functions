const { spawnSync } = require('child_process');
const logger = require('./logger');
const { sleep } = require('./time');
const { WAIT_BETWEEN_QUERY_RETRIES } = require('./waitTimes');

const testOnlyIfSet = (environmentVariableName) => {
  return process.env[environmentVariableName] ? test : test.skip;
};

const waitForLogMessageContaining = async (nrdb, substring) => {
  return nrdb.waitToFindOne({
    where: `message like '%${substring}%' and plugin.type = 'azure'`,
  });
};

const countAll = async (nrdb, substring, expectedCount) => {
  let nRetries = 60;

  while (nRetries--) {
    let result = await nrdb.waitToFindOne({
      where: `message like '%${substring}%' and plugin.type = 'azure' and tags.test = 'azureUnit' and tags.test2 = 'success'`,
      select: 'count(*)',
    });
    if (result.count === expectedCount) return expectedCount;
    else
      console.log(
        'Count not matching, expected: ' +
          expectedCount +
          ', actual: ' +
          result.count
      );
    await sleep(WAIT_BETWEEN_QUERY_RETRIES);
  }

  throw 'Logs count did not match';
};

const executeSync = (command, commandArguments, expectedExitCode) => {
  const result = spawnSync(command, commandArguments);

  logger.info(result.stdout?.toString());
  logger.error(result.stderr?.toString());
  expect(result.status).toEqual(expectedExitCode);
};

module.exports = {
  testOnlyIfSet,
  waitForLogMessageContaining,
  countAll,
  executeSync,
};
