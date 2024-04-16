const { sleep } = require('./time');
const logger = require('./logger');
const { retryingGraphQlCall } = require('./nerdGraph');
const {
  WAIT_BETWEEN_QUERY_RETRIES,
  WAIT_FOR_PROCESSING,
  DEFAULT_SINCE,
  NRQL_QUERY_TIMEOUT_IN_SECONDS,
} = require('./waitTimes');
const { logAxiosError } = require("./errors");
const { option } = require('yargs');

const _messageComparer = (message1, message2) => {
  // Sort first by batch index, and then by segment ID
  return (
    message1['newrelic.logs.batchIndex'] - message2['newrelic.logs.batchIndex'] ||
    _getSafeSegmentId(message1) - _getSafeSegmentId(message2)
  );
};

const _getSafeSegmentId = (message) => {
  const defaultValue = 0;
  const metadata = message['newrelic.logs.metadata'];
  if (!metadata) {
    return defaultValue;
  }

  const parsed = JSON.parse(metadata);
  return parsed.segment_id || defaultValue;
};

/**
 * Depending on what was selected ('*', 'uniques', 'uniqueCount'), you'll
 * get results with different field names. This just picks out the right one.
 */
const _getResults = (response) => {
  const { data, errors } = response.data;
  if (errors) {
    throw errors;
  }

  const results = data.actor.account.nrql.results;

  // SELECT *
  if (results.events !== undefined) {
    return results.events;
  }

  // SELECT uniques(...)
  if (results.members !== undefined) {
    return results.members;
  }

  // SELECT uniqueCount(...)
  if (results.uniqueCount !== undefined) {
    return [results.uniqueCount];
  }

  // used for LPE test cases for list of cells
  if (results['uniques.cell'] !== undefined) {
    return results['uniques.cell'];
  }

  if (results !== []) {
    return results;
  }

  logger.error('Unhandled result type', results);
  throw new Error('Unhandled result type');
};

const _findAll = async (account, options) => {
  const { select, from, where, since, until, limit } = options;

  let query = `select ${select} from ${from} `;
  if (where) query = query + `WHERE ${where} `;
  if (since) query = query + `SINCE ${since} `;
  if (until) query = query + `UNTIL ${until} `;
  if (limit) query = query + `LIMIT ${limit} `;

  const generateNrqlGqlQuery = (nrql, accountId) => {
    const query = `query($nrql: Nrql!){
        actor {
          account(id: ${accountId}) {
            nrql(query: $nrql, timeout: ${NRQL_QUERY_TIMEOUT_IN_SECONDS}) {
              results
            }
          }
        }
      }`;
    return { query, variables: { nrql } };
  };

  const payload = generateNrqlGqlQuery(query, account.accountId);

  const url = account.nerdGraphUrl;

  try {
    logger.debug('Searching NRDB', { url, query });
    const headers = {
      'Content-Type': 'application/json',
      'API-Key': account.apiKey,
    };

    const response = await retryingGraphQlCall(url, payload, { headers: headers });

    const nrdbData = _getResults(response);

    return nrdbData.sort(_messageComparer);
  } catch (error) {
    logAxiosError(`Error querying NRQL for account ${account}: ${query}`, error);
    throw error;
  }
};

const _waitToFindOne = async (account, options) => {
  const expectedCount = 1;
  options.limit = 1;
  let nrdbData = await _waitToFindAll(account, options, expectedCount);
  return nrdbData[0];
};

// Queries NRDB for all the records (MAX 2000) matching the clauses.
// This will retry querying NRDB until at least one log line is returned.
const _waitToFindAll = async (account, options, expectedCount) => {
  return _waitForeverToFindAll(account, options, expectedCount);
};

const _waitForeverToFindAll = async (account, options, expectedCount) => {
  let requestTimedOut = false;

  let timeoutHandle = setTimeout(() => {
    requestTimedOut = true;
    logger.debug(`Timed out while fetching logs for query ${options.where} in NRDB`);
  }, options.wait);

  const foundAll = (results) => {
    if (expectedCount === undefined) {
      return true;
    }

    return results !== null && results.length >= expectedCount;
  };

  let results;
  while (!requestTimedOut) {
    results = await _findAll(account, options);
    if (foundAll(results)) {
      clearTimeout(timeoutHandle);
      return results;
    }

    await sleep(WAIT_BETWEEN_QUERY_RETRIES);
  }

  throw options.didNotFindAllResultsMessage(results, expectedCount);
};

function Nrdb(account) {
  const defaultOptions = {
    select: '*',
    from: 'Log',
    limit: '2000',
    wait: WAIT_FOR_PROCESSING,
    since: DEFAULT_SINCE,
    didNotFindAllResultsMessage: (foundResults, expectedResultCount) => {
      return (
        `Timed out waiting for all ${expectedResultCount} expected query results.` +
        ` Found '${JSON.stringify(foundResults)}'`
      );
    },
  };

  return {
    /**
     * Takes a QueryOptions object. See the README for details of that object.
     *
     * Returns a promise that resolves to an event received from NRDB.
     */
    waitToFindOne: (options) => {
      return _waitToFindOne(account, { ...defaultOptions, ...options });
    },

    /**
     * Takes a QueryOptions object. See the README for details of that object.
     *
     * Returns a promise that resolves to all the matching events received from NRDB.
     * Messages will get returned sorted first by batch index, and then by segment ID.
     */
    waitToFindAll: (options, expectedCount) => {
      return _waitToFindAll(account, { ...defaultOptions, ...options }, expectedCount);
    },
  };
}

module.exports = Nrdb;
