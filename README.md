# User Buy List

![Architecture diagram](assets/buylist.drawio.png)

## Quick Start

### Option 1: Automated Deployment

```bash
./scripts/deploy.sh
```

### Option 2: Manual Step-by-Step

1. **Create a local Kubernetes cluster:**
   ```bash
   kind create cluster --name user-buy-cluster
   # or
   minikube start
   ```

2. **Install KEDA:**
   ```bash
   kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.12.1/keda-2.12.1.yaml
   kubectl wait --for=condition=available --timeout=300s deployment/keda-operator -n keda
   ```

3. **Apply all manifests:**
   ```bash
   cd k8s
   kubectl apply -f .
   ```

4. **Access the frontend:**
   ```bash
   kubectl port-forward svc/user-buy-frontend 8080:80
   ```
   Open http://localhost:8080