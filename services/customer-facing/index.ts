import express, { Request, Response } from 'express';
import { Kafka, Producer } from 'kafkajs';
import axios from 'axios';

const app = express();
app.use(express.json());

// Config
const PORT: number = Number(process.env.PORT) || 3000;
const KAFKA_BROKER: string = process.env.KAFKA_BROKER || 'localhost:9092';
const CUSTOMER_MANAGEMENT_URL: string = process.env.CUSTOMER_MANAGEMENT_URL || 'http://localhost:3001';

// Purchase interface
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

// Connect to Kafka
async function connectKafka(): Promise<void> {
  try {
    await producer.connect();
    console.log('Connected to Kafka');
  } catch (err) {
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

    const purchase: Purchase = {
      username,
      userid,
      price,
      timestamp: new Date().toISOString()
    };

    await producer.send({
      topic: 'purchases',
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

// Health check
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok' });
});

// Start server
app.listen(PORT, async () => {
  console.log(`Customer-facing service running on port ${PORT}`);
  await connectKafka();
});