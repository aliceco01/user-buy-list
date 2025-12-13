# User Buy List

A Kubernetes based implementation of a simple purchase tracking system with event-driven architecture, advanced autoscaling, full observability, and CI/CD.

## Architecture diagram

![Architecture diagram](assets/buylist.drawio.png)

## Quick Start

### Prerequisites

Before running, ensure you have installed:

####
1. Docker must be installed and running


**
macOS:
**

```
bash

brew 
install
 --cask 
docker

# Then launch Docker Desktop from Applications

```

**
Ubuntu/Debian:
**

```
bash

sudo
 
apt-get
 update
sudo
 
apt-get
 
install
 docker.io
sudo
 systemctl start 
docker

sudo
 
usermod
 -aG 
docker
 
$USER
  
# Log out and back in after this

```

**
Windows:
**

Download and install 
[
Docker Desktop
](
https://www.docker.com/products/docker-desktop/
)

**
Verify installation:
**

```
bash

docker
 --version
docker
 info  
# Should show server info, not connection error

```


####
 2. Install minikube

**
macOS:
**

```
bash

brew 
install
 minikube

```

**
Ubuntu/Debian:
**

```
bash

curl
 -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo
 
install
 minikube-linux-amd64 /usr/local/bin/minikube

```


**
Windows (PowerShell as Admin):
**

```
powershell

choco install minikube
# Or download from https://minikube.sigs.k8s.io/docs/start/

```

**
Verify installation:
**

```
bash

minikube version

```


3. kubectl configured


**
macOS:
**

```
bash

brew 
install
 kubectl

```


**
Ubuntu/Debian:
**

```
bash

curl
 -LO 
"https://dl.k8s.io/release/
$(
curl
 -L -s https://dl.k8s.io/release/stable.txt
)
/bin/linux/amd64/kubectl"

sudo
 
install
 kubectl /usr/local/bin/kubectl

```


**
Windows:
**

```
powershell

choco install kubernetes-
cli

```


**
Verify installation:
**

```
bash

kubectl version --client

```


---

### Deployment

One Command Deployment:

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


###
 Manual Access


If the browser doesn't open automatically:
```
bash

# Option 1: minikube service (recommended)

minikube 
service
 user-buy-frontend
# Option 2: Port forwarding

kubectl port-forward svc/user-buy-frontend 
8080
:80
# Then open http://localhost:8080


### Cleanup

```bash
./scripts/cleanup.sh
```


## Design Decisions 

## Overview

This project implements a purchase tracking system with the following data flow:
- User submits purchase -> Frontend sends request to customer-facing API
- Event published -> customer-facing produces message to Kafka
- Event consumed -> customer-management consumes from Kafka, persists to MongoDB
- User queries purchases -> customer-facing fetches from customer-management API


## CICD

The pipeline is intentionally designed to avoid direct cluster access and to keep deployment state fully declarative and auditable in Git. 
Each pipeline run follows a deterministic flow. Application artifacts are built first, container images are published next, Kubernetes manifests are updated to reference immutable image digests, and the updated manifests are committed back to the repository.

```

┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    Build    │───►│    Push     │───►│   Update    │───►│   Commit    │
│  TypeScript │    │  to GHCR    │    │  Manifests  │    │   to Repo   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘

```



**Trade-offs acknowledged:**

- No Docker layer caching (builds are slower but simpler)
- Requires branch protection rules in production to prevent unauthorized commits



## Security Considerations


### MongoDB Without Authentication

 MongoDB runs without auth in this demo.  This was intentionally done for the following reasons:
- simplify setup for reviewers.
- Focus on Kubernetes patterns, not MongoDB ops
- In non-demo enviornemnts, I would at least use secrets for credentials, and enable auth.

### Single-Replica Stateful Services