#!/bin/bash

echo "=== Cleaning up User Buy List System ==="

kubectl delete -f k8s/ --ignore-not-found

echo "Deleting KEDA..."
kubectl delete -f https://github.com/kedacore/keda/releases/download/v2.15.1/keda-2.15.1.yaml --ignore-not-found

echo ""
echo "=== Cleanup Complete ==="
