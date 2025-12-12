// read and write customer purchase data from MongoDB
// consume purchase messages from Kafka
// expose REST API for reading and writing purchase data
// health check endpoint

import express, { Request, Response, NextFunction } from 'express';
import { Kafka, Consumer } from 'kafkajs';
import mongoose, { Schema } from 'mongoose';
import client from 'prom-client';

const app = express();
app.use(express.json());

// ============ PROMETHEUS METRICS SETUP ============
client.collectDefaultMetrics();

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status']
});

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route'],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
});

const httpRequestsInFlight = new client.Gauge({
  name: 'http_requests_in_flight',
  help: 'Number of HTTP requests currently being processed'
});

const kafkaMessagesProcessed = new client.Counter({
  name: 'kafka_messages_processed_total',
  help: 'Total Kafka messages processed'
});

const kafkaMessageProcessingDuration = new client.Histogram({
  name: 'kafka_message_processing_seconds',
  help: 'Kafka message processing duration',
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5]
});

const kafkaMessagesInQueue = new client.Gauge({
  name: 'kafka_messages_in_queue',
  help: 'Number of Kafka messages currently being processed (work queue depth)'
});

// Metrics middleware (must be before routes)
app.use((req: Request, res: Response, next: NextFunction) => {
  if (req.path === '/metrics' || req.path === '/health') return next();
  
  httpRequestsInFlight.inc();
  const start = Date.now();
  
  res.on('finish', () => {
    httpRequestsInFlight.dec();
    const duration = (Date.now() - start) / 1000;
    const route = req.route?.path || req.path;
    httpRequestDuration.observe({ method: req.method, route }, duration);
    httpRequestsTotal.inc({ method: req.method, route, status: res.statusCode.toString() });
  });
  
  next();
});

// ============ CONFIG ============
const PORT = Number(process.env.PORT) || 3001;
const KAFKA_BROKER = process.env.KAFKA_BROKER || 'localhost:9092';
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/purchases';
const PURCHASE_TOPIC = process.env.PURCHASE_TOPIC || 'purchases';
const KAFKA_GROUP_ID = process.env.KAFKA_GROUP_ID || 'purchase-group';

// Purchase interface
interface IPurchase {
  username: string;
  userid: string;
  price: number;
  timestamp: Date;
}

// MongoDB schema
const purchaseSchema = new Schema<IPurchase>({
  username: { type: String, required: true, index: true },
  userid: { type: String, required: true, index: true },
  price: { type: Number, required: true },
  timestamp: { type: Date, required: true }
});

const Purchase = mongoose.model<IPurchase>('Purchase', purchaseSchema);

// Kafka consumer setup
const kafka = new Kafka({
  clientId: 'customer-management',
  brokers: [KAFKA_BROKER]
});
const consumer: Consumer = kafka.consumer({ groupId: KAFKA_GROUP_ID });

let kafkaReady = false;
let mongoReady = false;

// Connect to MongoDB
async function connectMongo(): Promise<void> {
  try {
    await mongoose.connect(MONGODB_URI);
    mongoReady = true;
    console.log('Connected to MongoDB');
  } catch (err) {
    mongoReady = false;
    console.error('Failed to connect to MongoDB:', err);
    setTimeout(connectMongo, 5000);
  }
}

// Connect to Kafka and consume messages
async function startKafkaConsumer(): Promise<void> {
  try {
    await consumer.connect();
    await consumer.subscribe({ topic: PURCHASE_TOPIC, fromBeginning: false });

    kafkaReady = true;
    console.log('Kafka consumer started');

    await consumer.run({
      eachMessage: async ({ message }) => {
        if (!message.value) return;

        kafkaMessagesInQueue.inc();
        const msgStart = Date.now();

        try {
          const purchase = JSON.parse(message.value.toString()) as IPurchase;
          const newPurchase = new Purchase(purchase);
          await newPurchase.save();
          console.log('Purchase saved to MongoDB');
          kafkaMessagesProcessed.inc();
        } catch (err) {
          console.error('Failed to process incoming purchase message:', err);
        } finally {
          kafkaMessagesInQueue.dec();
          kafkaMessageProcessingDuration.observe((Date.now() - msgStart) / 1000);
        }
      }
    });

  } catch (err) {
    kafkaReady = false;
    console.error('Failed to start Kafka consumer:', err);
    setTimeout(startKafkaConsumer, 5000);
  }
}

// ============ ROUTES ============

// GET /purchases/:userid - read purchases for a user
app.get('/purchases/:userid', async (req: Request, res: Response) => {
  try {
    const { userid } = req.params;
    const purchases = await Purchase.find({ userid }).sort({ timestamp: -1 });
    res.json(purchases);
  } catch (err) {
    console.error('Error fetching purchases:', err);
    res.status(500).json({ error: 'Failed to fetch purchases' });
  }
});

// GET /purchases - read all purchases
app.get('/purchases', async (_req: Request, res: Response) => {
  try {
    const purchases = await Purchase.find({}).sort({ timestamp: -1 }).limit(500);
    res.json(purchases);
  } catch (err) {
    console.error('Error fetching all purchases:', err);
    res.status(500).json({ error: 'Failed to fetch purchases' });
  }
});

// Health check
app.get('/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok', kafkaReady, mongoReady });
});

// Prometheus metrics endpoint
app.get('/metrics', async (_req: Request, res: Response) => {
  res.set('Content-Type', client.register.contentType);
  res.send(await client.register.metrics());
});

// ============ SERVER START ============
const server = app.listen(PORT, async () => {
  console.log(`Customer-management service running on port ${PORT}`);
  await connectMongo();
  await startKafkaConsumer();
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('Shutting down customer-management service');
  await consumer.disconnect().catch(() => {});
  await mongoose.disconnect().catch(() => {});
  server.close(() => process.exit(0));
});