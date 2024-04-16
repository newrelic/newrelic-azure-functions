const requireEnvironmentVariable = (name) => {
  const value = process.env[name];
  if(!value) {
    throw new Error(`No value was for provided for environment variable '${name}'`);
  }
  
  return value;
};

module.exports = {
  requireEnvironmentVariable,
};