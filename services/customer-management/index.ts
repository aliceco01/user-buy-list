import express, { Request, Response } from 'express';
import { Kafka, Consumer } from 'kafkajs';
import mongoose from 'mongoose';

const app = express();
app.use(express.json());

// Config
const PORT: number = Number(process.env.PORT) || 3001;
const KAFKA_BROKER: string = process.env.KAFKA_BROKER || 'localhost:9092';
const MONGODB_URI: string = process.env.MONGODB_URI || 'mongodb://localhost:27017/purchases';

// Purchase interface
interface IPurchase {
  username: string;
  userid: string;
  price: number;
  timestamp: Date;
}

// MongoDB schema
const purchaseSchema = new mongoose.Schema<IPurchase>({
  username: String,
  userid: String,
  price: Number,
  timestamp: Date
});
const Purchase = mongoose.model<IPurchase>('Purchase', purchaseSchema);

// Kafka consumer setup
const kafka = new Kafka({
  clientId: 'customer-management',
  brokers: [KAFKA_BROKER]
});
const consumer: Consumer = kafka.consumer({ groupId: 'purchase-group' });

// Connect to MongoDB
async function connectMongo(): Promise<void> {
  try {
    await mongoose.connect(MONGODB_URI);
    console.log('Connected to MongoDB');
  } catch (err) {
    console.error('Failed to connect to MongoDB:', err);
    setTimeout(connectMongo, 5000);
  }
}

// Connect to Kafka and consume messages
async function startKafkaConsumer(): Promise<void> {
  try {
    await consumer.connect();
    await consumer.subscribe({ topic: 'purchases', fromBeginning: true });

    await consumer.run({
      eachMessage: async ({ message }) => {
        if (message.value) {
          const purchase = JSON.parse(message.value.toString());
          console.log('Received purchase:', purchase);

          const newPurchase = new Purchase(purchase);
          await newPurchase.save();
          console.log('Purchase saved to MongoDB');
        }
      }
    });

    console.log('Kafka consumer started');
  } catch (err) {
    console.error('Failed to start Kafka consumer:', err);
    setTimeout(startKafkaConsumer, 5000);
  }
}

// GET /purchases/:userid
app.get('/purchases/:userid', async (req: Request, res: Response) => {
  try {
    const { userid } = req.params;
    const purchases = await Purchase.find({ userid });
    res.json(purchases);
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
  console.log(`Customer-management service running on port ${PORT}`);
  await connectMongo();
  await startKafkaConsumer();
});