# User Buy List

A Kubernetes based implementation of a simple purchase tracking system with event-driven architecture, advanced autoscaling, full observability, and CI/CD.

## Architecture diagram

![Architecture diagram](assets/buylist.drawio.png)

## Quick Start

### Prerequisites

Before running, ensure you have installed:

####
1. Docker must be installed and running

2. Install minikube:

3. kubectl configured

###  Note about minikube 

The deployment script requires and manages Minikube. 

Minikube installs in 5 minutes and runs alongside other tools without conflict.

For the sake of a streamlined, one-click demo experience, the provided deploy.sh script is optimized specifically for its minikube service tunnel capabilities and Docker driver handling. If you are running on non-Minikube Clusters,the Kubernetes manifests in k8s directory are standard and cloud-agnostic. 

If you prefer to use a different cluster, a manual configuration of the k8s files in possible.



### Deployment

One Command Deployment

```bash
./scripts/deploy.sh
```

This script automatically:

1. Starts minikube if not running (with 4GB RAM, 2 CPUs)
2. Installs KEDA for event-driven autoscaling
3. Deploys infrastructure (MongoDB, Kafka, Zookeeper, Prometheus)
4. Deploys application services
5. Configures autoscaling (HPA + KEDA ScaledObjects)
6. Opens the frontend in your browser


## Manual Access

If the browser doesn't open automatically:

### Option 1: minikube service (recommended)

echo "Frontend is available at:"
minikube service user-buy-frontend --url 

### Option 2: Port forwarding
```
kubectl port-forward svc/user-buy-frontend 8080:80
Then open http://localhost:8080
```


### Cleanup

```bash
./scripts/cleanup.sh
```

### Design Decisions 

This project implements a purchase tracking system with the following data flow:
- User submits purchase -> Frontend sends request to customer-facing API
- Event published -> customer-facing produces message to Kafka
- Event consumed -> customer-management consumes from Kafka, persists to MongoDB
- User queries purchases -> customer-facing fetches from customer-management API



#### Production / real-life Considerations:


This demo makes tradeoffs for simplicity.
Some of the trade-offs and how this system should behave in non-demo envs. 



### Autoscaling Strategy

Hybrid Approach:

Use HPA for HTTP services, KEDA for Kafka consumers
**Why not just HPA for everything?**
- Display range of experience with autoscailing strategies 
- HPA scales on CPU/memory or custom metrics
- Kafka consumer lag isn't a metric HPA understands natively
- CPU-based scaling for consumers is misleading (idle consumer waiting for messages = low CPU, but might have huge backlog)

**Why not just KEDA for everything?**
- KEDA adds complexity (another operator to install)
- HPA is built-in, well-understood, sufficient for HTTP workloads
- customer-facing already exposes Prometheus metrics that HPA can use via Prometheus Adapter


## Prometheus Metrics

- http_requests_total - Request volume
- http_request_duration_seconds - Latency percentiles
- http_requests_in_flight - Concurrency (HPA trigger)
- kafka_producer_messages_total - producer throughput
- kafka_messages_processed_total - Consumer throughput
- kafka_message_processing_seconds - Processing latency


### Accessing Metrics

1. Prometheus UI:

```
kubectl port-forward svc/prometheus 9090:9090
# Open http://localhost:9090
```

2. Raw metrics from services
```
kubectl port-forward svc/customer-facing 3000:80
curl http://localhost:3000/metrics

```


## CICD

The pipeline is intentionally designed to avoid direct cluster access and to keep deployment state fully declarative and auditable in Git. 

Each pipeline run follows a deterministic flow, and application artifacts are built first, container images are published next, Kubernetes manifests are updated to reference immutable image digests, and the updated manifests are committed back to the repository.

For demo simplicity, I avoided anything that requires cluster credentials in CI (security overhead), and that has no audit trail. Additionally, it works with ArgoCD/Flux if added later.

```

┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    Build    │───►│    Push     │───►│   Update    │───►│   Commit    │
│  TypeScript │    │  to GHCR    │    │  Manifests  │    │   to Repo   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘

```
 
**Trade-offs acknowledged:**

- No Docker layer caching (builds are slower but simpler)
- Requires branch protection rules in production to prevent unauthorized commits


### MongoDB Without Authentication and security considerations 

 MongoDB runs without auth in this demo.  This was intentionally done for the following reasons:
- simplify setup for reviewers.
- Focus on Kubernetes patterns, not MongoDB ops
- In non-demo enviornemnts, I would at least use secrets for credentials, and enable auth.


