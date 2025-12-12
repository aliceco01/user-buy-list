# User Buy List

A Kubernetes-based implementation of a simple purchase tracking system with event-driven architecture, advanced autoscaling, full observability, and CI/CD.

## Architecture diagram

![Architecture diagram](assets/buylist.drawio.png)

## Quick Start

### Prerequisites
- Kubernetes cluster (minikube or kind)
- kubectl configured

### Deployment

```bash
./scripts/deploy.sh
```

This script will:
- Install KEDA v2.15.1
- Deploy infrastructure (MongoDB, Kafka, Prometheus)
- Deploy applications (customer-facing, customer-management, frontend)
- Open the frontend in your browser

### Access Services

The frontend will open automatically, or manually access:
```bash
kubectl port-forward svc/user-buy-frontend 8080:80
```
Then open http://localhost:8080

### Cleanup

```bash
./scripts/cleanup.sh
```