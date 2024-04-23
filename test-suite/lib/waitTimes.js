const { ONE_SECOND, ONE_MINUTE } = require('./time');

module.exports = {
  /**
   * How many times to retry an axios HTTP call for a "retryable" error like a network issue
   * or a 429 (temporarily getting rate limited).
   *
   * This is used both for the Logs API (see logsApi.js) and querying NerdGraph (see nerdGraph.js)
   */
  HTTP_RETRY_COUNT: 3,

  /**
   * How long to wait between retrying a query -- either retrying because of an HTTP error (see retryingAxios.js),
   * or because of an error from NerdGraph (see nerdGraph.js)
   */
  WAIT_BETWEEN_QUERY_RETRIES: 5 * ONE_SECOND,

  /**
   * How long it could take our pipeline to process data and get it into NRDB.
   * This should be long enough to cover almost 100% of possible wait times, but short
   * enough so that builds don't wait forever if there's a failure
   */
  WAIT_FOR_PROCESSING: 4 * ONE_MINUTE,

  /**
   * How long it ideally should take for something like 95% of messages to show up. Use this
   * when you are waiting a bit for something to not show up (like for testing
   * drop filters). Use this instead of WAIT_FOR_PROCESSING so that we don't have to
   * wait a super long time for every test run. You may get false positives (maybe
   * the message shows up after this short wait), but it's better than having to wait
   * this long time for each test.
   */
  WAIT_FOR_NON_EXISTENCE: 5 * ONE_SECOND,

  /**
   * How long we want to wait for a test to execute before failing it.
   * This should be long enough to cover almost 100% of possible test runs, but short
   * enough so that builds don't wait forever if they're failing
   */
  WAIT_FOR_TEST_COMPLETION: 1 * ONE_MINUTE,

  /**
   * This should be longer than WAIT_FOR_PROCESSING, so that when tests fail
   * after WAIT_FOR_PROCESSING, nrdb.js can output the results we did find (if instead it is
   * shorter than WAIT_FOR_PROCESSING, any results we do find will have "aged out"
   * by the time the test fails, and we'll think we didn't find any results.
   *
   * We want it to be as short as possible, just to try to decrease the query load on NRDB.
   * The shorter the time range, the fewer logs that NRDB needs to inspect. However, depending
   * on the rate of logs, NRDB may have an archive file opened for a really long time (so there
   * would be logs with a large range of timestamps), and so NRDB might need to inspect logs older
   * than this range anyway. So we should be careful about our time range size, but I'm not sure
   * how important it is to worry about it too much.
   *
   * Note that some fixtures in fixtures/grok-parsing/syslog-rfc5424 rely on this being longer
   * than it takes for `npm test` to run the test (which we've seen to be about 20 minutes in some
   * environments). See comments in those tests for details.
   */
  DEFAULT_SINCE: '30 minutes ago',

  /**
   * Yes, this is a ridiculously large value -- none of the tests
   * should be taking more than a few seconds to execute queries,
   * yet we still hit timeouts occasionally.
   *
   * Maybe that means we need to look at like percentiles of query times,
   * and see what the distribution looks like -- maybe we are mostly a few
   * seconds, but maybe there's hiccups and 1% of queries take much, much longer.
   *
   * NerdGraph allows this value to be as large as 120
   */
  NRQL_QUERY_TIMEOUT_IN_SECONDS: 60,
};
