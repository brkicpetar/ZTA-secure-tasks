#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAMESPACE="secure-tasks"
MONITORING_NAMESPACE="monitoring"
KYVERNO_NAMESPACE="kyverno"

FRONTEND_IMAGE="secure-tasks/frontend:latest"
BACKEND_IMAGE="secure-tasks/backend:latest"
AUTH_IMAGE="secure-tasks/auth-service:latest"

CURRENT_STEP="initialization"

error_handler() {
    local exit_code=$?

    echo ""
    echo "========================================"
    echo " INICIJALIZACIJA NEUSPEŠNA"
    echo "========================================"
    echo "Korak: $CURRENT_STEP"
    echo "Exit code: $exit_code"
    echo ""

    if kubectl cluster-info >/dev/null 2>&1; then
        echo "Application pods:"
        kubectl get pods -n "$APP_NAMESPACE" 2>/dev/null || true

        echo ""
        echo "Monitoring pods:"
        kubectl get pods -n "$MONITORING_NAMESPACE" 2>/dev/null || true

        echo ""
        echo "Recent application events:"
        kubectl get events \
            -n "$APP_NAMESPACE" \
            --sort-by=.lastTimestamp 2>/dev/null | tail -15 || true
    fi

    echo ""
    echo "Ispravite grešku i pokrenite ./setup.sh ponovo."
    exit "$exit_code"
}

trap error_handler ERR

echo "========================================"
echo " Secure Tasks - Zero Trust Setup"
echo "========================================"

# --------------------------------------------------
# 1. Dependencies
# --------------------------------------------------

CURRENT_STEP="Proveravam preduslove"

echo ""
echo "[1/9] Proveravam preduslove..."

for cmd in docker minikube kubectl helm curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "GREŠKA: '$cmd' nije instaliran."
        exit 1
    fi
done

if ! docker info >/dev/null 2>&1; then
    echo "GREŠKA: Docker je instaliran ali nije pokrenut."
    echo "Pokrenite Docker Desktop i probajte ponovo."
    exit 1
fi

echo "✓ Preduslovi ispunjeni"

# --------------------------------------------------
# 2. Minikube
# --------------------------------------------------

CURRENT_STEP="Pokrećem Minikube"

echo ""
echo "[2/9] Pokrećem Minikube..."

if minikube status >/dev/null 2>&1; then
    echo "✓ Minikube već pokrenut"
else
    minikube start --driver=docker --cni=calico
fi

kubectl wait \
    --for=condition=Ready \
    node/minikube \
    --timeout=180s

echo "✓ Kubernetes spreman"

# --------------------------------------------------
# 3. Calico
# --------------------------------------------------

CURRENT_STEP="Proveravam Calico"

echo ""
echo "[3/9] Proveravam Calico..."

if ! kubectl get pods -n kube-system \
    -l k8s-app=calico-node \
    --no-headers 2>/dev/null | grep -q .; then

    echo "GREŠKA: Calico nije pronađen."
    echo ""
    echo "Ovaj projekat zahteva NetworkPolicy-capable CNI."
    echo "Nemojte nastavljati sa nekompatibilnim klasterima"
    exit 1
fi

kubectl wait \
    --for=condition=Ready \
    pod \
    -l k8s-app=calico-node \
    -n kube-system \
    --timeout=180s

echo "✓ Calico spreman"

# --------------------------------------------------
# 4. Namespace + ServiceAccounts
# --------------------------------------------------

CURRENT_STEP="Kreiram namespace and RBAC identitete"

echo ""
echo "[4/9] Konfigurišem namespace and ServiceAccounts..."

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/rbac.yaml

echo "✓ Namespace i ServiceAccounts konfigurisani"

# --------------------------------------------------
# 5. Build images
# --------------------------------------------------

CURRENT_STEP="Buildujem App Images"

echo ""
echo "[5/9] Buildujem App Images..."

minikube image build \
    -t "$FRONTEND_IMAGE" \
    ./frontend

