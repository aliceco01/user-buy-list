// handle customer purchases, send to Kafka, fetch from customer-management
// exports Prometheus metrics and health check via Express server (rest API)

import axios from 'axios';
import cors from 'cors';
import express, { Request, Response, NextFunction } from 'express';
import { Kafka, Producer } from 'kafkajs';
import client from 'prom-client';

const app = express();
app.use(express.json());
app.use(cors());

// Prometheus metrics setup
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

const kafkaProducerMessages = new client.Counter({
  name: 'kafka_producer_messages_total',
  help: 'Total messages sent to Kafka'
});

// kafka and service config 
const PORT = Number(process.env.PORT) || 3000;
const KAFKA_BROKER = process.env.KAFKA_BROKER || 'localhost:9092';
const CUSTOMER_MANAGEMENT_URL = process.env.CUSTOMER_MANAGEMENT_URL || 'http://localhost:3001';
const PURCHASE_TOPIC = process.env.PURCHASE_TOPIC || 'purchases';

// Purchase interface for sending to Kafka
interface Purchase {
  username: string;
  userid: string;
  price: number;
  timestamp: string;
}

// Kafka producer setup 
const kafka = new Kafka({
  clientId: 'customer-facing',
  brokers: [KAFKA_BROKER]
});
const producer: Producer = kafka.producer();
let kafkaReady = false;

// Connect to Kafka with retry
async function connectKafka(): Promise<void> {
  try {
    await producer.connect();
    kafkaReady = true;
    console.log('Connected to Kafka');
  } catch (err) {
    kafkaReady = false;
    console.error('Failed to connect to Kafka:', err);
    setTimeout(connectKafka, 5000);
  }
}

// Metrics middleware
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

// POST /buy - receives purchase from frontend, validates input, sends to Kafka
// Implements customer-facing REST API + Kafka producer 
app.post('/buy', async (req: Request, res: Response) => {
  try {
    const { username, userid, price } = req.body;

    if (!username || !userid || price === undefined) {
      return res.status(400).json({ error: 'Missing required fields: username, userid, price' });
    }
// Validate price - can't be negative or zero
    const parsedPrice = Number(price);
    if (Number.isNaN(parsedPrice) || parsedPrice <= 0) {
      return res.status(400).json({ error: 'Price must be a positive number' });
    }
// Create purchase object
    const purchase: Purchase = {
      username,
      userid,
      price: parsedPrice,
      timestamp: new Date().toISOString()
    };

    // Send purchase to Kafka asynchronously, using userid as the key for partitioning
    // NOTE: The Kafka topic should be created with multiple partitions to ensure key-based partitioning works.
    await producer.send({
      topic: PURCHASE_TOPIC,
      messages: [{
        key: userid, // ensures all purchases for a user go to the same partition
        value: JSON.stringify(purchase)
      }]
    });

    // Increment Kafka messages metric
    kafkaProducerMessages.inc();
    res.status(201).json({ message: 'Purchase recorded', purchase });
  } catch (err) {
    console.error('Error processing purchase:', err);
    res.status(500).json({ error: 'Failed to process purchase' });
  }
});

// GET /getAllUserBuys/:userid
app.get('/getAllUserBuys/:userid', async (req: Request, res: Response) => {
  try {
    const { userid } = req.params;
    const response = await axios.get(`${CUSTOMER_MANAGEMENT_URL}/purchases/${userid}`, {
      timeout: 5000 // 5 second timeout to prevent hanging
    });
    res.json(response.data);
  } catch (err) {
    console.error('Error fetching purchases:', err);
    res.status(500).json({ error: 'Failed to fetch purchases' });
  }
});


// Liveness probe: returns 200 if process is alive (no dependency checks)
app.get('/health', (_req: Request, res: Response) => {
  res.status(200).json({ status: 'alive' });
});

// Readiness probe: returns 200 only if Kafka is connected
app.get('/ready', (_req: Request, res: Response) => {
  if (kafkaReady) {
    res.status(200).json({ status: 'ready', kafkaReady: true });
  } else {
    res.status(503).json({ status: 'not ready', kafkaReady: false });
  }
});


// Prometheus metrics endpoint
app.get('/metrics', async (_req: Request, res: Response) => {
  res.set('Content-Type', client.register.contentType);
  res.send(await client.register.metrics());
});

// Start server and connect to Kafka
const server = app.listen(PORT, async () => {
  console.log(`Customer-facing service running on port ${PORT}`);
  await connectKafka();
});

// Graceful shutdown of Kafka producer
process.on('SIGTERM', async () => {
  console.log('Shutting down customer-facing service');
  await producer.disconnect().catch(() => {});
  server.close(() => process.exit(0));
});