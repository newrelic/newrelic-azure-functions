[![Community header](https://github.com/newrelic/opensource-website/raw/master/src/images/categories/Community_Project.png)](https://opensource.newrelic.com/oss-category/#community-project)

# New Relic Azure Functions
![GitHub release (latest SemVer including pre-releases)](https://img.shields.io/github/v/release/newrelic/newrelic-azure-functions?include_prereleases) [![Known Vulnerabilities](https://snyk.io/test/github/newrelic-experimental/newrelic-azure-functions/badge.svg?targetFile=package.json)](https://snyk.io/test/github/newrelic-experimental/newrelic-azure-functions?targetFile=package.json)

This repository contains functions to collect and forward logs from Microsoft
Azure Blob Storage and Event Hubs and [Azure ARM templates](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/overview) 
to automate the deployment of those.

## Configuration

For setup instructions, click on the name of the function you wish to configure below.

| Function | Description | Data Sources |
| -------------| ----------- | -------------- |
|[New Relic Event Hub Function](LogForwarder/EventHubForwarder)| Collects and forwards log data from Azure Event Hubs to New Relic Logs. | <ul><li>[Azure Activity and Resource Logs](https://docs.microsoft.com/en-us/azure/azure-monitor/platform/resource-logs-stream-event-hubs)</li><li>[Azure Active Directory](https://docs.microsoft.com/en-us/azure/active-directory/reports-monitoring/tutorial-azure-monitor-stream-logs-to-event-hub)</li></ul>|
|[New Relic Azure Blob Storage Function](LogForwarder/BlobForwarder) | Collects and forwards log data from Azure Blob Storage to New Relic Logs.| <ul><li>[Azure App Service](https://docs.microsoft.com/en-us/azure/app-service/troubleshoot-diagnostic-logs#enable-application-logging-windows)</li><li>[Azure Web Server](https://docs.microsoft.com/en-us/azure/app-service/troubleshoot-diagnostic-logs#enable-web-server-logging)</li></ul> |

## Contributing

Contributions to improve newrelic-azure-functions are encouraged! Keep in mind when you submit your pull request, you'll need to sign the CLA via the click-through using CLA-Assistant. You only have to sign the CLA one time per project.
To execute our corporate CLA, which is required if your contribution is on behalf of a company, or if you have any questions, please drop us an email at open-source@newrelic.com.

Here are some general guidelines
1. PR owners would follow the code review process and standards team has established.
1. Thorough testing must be done by PR owners to ensure new feature works and no regressions.
1. Add/Update any applicable tests as part of PR.
1. Breakdown PRs into multiple PRs if needed to reduce chances of breaking changes.

## Community

New Relic hosts and moderates an online forum where customers can interact with New Relic employees as well as other customers to get help and share best practices. Like all official New Relic open source projects, there's a related Community topic in the New Relic Explorers Hub: [Log forwarding](https://discuss.newrelic.com/tag/log-forwarding)

## A note about vulnerabilities

As noted in our [security policy](../../security/policy), New Relic is committed to the privacy and security of our customers and their data. We believe that providing coordinated disclosure by security researchers and engaging with the security community are important means to achieve our security goals.

If you believe you have found a security vulnerability in this project or any of New Relic's products or websites, we welcome and greatly appreciate you reporting it to New Relic through [HackerOne](https://hackerone.com/newrelic).

If you would like to contribute to this project, review [these guidelines](https://opensource.newrelic.com/code-of-conduct/).

## License
newrelic-azure-functions is licensed under the [Apache 2.0](http://apache.org/licenses/LICENSE-2.0.txt) License.

