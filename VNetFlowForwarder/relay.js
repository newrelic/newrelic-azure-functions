'use strict';

/**
 * VNet Flow Logs Forwarder — Event Grid Relay Function
 *
 * Triggered by Event Grid BlobCreated events on the flow-log storage container.
 * Re-publishes each event to Event Hub with partitionKey = event.subject (blob path)
 * to guarantee per-file chronological ordering within a partition.
 */

const { EventHubProducerClient } = require('@azure/event-hubs');
const config = require('./config');

let producerClient = null;

/**
 * Get or create the Event Hub producer client (lazy singleton).
 */
function getProducerClient() {
  if (!producerClient) {
    producerClient = new EventHubProducerClient(
      config.eventhubConnection,
      config.eventhubName
    );
  }
  return producerClient;
}

/**
 * Relay handler: receives an Event Grid event and publishes it to Event Hub
 * with the blob path as partition key.
 *
 * @param {Object} event - Event Grid event object
 * @param {Object} context - Azure Function context
 */
async function relayHandler(event, context) {
  // Event Grid CloudEvents or EventGridSchema — extract subject (blob path)
  const subject = event.subject || event.data?.url || '';
  if (!subject) {
    context.warn('Relay received event with no subject. Skipping.');
    return;
  }

  if (config.debugEnabled) {
    context.log(`Relay: forwarding event for ${subject}`);
  }

  const producer = getProducerClient();
  const batch = await producer.createBatch({
    partitionKey: subject,
  });

  const eventBody = {
    subject,
    eventType: event.eventType || 'Microsoft.Storage.BlobCreated',
    data: event.data || {},
    eventTime: event.eventTime || new Date().toISOString(),
  };

  const added = batch.tryAdd({ body: eventBody });
  if (!added) {
    context.error(
      `Relay: event too large for Event Hub batch. Subject: ${subject}`
    );
    return;
  }

  // SDK handles retries internally via built-in exponential backoff (retryOptions)
  await producer.sendBatch(batch);

  if (config.debugEnabled) {
    context.log(`Relay: event sent to Event Hub partition (key=${subject})`);
  }
}

/**
 * Reset the producer client (for testing).
 */
function resetClient() {
  producerClient = null;
}

module.exports = {
  relayHandler,
  resetClient,
  _getProducerClient: getProducerClient,
};
