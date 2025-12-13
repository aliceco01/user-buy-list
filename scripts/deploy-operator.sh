#!/bin/bash
set -e

echo "=== UserBuyList Operator Deployment ==="

# Check minikube
if ! minikube status | grep -q "Running"; then
    echo "Starting minikube..."
    minikube start --memory=4096 --cpus=2
fi

# Install KEDA (required for autoscaling)
echo "Installing KEDA..."
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.15.1/keda-2.15.1.yaml
kubectl wait --for=condition=available --timeout=120s deployment/keda-operator -n keda || true

# Install operator
echo "Installing UserBuyList operator..."
kubectl apply -k operator/manifests/

# Wait for operator
echo "Waiting for operator..."
kubectl wait --for=condition=available --timeout=60s deployment/userbuylist-operator

# Deploy the app
echo "Deploying application..."
kubectl apply -f deploy/userbuyslist-sample.yaml

# Wait for pods
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=user-buy-frontend --timeout=180s

echo ""
echo "=== Deployment complete ==="
echo ""
echo "Access the application:"
echo "  kubectl port-forward svc/user-buy-frontend 8080:80"
echo "  Then open: http://localhost:8080"
echo ""
echo "Or use minikube service:"
echo "  minikube service user-buy-frontend"
echo ""

# Automatically set up port-forward in background
echo "Setting up port-forward to frontend..."
kubectl port-forward svc/user-buy-frontend 8080:80 > /dev/null 2>&1 &
PORT_FORWARD_PID=$!
echo "Port-forward started (PID: $PORT_FORWARD_PID)"
echo ""

# Wait a moment for port-forward to establish
sleep 2

# Open browser
echo "Opening browser..."
if command -v open &> /dev/null; then
    open http://localhost:8080
elif command -v xdg-open &> /dev/null; then
    xdg-open http://localhost:8080
else
    echo "Please manually open: http://localhost:8080"
fi

echo ""
echo "To stop port-forward: kill $PORT_FORWARD_PID"
