# User Buy List

A simple system for a user to buy random items and get a list of all the items that he bought


![Architecture diagram](assets/buylist.drawio.png)






## Components
- `services/customer-facing`: Express API exposing `POST /buy`, `GET /getAllUserBuys/:userid`, publishes to Kafka.
- `services/customer-management`: Express API consuming Kafka, storing to MongoDB, exposing `GET /purchases/:userid`.
- `frontend`: Static UI served by a tiny Express app; calls the customer-facing API.
- `k8s`: Kafka, MongoDB, both services, frontend, HPAs (CPU/memory + Kafka lag), optional KEDA ScaledObject.
- `ci`: GitHub Actions builds/tests TypeScript and pushes images to GHCR.

## Prerequisites
- Kubernetes cluster + `kubectl`
- Container registry (GHCR by default) and Docker/BuildKit to build/push images
- Yarn v1 installed (`corepack enable && corepack prepare yarn@1.22.x --activate`) or install via your package manager; stick with Yarn to avoid lockfile churn
- (Optional) External metrics adapter for Kafka consumer lag metric if you use the HPA’s External metric (or install KEDA and use the provided ScaledObject)

## Build & push images (GHCR example)
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
Apply config/infra, then services and autoscaling:
```bash
kubectl apply -f k8s/config.yaml
kubectl apply -f k8s/pdb.yaml
kubectl apply -f k8s/kafka.yaml
kubectl apply -f k8s/mongodb.yaml
kubectl apply -f k8s/kafka-exporter.yaml   # exposes Kafka lag metrics
kubectl apply -f k8s/customer-managment.yaml
kubectl apply -f k8s/customer-facing.yaml
kubectl apply -f k8s/frontend.yaml
kubectl apply -f k8s/autoscaling.yaml
# Optional: kubectl apply -f k8s/keda-customer-management.yaml  # requires KEDA installed
``` 

Port-forward to try the UI:
```bash
kubectl port-forward svc/user-buy-frontend 8080:80
# Frontend calls the customer-facing service inside the cluster.
```

### Runtime configuration
- ConfigMaps: `k8s/config.yaml` holds non-secret env for each component.
- Secret: `customer-management-secret` holds `MONGODB_URI`.
- Persistence: `k8s/mongodb.yaml` uses a PVC (`mongo-data-pvc`, 10Gi, RWO).
- Resilience/Safety: `k8s/pdb.yaml` adds PodDisruptionBudgets; deployments run non-root with read-only root FS where possible.

Environment variables (for reference):
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

If you prefer KEDA, a sample ScaledObject is in `k8s/keda-customer-management.yaml` (requires KEDA CRDs installed).

### Observability (future)
- Kafka lag metric is already exposed via `kafka-exporter`. Hook it into Prometheus/Prometheus Adapter (or KEDA) for production-grade scaling.
- Add Prometheus/Grafana/Alertmanager to scrape service health endpoints and Kafka exporter if your cluster doesn’t already provide it.

### Smoke test
After port-forwarding the customer-facing service (or frontend), run:
```bash
API_BASE=http://localhost:3000 ./scripts/smoke.sh
```
## CI/CD

GitHub Actions workflow (`.github/workflows/ci.yaml`) automatically:
- Runs TypeScript type checking
- Builds container images for all services
- Pushes images to GitHub Container Registry

## Troubleshooting

### Pods not starting
- Check pod logs: `kubectl logs <pod-name>`
- Verify ConfigMaps/Secrets exist: `kubectl get configmaps,secrets`
- Ensure PVC is bound: `kubectl get pvc`

### Kafka connection issues
- Verify Kafka pod is running: `kubectl get pods -l app=kafka`
- Check service endpoints: `kubectl get endpoints kafka`

### MongoDB connection issues
- Verify MongoDB pod is running: `kubectl get pods -l app=mongodb`
- Check MongoDB logs: `kubectl logs -l app=mongodb`



