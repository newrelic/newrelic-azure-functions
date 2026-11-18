const config = require("./.releaserc.base.json");

// On develop, don't commit anything back (stamped templates, changelog, package*.json):
// a "-develop.N" version would reach master via the develop -> master merge and become
// the Deploy to Azure default. Only master releases commit these files.
if (process.env.GITHUB_REF_NAME === "develop") {
  const git = config.plugins.find((p) => p[0] === "@semantic-release/git")[1];
  git.assets = [];
}

module.exports = config;
