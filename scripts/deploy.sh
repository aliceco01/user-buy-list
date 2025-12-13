#!/bin/bash
set -e

echo "=== Deploying User Buy List System ==="
echo ""

# Check if Docker is installed and running
if ! docker info &> /dev/null; then
    echo "Error: Docker is not running"
    echo "Please start Docker Desktop and try again"
    exit 1
fi

# Check if  minikube is installed
if ! command -v minikube &> /dev/null; then
    echo "Error: minikube is not installed"
    echo "Install: https://minikube.sigs.k8s.io/docs/start/"
    exit 1
fi

# Start minikube if not running
if ! minikube status 2>&1 | grep -q "Running"; then
    echo "Starting minikube..."
    minikube start --memory=4096 --cpus=2
fi

# Check if kubectl is installed and can connect to cluster
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed"
    exit 1
fi

# Verify connection to Kubernetes cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

# Deploy KEDA and infrastructure
echo "Step 1: Installing KEDA (v2.15.1)..."
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.15.1/keda-2.15.1.yaml

echo "Waiting for KEDA to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/keda-operator -n keda || true

# Deploy infrastructure and applications
echo ""
echo "Step 2: Applying infrastructure..."
kubectl apply -f k8s/config.yaml
kubectl apply -f k8s/mongodb.yaml
kubectl apply -f k8s/kafka.yaml
kubectl apply -f k8s/prometheus.yaml
kubectl apply -f k8s/prometheus-adapter.yaml
kubectl apply -f k8s/kafka-exporter.yaml

echo "Waiting for infrastructure..."
kubectl wait --for=condition=ready pod -l app=mongodb --timeout=180s
kubectl wait --for=condition=ready pod -l app=kafka --timeout=180s

# Deploy services and frontend
echo ""
echo "Step 3: Applying applications..."
kubectl apply -f k8s/customer-management.yaml
kubectl apply -f k8s/customer-facing.yaml
kubectl apply -f k8s/frontend.yaml
kubectl apply -f k8s/pdb.yaml
kubectl apply -f k8s/autoscaling.yaml

echo ""
echo "=== Deployment Status ==="
kubectl get pods
echo ""
kubectl get hpa
echo ""
kubectl get scaledobjects

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Waiting for frontend to be ready..."
kubectl wait --for=condition=ready pod -l app=user-buy-frontend --timeout=120s

echo ""
echo "Opening frontend in browser..."
#create a tunnel to the the service and open in browser
minikube service user-buy-frontend
