# User Buy List

A simple system for a user to buy random items and get a list of all the items that he bought.


-
 
**
customer-facing
**
 - REST API that receives purchases and sends them to Kafka
-
 
**
customer-management
**
 - Consumes from Kafka and stores purchases in MongoDB
-
 
**
frontend
**
 - Web UI to buy items and view purchase history
-
 
**
Prometheus + Adapter
**
 - Collects metrics and exposes them for autoscaling

![Architecture diagram](assets/buylist.drawio.png)

## Autoscaling Metrics


 ### customer-facing:
-  CPU, memory
- HTTP RPS
-  in-flight requests 


### customer-management 
-CPU
- memory
- Kafka consumer lag
- work queue depth 


# How to get your setup up and running

## Prerequisites

1. install minikube:
Install 
[
minikube
](
https://minikube.sigs.k8s.io/docs/start/
)


## Deploy to Minikube

```bash
# Start minikube
minikube start

# Enable metrics-server
minikube addons enable metrics-server

# Deploy all components
kubectl apply -f k8s/

# Wait for pods to be ready
kubectl get pods -w
```

## Verify Deployment

check for pods Running:
```bash
kubectl get pods
```

Expected:
- customer-facing (2 replicas)
- customer-management (2 replicas)
- kafka
- zookeeper
- mongodb
- prometheus
- prometheus-adapter
- kafka-exporter
- user-buy-frontend

## Test the Application

```bash
# Port-forward frontend
kubectl port-forward svc/user-buy-frontend 8080:80
```

Open http://localhost:8080

1. **Buy**: Enter username, userid, price, then click Buy
2. **Get All Buys**: Enter userid, then click getAllUserBuys

## Test Metrics

```bash
# Check Prometheus targets
kubectl port-forward svc/prometheus 9090:9090
```

Open http://localhost:9090/targets - all targets should be UP.



##
 Cleanup

```
bash

kubectl delete -f k8s/
minikube stop

