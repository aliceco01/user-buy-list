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

echo "Step 1: Installing KEDA (latest)..."
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/latest/download/keda.yaml

echo "Waiting for KEDA to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/keda-operator -n keda

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
kubectl apply -f k8s/ingress.yaml

echo ""
echo "=== Deployment Status ==="
kubectl get pods
echo ""
kubectl get hpa
echo ""
kubectl get scaledobjects

echo ""
echo "=== Deployment Complete ==="
echo "Access the application:"
echo "  kubectl port-forward svc/user-buy-frontend 8080:80"
echo "  Or via ingress:"
echo "    minikube tunnel"
echo "    Open http://localhost"
