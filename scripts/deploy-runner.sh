#!/bin/bash
set -e

echo "GitHub Actions Self-Hosted Runner Setup"
echo ""

read -p "Enter GitHub repository (e.g., aliceco01/user-buy-list): " GITHUB_REPOSITORY
read -sp "Enter GitHub PAT (with 'repo' scope): " GITHUB_PAT
echo ""

eval $(minikube docker-env)

# Build runner image
docker build -t github-runner:local -f - . << 'DOCKERFILE'
FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y curl jq git sudo docker.io nodejs npm && rm -rf /var/lib/apt/lists/*
RUN npm install -g yarn
RUN useradd -m runner && echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
WORKDIR /home/runner
RUN ARCH=$(dpkg --print-architecture) && \
    curl -o runner.tar.gz -L "https://github.com/actions/runner/releases/download/v2.320.0/actions-runner-linux-${ARCH}-2.320.0.tar.gz" && \
    tar xzf runner.tar.gz && rm runner.tar.gz && ./bin/installdependencies.sh && chown -R runner:runner .
USER runner
CMD REG_TOKEN=$(curl -sX POST -H "Authorization: token ${GITHUB_PAT}" "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runners/registration-token" | jq -r .token) && \
    ./config.sh --url "https://github.com/${GITHUB_REPOSITORY}" --token "$REG_TOKEN" --name minikube-runner --labels self-hosted,linux,minikube --unattended --replace && \
    ./run.sh
DOCKERFILE

kubectl create namespace actions-runner 2>/dev/null || true
kubectl delete secret github-runner-secret -n actions-runner 2>/dev/null || true
kubectl create secret generic github-runner-secret -n actions-runner --from-literal=GITHUB_PAT="$GITHUB_PAT" --from-literal=GITHUB_REPOSITORY="$GITHUB_REPOSITORY"

kubectl apply -f - << YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: github-runner
  namespace: actions-runner
spec:
  replicas: 1
  selector:
    matchLabels:
      app: github-runner
  template:
    metadata:
      labels:
        app: github-runner
    spec:
      containers:
        - name: runner
          image: github-runner:local
          imagePullPolicy: Never
          env:
            - name: GITHUB_PAT
              valueFrom:
                secretKeyRef:
                  name: github-runner-secret
                  key: GITHUB_PAT
            - name: GITHUB_REPOSITORY
              valueFrom:
                secretKeyRef:
                  name: github-runner-secret
                  key: GITHUB_REPOSITORY
          volumeMounts:
            - name: docker-sock
              mountPath: /var/run/docker.sock
      volumes:
        - name: docker-sock
          hostPath:
            path: /var/run/docker.sock
YAML

echo "Waiting for runner..."
kubectl rollout status deployment/github-runner -n actions-runner --timeout=180s
echo "✅ Done! Check: kubectl logs -f deployment/github-runner -n actions-runner"
