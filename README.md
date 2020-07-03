[![Community Project header](https://github.com/newrelic/open-source-office/raw/master/examples/categories/images/Community_Project.png)](https://github.com/newrelic/open-source-office/blob/master/examples/categories/index.md#community-project)

# newrelic-azure-functions 
![GitHub release (latest SemVer including pre-releases)](https://img.shields.io/github/v/release/newrelic/newrelic-azure-functions?include_prereleases) [![Known Vulnerabilities](https://snyk.io/test/github/newrelic-experimental/newrelic-azure-functions/badge.svg?targetFile=package.json)](https://snyk.io/test/github/newrelic-experimental/newrelic-azure-functions?targetFile=package.json)

This repository contains functions to collect and forward logs from Microsoft Azure Blob Storage and Event Hubs.

## Configuration

For setup instructions, click on the name of the function you wish to configure below.

 | Function | Description | Data Sources |
| -------------| ----------- | -------------- |
|[New Relic Event Hub Function](EventHub)| Collects and forwards log data from Azure Event Hubs to New Relic Logs. | <ul><li>[Azure Activity and Resource Logs](https://docs.microsoft.com/en-us/azure/azure-monitor/platform/resource-logs-stream-event-hubs)</li><li>[Azure Active Directory](https://docs.microsoft.com/en-us/azure/active-directory/reports-monitoring/tutorial-azure-monitor-stream-logs-to-event-hub)</li></ul>|
|[New Relic Azure Blob Storage Function](BlobForwarder) | Collects and forwards log data from Azure Blob Storage to New Relic Logs.| <ul><li>[Azure App Service](https://docs.microsoft.com/en-us/azure/app-service/troubleshoot-diagnostic-logs#enable-application-logging-windows)</li><li>[Azure Web Server](https://docs.microsoft.com/en-us/azure/app-service/troubleshoot-diagnostic-logs#enable-web-server-logging)</li></ul> |

## Support

New Relic hosts and moderates an online forum where customers can interact with New Relic employees as well as other customers to get help and share best practices. Like all official New Relic open source projects, there's a related Community topic in the New Relic Explorers Hub. You can find this project's topic/threads here:

>Add the url for the support thread here

## Contributing
Full details about how to contribute to
Contributions to improve newrelic-azure-functions are encouraged! Keep in mind when you submit your pull request, you'll need to sign the CLA via the click-through using CLA-Assistant. You only have to sign the CLA one time per project.
To execute our corporate CLA, which is required if your contribution is on behalf of a company, or if you have any questions, please drop us an email at open-source@newrelic.com.

## License
newrelic-azure-functions is licensed under the [Apache 2.0](http://apache.org/licenses/LICENSE-2.0.txt) License.
