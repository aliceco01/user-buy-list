# User Buy List

A Kubernetes based implementation of a simple purchase tracking system.

## Architecture diagram

![Architecture diagram](assets/buylist.drawio.png)

## Quick Start


The project is designed to run  with a single command using Minikube.


### Prerequisites

Before running, ensure you have installed:


1. Docker must be installed and running

2. Install minikube:

3. kubectl configured




### Deployment

One Command Deployment

```
./scripts/deploy.sh
```

This script automatically:

1. Starts minikube if not running (with 4GB RAM, 2 CPUs)
2. Installs KEDA for event-driven autoscaling
3. Deploys infrastructure (MongoDB, Kafka, Zookeeper, Prometheus)
4. Deploys application services
5. Configures autoscaling (HPA + KEDA ScaledObjects)
6. Opens the frontend in your browser


If the browser doesn't open automatically:

### Option 1: minikube service (recommended)

```
echo "Frontend is available at:"
minikube service user-buy-frontend --url 
```

### Option 2: Port forwarding
```
kubectl port-forward svc/user-buy-frontend 8080:80
Then open http://localhost:8080
```

### Tests 

To run the tests locally:
```
./scripts/test-all.sh
```

The tests assume the system is already running in Minikube and interact with the services via exposed endpoints. They are designed to be idempotent and safe to re-run during development.


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

The system uses a hybrid autoscaling approach.

HTTP-based services scale using HPA (Horizontal Pod Autoscaler) based on request-related metrics exposed via Prometheus. Kafka consumers scale using KEDA (Kubernetes Event-Driven Autoscaling) based on consumer lag.

This separation reflects real-world behavior. Kafka consumers often appear idle from a CPU perspective while still being overloaded due to message backlog, making CPU-based scaling misleading. At the same time, using KEDA for all workloads would add unnecessary operational complexity where HPA is sufficient.

### Observability

Services expose Prometheus metrics for request volume, latency, concurrency, and message processing behavior. These metrics are used both for visibility and for autoscaling decisions.

Metrics can be accessed via the Prometheus UI




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


or directly from the services’ /metrics endpoints.


### CICD

The pipeline is intentionally designed to avoid direct cluster access and to keep deployment state fully declarative and auditable in Git. 

Each pipeline run follows a deterministic flow, and application artifacts are built first, container images are published next, Kubernetes manifests are updated to reference immutable image digests, and the updated manifests are committed back to the repository.

For demo simplicity, I avoided anything that requires cluster credentials in CI (security overhead), and that has no audit trail. Additionally, it works with ArgoCD/Flux if added later.


 
Trade-offs:

- No Docker layer caching (builds are slower but simpler)
- Requires branch protection rules in production to prevent unauthorized commits


### Demo-related trade-offs

Several infrastructure choices favor clarity and reproducibility over optimization, which is intentional for a reviewer-facing assignment. 

For simplicity, MongoDB runs without authentication in this demo. In a real environment, credentials would be managed via Kubernetes Secrets, authentication would be enabled, and additional hardening would be applied.




#### Why Minikube

This repository is designed to run locally with a single command using Minikube, providing a consistent and predictable Kubernetes environment for reviewers.

All Kubernetes manifests are standard and cluster-agnostic. Minikube is used only to simplify local service access during the demo.

#### Operator-based approach

In this project, the operator pattern is used selectively, where it provides clear value, rather than applied uniformly. Core application services are deployed as standard Deployments, while supporting systems that benefit from ongoing reconciliation and understanding of runtime state are managed via operators. 

For a local demo, operator usage adds minimal overhead while allowing the same manifests and mental model to scale naturally to production environments. If this system were extended further, additional concerns such as backup orchestration, rolling upgrades, and failure recovery would be handled through the same operator reconciliation loop rather than bespoke automation. 

To run the project locally, use the operator-based deployment by simply executing ```./scripts/deploy-operator.sh.```

 The operator handles application setup automatically and no manual configuration is required - it will:

1. Starts Minikube and assumes a local control plane.

2. Builds a custom operator container image from operator/.

3. Loads that image directly into the Minikube node image cache.

4. Installs KEDA (an external operator).

5. Applies Kustomize (kubectl apply -k) manifests for your operator.

6. Patches the operator Deployment to use the locally built image.

7. Applies a sample Custom Resource (userbuyslist-sample.yaml) that the operator reconciles.

8. The operator is therefore responsible for deploying (some or all of) the application resources.