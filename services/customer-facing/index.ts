// handle customer purchases, send to Kafka, fetch from customer-management

import axios from 'axios';
import cors from 'cors';
import express, { Request, Response } from 'express';
import { Kafka, Producer } from 'kafkajs';

const app = express();
app.use(express.json());
app.use(cors());

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

// POST /buy
app.post('/buy', async (req: Request, res: Response) => {
  try {
    const { username, userid, price } = req.body;

    if (!username || !userid || price === undefined) {
      return res.status(400).json({ error: 'Missing required fields: username, userid, price' });
    }

    const parsedPrice = Number(price);
    if (Number.isNaN(parsedPrice) || parsedPrice <= 0) {
      return res.status(400).json({ error: 'Price must be a positive number' });
    }

    // Creation of  purchase object in Kafka message
    const purchase: Purchase = {
      username,
      userid,
      price: parsedPrice,
      timestamp: new Date().toISOString()
    };
// Send purchase message to Kafka
    await producer.send({
      topic: PURCHASE_TOPIC,
      messages: [{ value: JSON.stringify(purchase) }]
    });

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
    const response = await axios.get(`${CUSTOMER_MANAGEMENT_URL}/purchases/${userid}`);
    res.json(response.data);
  } catch (err) {
    console.error('Error fetching purchases:', err);
    res.status(500).json({ error: 'Failed to fetch purchases' });
  }
});

// Health check endpoint for Kafka connection
app.get('/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok', kafkaReady });
});

// Start server
const server = app.listen(PORT, async () => {
  console.log(`Customer-facing service running on port ${PORT}`);
  await connectKafka();
});

process.on('SIGTERM', async () => {
  console.log('Shutting down customer-facing service');
  await producer.disconnect().catch(() => {});
  server.close(() => process.exit(0));
});
