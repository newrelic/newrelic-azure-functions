const sleep = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

const currentTimeAsIso8601 = () => new Date().toISOString();

const ONE_SECOND = 1000;
const ONE_MINUTE = 60 * ONE_SECOND;

module.exports = {
  ONE_SECOND,
  ONE_MINUTE,
  currentTimeAsIso8601,
  sleep,
};
