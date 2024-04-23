const retryingAxios = require('./retryingAxios');
const { sleep } = require('./time');
const logger = require('./logger');
const { HTTP_RETRY_COUNT, WAIT_BETWEEN_QUERY_RETRIES } = require('./waitTimes');

/**
 * Retries a call if the GraphQL response contains an error.
 */
const retryingGraphQlCall = async (url, payload, configuration) => {
  // Since we use '<=' in the for loop, response is always set before the for loop exits
  // (one loop for the "main" call, and then one loop for each allowed retry -- the main
  // loop is "retry=0")
  let response = null;

  for (let retry = 0; retry <= HTTP_RETRY_COUNT; ++retry) {
    // Pause before retrying
    if (retry > 0) {
      logger.debug(
        `GraphQL retry attempt ${retry}, waiting ${WAIT_BETWEEN_QUERY_RETRIES} milliseconds`
      );
      await sleep(WAIT_BETWEEN_QUERY_RETRIES);
    }

    // Make remote call
    response = await retryingAxios.post(url, payload, configuration);
    if (!response.data.errors) {
      break;
    }
    logger.debug('GraphQL call got error', response.data.errors);
  }

  return response;
};

module.exports = {
  retryingGraphQlCall,
};