minikube image build \
    -t "$BACKEND_IMAGE" \
    ./backend

minikube image build \
    -t "$AUTH_IMAGE" \
    ./auth-service

echo "✓ App Images spremni"

# --------------------------------------------------
# 6. Kyverno
# --------------------------------------------------

CURRENT_STEP="Instaliram Kyverno"

echo ""
echo "[6/9] Instaliram Kyverno..."

helm repo add kyverno \
    https://kyverno.github.io/kyverno/ \
    --force-update >/dev/null

helm repo update >/dev/null

if helm status kyverno \
    -n "$KYVERNO_NAMESPACE" >/dev/null 2>&1; then

    echo "✓ Kyverno Helm release već postoji"
else
    helm install kyverno kyverno/kyverno \
        --namespace "$KYVERNO_NAMESPACE" \
        --create-namespace \
        --wait \
        --timeout 5m
fi

kubectl wait \
    --for=condition=Ready \
    pod \
    --all \
    -n "$KYVERNO_NAMESPACE" \
    --timeout=300s

kubectl apply -f k8s/kyverno.yaml

echo "✓ Kyverno spreman"
echo "✓ Bezbednosna pravila primenjena"

# --------------------------------------------------
# 7. Application
# --------------------------------------------------

CURRENT_STEP="Pokrećem aplikaciju"

echo ""
echo "[7/9] Pokrećem aplikaciju..."

kubectl apply -f k8s/redis.yaml
kubectl apply -f k8s/auth-service.yaml
kubectl apply -f k8s/backend.yaml
kubectl apply -f k8s/frontend.yaml
kubectl apply -f k8s/network-policy.yaml

for deployment in redis auth-service backend frontend; do
    echo "Čekam $deployment..."

    kubectl rollout status \
        "deployment/$deployment" \
        -n "$APP_NAMESPACE" \
        --timeout=180s
done

echo "✓ Aplikacija spremna"

# --------------------------------------------------
# 8. Monitoring
# --------------------------------------------------

CURRENT_STEP="Instaliram monitoring"

echo ""
echo "[8/9] Instaliram Prometheus i Grafanu..."

helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts \
    --force-update >/dev/null

helm repo update >/dev/null

if helm status monitoring \
    -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then

    echo "✓ Monitoring Helm release već postoji"
else
    helm install monitoring \
        prometheus-community/kube-prometheus-stack \
        --namespace "$MONITORING_NAMESPACE" \
        --create-namespace \
        --wait \
        --timeout 10m
fi

kubectl wait \
    --for=condition=Ready \
    pod \
    --all \
    -n "$MONITORING_NAMESPACE" \
    --timeout=600s

echo "✓ Monitoring spreman"

# --------------------------------------------------
# 9. Monitoring integration
# --------------------------------------------------

CURRENT_STEP="Konfigurišem bezbednosni monitoring"

echo ""
echo "[9/9] Konfigurišem bezbednosni monitoring..."

kubectl apply -f k8s/service-monitor.yaml
kubectl apply -f k8s/security-alerts.yaml

if ! kubectl get servicemonitor \
    secure-tasks-backend \
    -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then

    echo "GREŠKA: Backend ServiceMonitor nije kreiran."
    exit 1
fi

if ! kubectl get prometheusrule \
    secure-tasks-security-alerts \
    -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then

    echo "GREŠKA: PrometheusRule nije kreiran."
    exit 1
fi

echo "✓ ServiceMonitor konfigurisan"
echo "✓ Bezbednosna pravila konfigurisana"

# --------------------------------------------------
# Finished
# --------------------------------------------------

trap - ERR

echo ""
echo "========================================"
echo " INICIJALIZACIJA USPEŠNA"
echo "========================================"
echo ""
echo "Aplikacija je uspešno inicijalizovana."
echo ""
echo "Pokrenite aplikaciju pomoću:"
echo ""
echo "  ./start.sh"
echo ""