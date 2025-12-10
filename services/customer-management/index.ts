import express, { Request, Response } from 'express';
import { Kafka, Consumer } from 'kafkajs';
import mongoose, { Schema } from 'mongoose';

const app = express();
app.use(express.json());

// Config
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
    await consumer.subscribe({ topic: PURCHASE_TOPIC, fromBeginning: true });

    await consumer.run({
      eachMessage: async ({ message }) => {
        if (!message.value) return;

        try {
          const purchase = JSON.parse(message.value.toString()) as IPurchase;
          const newPurchase = new Purchase(purchase);
          await newPurchase.save();
          console.log('Purchase saved to MongoDB');
        } catch (err) {
          console.error('Failed to process incoming purchase message:', err);
        }
      }
    });

    kafkaReady = true;
    console.log('Kafka consumer started');
  } catch (err) {
    kafkaReady = false;
    console.error('Failed to start Kafka consumer:', err);
    setTimeout(startKafkaConsumer, 5000);
  }
}

// POST /purchases - direct write (useful for tests)
app.post('/purchases', async (req: Request, res: Response) => {
  try {
    const { username, userid, price, timestamp } = req.body;

    if (!username || !userid || price === undefined) {
      return res.status(400).json({ error: 'Missing required fields: username, userid, price' });
    }

    const parsedPrice = Number(price);
    if (Number.isNaN(parsedPrice) || parsedPrice <= 0) {
      return res.status(400).json({ error: 'Price must be a positive number' });
    }

    const purchase = new Purchase({
      username,
      userid,
      price: parsedPrice,
      timestamp: timestamp ? new Date(timestamp) : new Date()
    });

    await purchase.save();
    res.status(201).json(purchase);
  } catch (err) {
    console.error('Error writing purchase:', err);
    res.status(500).json({ error: 'Failed to write purchase' });
  }
});

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

// Start server
const server = app.listen(PORT, async () => {
  console.log(`Customer-management service running on port ${PORT}`);
  await connectMongo();
  await startKafkaConsumer();
});

process.on('SIGTERM', async () => {
  console.log('Shutting down customer-management service');
  await consumer.disconnect().catch(() => {});
  await mongoose.disconnect().catch(() => {});
  server.close(() => process.exit(0));
});
