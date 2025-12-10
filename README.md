# User Buy List

A simple buy-list system where a customer-facing service publishes purchases to Kafka, a customer-management service consumes and stores them in MongoDB, and a lightweight frontend triggers buys and lists a user's purchases.

## Components
- `services/customer-facing`: Express API that exposes `POST /buy` and `GET /getAllUserBuys/:userid`, publishes purchases to Kafka.
- `services/customer-management`: Express API that consumes Kafka messages, stores them in MongoDB, and exposes `GET /purchases/:userid`.
- `frontend`: Static UI (served via a tiny Express app) with Buy and getAllUserBuys buttons.
- `k8s`: Manifests for Kafka, MongoDB, both services, frontend, and HPAs (CPU/memory + Kafka lag as an external metric).
- `ci`: GitHub Actions builds/tests TypeScript and pushes images to GHCR.

## Prerequisites
- Kubernetes cluster + `kubectl`
- Container registry (GHCR by default) and Docker/BuildKit to build/push images
- (Optional) External metrics adapter for the Kafka consumer lag metric used by the customer-management HPA

## Build & Push Images (GHCR example)
```bash
REGISTRY=ghcr.io/<owner>/<repo>

# Customer-facing
cd services/customer-facing
yarn install
yarn build
docker build -t $REGISTRY/customer-facing:latest .
docker push $REGISTRY/customer-facing:latest

# Customer-management
cd ../customer-management
yarn install
yarn build
docker build -t $REGISTRY/customer-management:latest .
docker push $REGISTRY/customer-management:latest

# Frontend
cd ../../frontend
yarn install
docker build -t $REGISTRY/user-buy-frontend:latest .
docker push $REGISTRY/user-buy-frontend:latest

# Update image references in k8s manifests to match $REGISTRY paths.
```

## Deploy to Kubernetes
Apply infra first, then services and autoscaling:
```bash
kubectl apply -f k8s/kafka.yaml
kubectl apply -f k8s/mongodb.yaml
kubectl apply -f k8s/kafka-exporter.yaml   # exposes Kafka lag metrics
kubectl apply -f k8s/customer-managment.yaml
kubectl apply -f k8s/customer-facing.yaml
kubectl apply -f k8s/frontend.yaml
kubectl apply -f k8s/autoscaling.yaml
``` 

Port-forward to try the UI:
```bash
kubectl port-forward svc/user-buy-frontend 8080:80
# Frontend calls the customer-facing service inside the cluster.
```

### Environment Variables
- Customer-facing: `PORT` (default 3000), `KAFKA_BROKER` (default `localhost:9092`), `CUSTOMER_MANAGEMENT_URL`, `PURCHASE_TOPIC` (default `purchases`)
- Customer-management: `PORT` (3001), `KAFKA_BROKER`, `MONGODB_URI`, `PURCHASE_TOPIC`, `KAFKA_GROUP_ID`
- Frontend: `PORT` (8080), `API_BASE` (base URL to customer-facing)

### Autoscaling
- `k8s/autoscaling.yaml`:
  - Customer-facing: CPU + memory utilization
  - Customer-management: **Kafka consumer lag only** via external metric `kafka_consumer_group_lag` (topic `purchases`, group `purchase-group`; requires metrics adapter such as Prometheus Adapter scraping from `kafka-exporter`)
  - Frontend: CPU
- Intentional scope stop: Prometheus/Adapter manifests are not included; assume an existing metrics stack exposes `kafka_consumer_group_lag` to the HPA.
Kafka consumer lag is used as the scaling signal for customer-management. In a real cluster this metric would typically be surfaced via a Kafka exporter and consumed through an existing metrics pipeline (for example via a custom metrics adapter or KEDA). For this assignment, the HPA demonstrates the correct scaling semantics without deploying shared observability infrastructure.

## Endpoints
- Customer-facing: `POST /buy`, `GET /getAllUserBuys/:userid`, `GET /health`
- Customer-management: `GET /purchases/:userid`, `POST /purchases` (direct write, useful for tests), `GET /health`
- Frontend: `GET /` UI; uses `/buy` and `/getAllUserBuys/:userid` calls to the customer-facing service

## CI/CD
- `.github/workflows/ci.yaml` runs `yarn test` (TypeScript checks) and builds/pushes images for customer-facing, customer-management, and frontend to GHCR (`ghcr.io/<owner>/<repo>`).
