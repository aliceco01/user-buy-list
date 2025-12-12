#!/bin/bash
set -e

echo "=== Deploying User Buy List System ==="
echo ""

if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "Step 1: Installing KEDA (v2.15.1)..."
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.15.1/keda-2.15.1.yaml

echo "Waiting for KEDA to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/keda-operator -n keda || true

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
minikube service user-buy-frontend