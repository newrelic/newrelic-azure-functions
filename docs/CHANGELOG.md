## [2.5.1](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v2.5.0...v2.5.1) (2024-10-01)


### Bug Fixes

* removes accidentally pasted link ([ff77c00](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/ff77c00fdd45b7da85fe4cc21a28ce3481959b9a))
* removes Content Share when using private Storage Account connectivity ([2bbc01b](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/2bbc01b39a7c16d57a6a0cadec4db8971d650ce1))

# [2.5.0](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v2.4.1...v2.5.0) (2024-05-27)


### Features

* update Node version for blobforwarder and github workflows ([cf8e6e4](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/cf8e6e42afc7400daf098112df4d914ce735a7a7))

## [2.4.1](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v2.4.0...v2.4.1) (2024-05-14)


### Bug Fixes

* semantic release fix ([d8175d3](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/d8175d3a1ad8347e2e9b6efa46df42ff2bab0157))

# [2.4.0](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v2.3.0...v2.4.0) (2024-05-14)


### Features

* Code unified for Blob forwarder and EventHub forwarder functions ([7ce3d1b](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/7ce3d1b748fcd327009f9b240fdf4eb72b441cf9))
* releaserc updated for new release with code unification ([dbb0a72](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/dbb0a72ed6b58d91eb89e0af462c44ce6bd08644))

# [2.4.0](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v2.3.0...v2.4.0) (2024-05-14)


### Features

* Code unified for Blob forwarder and EventHub forwarder functions ([7ce3d1b](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/7ce3d1b748fcd327009f9b240fdf4eb72b441cf9))

# [2.3.0](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v2.2.0...v2.3.0) (2024-04-19)


### Features

* Update readme and gitignore ([8bf03d0](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/8bf03d050ec2d04e6d77ce8d44d35930bd12ee0d))

# [2.2.0](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v2.1.0...v2.2.0) (2023-05-18)


### Features

* Extends BlobForwarder ARM template to use secured settings for Azure resources ([#83](https://github.com/newrelic-experimental/newrelic-azure-functions/issues/83)) ([e42d040](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/e42d04094749ff908f3f93ec6ed36f079718721a))

# [2.1.0](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v2.0.1...v2.1.0) (2023-05-15)


### Features

* Trigger new version ([bd01120](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/bd01120f82e3e6b030a6eef7be2bd769de5b1a3e))

## [2.0.1](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v2.0.0...v2.0.1) (2022-12-14)


### Bug Fixes

* producer policy should depend on consumer policy ([#72](https://github.com/newrelic-experimental/newrelic-azure-functions/issues/72)) ([5deeef5](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/5deeef50872523706984c2b3ed7f4b58bbcbf575))

# [2.0.0](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v1.2.1...v2.0.0) (2022-12-05)


### Features

* upgrade to azure functions 4 ([#63](https://github.com/newrelic-experimental/newrelic-azure-functions/issues/63)) ([8bf1ff0](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/8bf1ff090eba4bcd1176839ae923399f0c0e331f))


### BREAKING CHANGES

* The azure functions library and node versions
are upgraded, this could include breaking changes, and if not,
we want to treat it as a new major anyway.

## [1.2.1](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v1.2.0...v1.2.1) (2022-02-02)


### Bug Fixes

* add null check for parsedLogs[0] ([c44c62d](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/c44c62dab4a60ab8ed23710605ec954c0d5f7162))

# [1.2.0](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v1.1.0...v1.2.0) (2021-09-27)


### Features

* Introduces new Azure ARM template to deploy BlobForwarder ([fa8c6b4](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/fa8c6b4a12c524aedac8734527530f71581e1e07))

# [1.1.0](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v1.0.1...v1.1.0) (2021-09-10)


### Features

* update EventHubForwarder ARM template and Function App configuration to read Event Hubs from the end and add template outputs for the Event Hub connection. ([050777e](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/050777e916dce4bbb2af75c42f52a183b27cae75))

## [1.0.1](https://github.com/newrelic-experimental/newrelic-azure-functions/compare/v1.0.0...v1.0.1) (2021-09-09)


### Bug Fixes

* Fix colon ([#44](https://github.com/newrelic-experimental/newrelic-azure-functions/issues/44)) ([56a3e44](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/56a3e44680370417fbbedd190c5d38d6ff672951))

# 1.0.0 (2020-07-09)


### Bug Fixes

* [LOGGING-2708] Automatically updates version in index.js before packaging ([f5899b2](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/f5899b2323706437738972b4824dadb67ea524e8))
* [LOGGING-2708] Empty commit to trigger new release ([5557083](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/5557083faea3c9952ecf6eb1fd93a46bc8520ab9))
* [LOGGING-2708] Missing details to complete the repository setup ([a48cccb](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/a48cccb5a76658e8236e9795e73da9de29de53c7))
* [LOGGING-2708] Sets different names for the different Azure Functions ([be9f14d](https://github.com/newrelic-experimental/newrelic-azure-functions/commit/be9f14d49af09ae168d568dd00b56dc5c1d38a1d))
