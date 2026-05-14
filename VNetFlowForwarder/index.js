'use strict';

/**
 * VNet Flow Logs Forwarder — Function Registration
 *
 * Registers two Azure Functions:
 *   1. VNetFlowRelay: Event Grid trigger -> Event Hub (with partition key)
 *   2. VNetFlowConsumer: Event Hub trigger -> cursor -> delta -> NR
 */

const { app } = require('@azure/functions');
const config = require('./config');
const { relayHandler } = require('./relay');
const { consumerHandler } = require('./consumer');

// Register the Event Grid -> Event Hub relay function
if (config.relayEnabled) {
  app.eventGrid('VNetFlowRelay', {
    handler: async (event, context) => {
      await relayHandler(event, context);
    },
  });
}

// Register the Event Hub consumer function
if (config.consumerEnabled) {
  app.eventHub('VNetFlowConsumer', {
    eventHubName: config.eventhubName,
    connection: 'EVENTHUB_CONSUMER_CONNECTION',
    cardinality: 'many',
    consumerGroup: config.eventhubConsumerGroup,
    handler: async (messages, context) => {
      await consumerHandler(messages, context);
    },
  });
}

module.exports = { relayHandler, consumerHandler };
