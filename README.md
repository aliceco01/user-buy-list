# User Buy List

A microservices system for users to buy random items and retrieve their purchase history.

## Architecture

- **customer-facing** - REST API that receives purchases and sends them to Kafka
- **customer-management** - Consumes from Kafka and stores purchases in MongoDB
- **frontend** - Web UI to buy items and view purchase history
- **Prometheus + Adapter** - Collects metrics and exposes them for autoscaling

![Architecture diagram](assets/buylist.drawio.png)

## Autoscaling Metrics

### customer-facing
- CPU, memory
- HTTP RPS
- In-flight requests

### customer-management
- CPU, memory
- Kafka consumer lag
- Work queue depth

## Prerequisites

## System Requirements
- Minikube: 2+ CPUs, 4GB RAM
- Kubernetes 1.19+
- Docker 20.10+
- Ports 3000, 3001, 8080, 9090 available

1. clone the repo
```bash
git clone https://github.com/aliceco01/user-buy-list.git
cd user-buy-list
```
2. Docker installed
 - Container runtime  
   Install: https://docs.docker.com/get-docker/

3. minikube installed 
 - Runs a local Kubernetes cluster on your machine  
   Install: https://minikube.sigs.k8s.io/docs/start/
4. kubectl
- CLI for interacting with Kubernetes  
   Install: https://kubernetes.io/docs/tasks/tools/


## Deploy to Minikube

```bash
# Start minikube
minikube start

# Enable metrics-server
minikube addons enable metrics-server

# Deploy all components
kubectl apply -f k8s/

# Wait for pods to be ready
kubectl get pods -w
```

## Verify Deployment

Check that all pods are running:

```bash
kubectl get pods
```

Expected pods:
- customer-facing (2 replicas)
- customer-management (2 replicas)
- kafka
- zookeeper
- mongodb
- prometheus
- prometheus-adapter
- kafka-exporter
- user-buy-frontend

## Test the Application

```bash
# Port-forward frontend
kubectl port-forward svc/user-buy-frontend 8080:80
```

Open http://localhost:8080

1. **Buy**: Enter username, userid, price, then click Buy
2. **Get All Buys**: Enter userid, then click getAllUserBuys

## Test Metrics

```bash
# Check Prometheus targets
kubectl port-forward svc/prometheus 9090:9090
```

Open http://localhost:9090/targets - all targets should be UP.

## API Endpoints

### customer-facing (port 3000)

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/buy` | Submit a purchase |
| GET | `/getAllUserBuys/:userid` | Get all purchases for a user |
| GET | `/health` | Health check |
| GET | `/metrics` | Prometheus metrics |

### customer-management (port 3001)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/purchases/:userid` | Get purchases by user ID |
| GET | `/purchases` | Get all purchases (limit 500) |
| GET | `/health` | Health check |
| GET | `/metrics` | Prometheus metrics |

## CI/CD

The GitHub Actions workflow builds and pushes Docker images to GitHub Container Registry on pushes to `main`. Each service is built, type-checked, and containerized independently.

## Testing

### Comprehensive Test Suite

Run all tests to validate the entire system end-to-end:

```bash
./scripts/test-all.sh
```

This script:
- ✓ Verifies all pods are running and ready
- ✓ Tests health check endpoints
- ✓ Tests POST /buy endpoint
- ✓ Tests GET /getAllUserBuys endpoint
- ✓ Verifies data persistence (REST → Kafka → MongoDB flow)
- ✓ Validates Prometheus metrics collection
- ✓ Checks all metric targets are scraping
- ✓ Tests frontend accessibility
- ✓ Runs end-to-end smoke test
- ✓ Generates test summary report

**Expected Output:** All tests passing with summary statistics

### Quick Smoke Test

For a quick validation, run just the smoke test:

```bash
API_BASE=http://localhost:3000 ./scripts/smoke.sh
```

## Cleanup

```bash
kubectl delete -f k8s/
minikube stop
```