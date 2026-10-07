const config = require("./.releaserc.base.json");

// On develop, don't commit the stamped templates: a "-develop.N" version would reach
// master via the develop -> master merge and become the Deploy to Azure default.
if (process.env.GITHUB_REF_NAME === "develop") {
  const git = config.plugins.find((p) => p[0] === "@semantic-release/git")[1];
  git.assets = git.assets.filter((a) => !/^(armTemplates|bicep)\//.test(a));
}

module.exports = config;
