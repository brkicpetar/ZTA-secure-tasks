#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAMESPACE="secure-tasks"
MONITORING_NAMESPACE="monitoring"
KYVERNO_NAMESPACE="kyverno"

PIDS=()
CLEANED_UP=false

cleanup() {
    if [ "$CLEANED_UP" = true ]; then
        return
    fi

    CLEANED_UP=true

    if [ "${#PIDS[@]}" -gt 0 ]; then
        echo ""
        echo "Zaustavljanje port forwardinga..."

        for pid in "${PIDS[@]}"; do
            kill "$pid" 2>/dev/null || true
        done

        wait 2>/dev/null || true

        echo "✓ Port forwarding stopped"
    fi
}

fail() {
    local message="$1"

    echo ""
    echo "========================================"
    echo " POKRETANJE NEUSPEŠNO"
    echo "========================================"
    echo "$message"
    echo ""

    cleanup

    echo "Aplikacija NIJE pokrenuta."
    echo ""
    echo "Ako fale komponente, pokreni:"
    echo ""
    echo "  ./setup.sh"
    echo ""

    exit 1
}

trap cleanup EXIT
trap 'fail "Startup interrupted."' INT TERM

echo "========================================"
echo " Secure Tasks - Zero Trust Environment"
echo "========================================"

# --------------------------------------------------
# Dependencies
# --------------------------------------------------

echo ""
echo "[1/8] Proveravanje potrebnog softvera..."

for cmd in docker minikube kubectl curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "'$cmd' nije instaliran."
    fi
done

if ! docker info >/dev/null 2>&1; then
    fail "Docker nije pokrenut. Pokrenite prvo Docker Desktop."
fi

echo "✓ Potreban softver spreman"

# --------------------------------------------------
# Minikube
# --------------------------------------------------

echo ""
echo "[2/8] Pokrećem Kubernetes..."

if ! minikube start; then
    fail "Minikube se nije pokrenuo."
fi

if ! kubectl wait \
    --for=condition=Ready \
    node/minikube \
    --timeout=180s; then

    fail "Kubernetes čvor nije Ready."
fi

echo "✓ Kubernetes spreman"

# --------------------------------------------------
# Calico
# --------------------------------------------------

echo ""
echo "[3/8] Podešavam mrežnu bezbednost..."

if ! kubectl get pods \
    -n kube-system \
    -l k8s-app=calico-node \
    --no-headers 2>/dev/null | grep -q .; then

    fail "Calico nedostaje. NetworkPolicy se ne može pokrenuti."
fi

if ! kubectl wait \
    --for=condition=Ready \
    pod \
    -l k8s-app=calico-node \
    -n kube-system \
    --timeout=180s; then

    fail "Calico nije spreman."
fi

if ! kubectl get networkpolicy \
    default-deny-all \
    -n "$APP_NAMESPACE" >/dev/null 2>&1; then

    fail "Neophodan default-deny NetworkPolicy nedostaje."
fi

echo "✓ Calico spreman"
echo "✓ NetworkPolicy aktivan"

# --------------------------------------------------
# Kyverno
# --------------------------------------------------

echo ""
echo "[4/8] Podešavam policy primenu..."

if ! kubectl get namespace \
    "$KYVERNO_NAMESPACE" >/dev/null 2>&1; then

    fail "Kyverno namespace nedostaje."
fi

if ! kubectl wait \
    --for=condition=Ready \
    pod \
    --all \
    -n "$KYVERNO_NAMESPACE" \
    --timeout=180s; then

    fail "Kyverno nije spreman."
fi

if ! kubectl get clusterpolicy \
    disallow-privileged-containers >/dev/null 2>&1; then

    fail "Kyverno bezbednosni policy nedostaje."
fi

echo "✓ Kyverno spreman"
echo "✓ Bezbednosna pravila aktivna"

# --------------------------------------------------
# Application
# --------------------------------------------------

echo ""
echo "[5/8] Pokrećem aplikaciju..."

for deployment in redis auth-service backend frontend; do

    if ! kubectl get deployment \
        "$deployment" \
        -n "$APP_NAMESPACE" >/dev/null 2>&1; then

        fail "$deployment' nedostaje."
    fi

    echo "Proveravam $deployment..."

    if ! kubectl rollout status \
        "deployment/$deployment" \
        -n "$APP_NAMESPACE" \
        --timeout=180s; then

        echo ""
        kubectl get pods -n "$APP_NAMESPACE" || true

        echo ""
        echo "Recent events:"
        kubectl get events \
            -n "$APP_NAMESPACE" \
            --sort-by=.lastTimestamp 2>/dev/null | tail -15 || true

        fail "$deployment' nije spreman."
    fi
done

echo "✓ Frontend spreman"
echo "✓ Backend spreman"
echo "✓ Auth spreman"
echo "✓ Redis spreman"

# --------------------------------------------------
# Monitoring
# --------------------------------------------------

echo ""
echo "[6/8] Podešavam monitoring..."

if ! kubectl get namespace \
    "$MONITORING_NAMESPACE" >/dev/null 2>&1; then

    fail "Monitoring namespace nedostaje."
fi

if ! kubectl wait \
    --for=condition=Ready \
    pod \
    --all \
    -n "$MONITORING_NAMESPACE" \
    --timeout=300s; then

    echo ""
    kubectl get pods -n "$MONITORING_NAMESPACE" || true

    fail "Prometheus/Grafana nije spreman."
fi

if ! kubectl get servicemonitor \
    secure-tasks-backend \
    -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then

    fail "Backend ServiceMonitor nedostaje."
fi

if ! kubectl get prometheusrule \
    secure-tasks-security-alerts \
    -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then

    fail "Bezbednosna pravila nedostaju."
fi

echo "✓ Prometheus spreman"
echo "✓ Grafana spremna"
echo "✓ Bezbednosni monitoring konfigurisan"

# --------------------------------------------------
# Port forwards
# --------------------------------------------------

echo ""
echo "[7/8] Pokrećem portove..."

start_forward() {
    local namespace="$1"
    local service="$2"
    local mapping="$3"
    local name="$4"

    kubectl port-forward \
        -n "$namespace" \
        "service/$service" \
        "$mapping" \
        >/tmp/secure-tasks-"$service".log 2>&1 &

    local pid=$!
    PIDS+=("$pid")

    sleep 1

    if ! kill -0 "$pid" 2>/dev/null; then
        echo ""
        echo "$name port-forward log:"
        cat /tmp/secure-tasks-"$service".log 2>/dev/null || true

        fail "$name port-forward nije uspešan."
    fi

    echo "✓ $name port pokrenut"
}

start_forward \
    "$APP_NAMESPACE" \
    frontend \
    3000:3000 \
    "Frontend"

start_forward \
    "$APP_NAMESPACE" \
    backend \
    4000:4000 \
    "Backend"

start_forward \
    "$APP_NAMESPACE" \
    auth-service \
    4001:4001 \
    "Auth"

start_forward \
    "$MONITORING_NAMESPACE" \
    monitoring-grafana \
    3001:80 \
    "Grafana"

start_forward \
    "$MONITORING_NAMESPACE" \
    monitoring-kube-prometheus-prometheus \
    9090:9090 \
    "Prometheus"

# --------------------------------------------------
# Health checks
# --------------------------------------------------

echo ""
echo "[8/8] Health check..."

sleep 3

check_url() {
    local url="$1"
    local name="$2"

    if ! curl \
        --silent \
        --show-error \
        --fail \
        --max-time 5 \
        "$url" >/dev/null; then

        fail "$name health check nije uspešan: $url"
    fi

    echo "✓ $name zdrav"
}

# /metrics is known to exist on our backend.
check_url \
    "http://localhost:4000/metrics" \
    "Backend"

# Grafana exposes a dedicated health endpoint.
check_url \
    "http://localhost:3001/api/health" \
    "Grafana"

# Prometheus health endpoint.
check_url \
    "http://localhost:9090/-/healthy" \
    "Prometheus"

# Frontend only needs to return a successful HTTP response.
check_url \
    "http://localhost:3000" \
    "Frontend"

# Auth has no guaranteed public health endpoint in our current app.
# Verify that the port-forward process is alive instead.
if ! curl \
    --silent \
    --max-time 5 \
    -o /dev/null \
    http://localhost:4001/; then

    # A 404 still proves that the HTTP server is reachable.
    if ! curl \
        --silent \
        --max-time 5 \
        -o /dev/null \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{}' \
        http://localhost:4001/login; then

        fail "Auth nedostupan na portu 4001."
    fi
fi

echo "✓ Auth zdrav"

# --------------------------------------------------
# Final information
# --------------------------------------------------

echo ""
echo "========================================"
echo " SECURE TASKS SPREMAN"
echo "========================================"
echo ""
echo " Aplikacija"
echo "   http://localhost:3000"
echo ""
echo " API"
echo "   Backend:    http://localhost:4000"
echo "   Auth:       http://localhost:4001"
echo ""
echo " Bezbednosni Monitoring"
echo "   Grafana:    http://localhost:3001"
echo "   Prometheus: http://localhost:9090"
echo ""
echo " Grafana kredencijali"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo " User kredencijali"
echo "   Username: petar"
echo "   Password: petar123"
echo ""
echo " Admin kredencijali"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo " Bezbednosne kontrole"
echo "   ✓ JWT"
echo "   ✓ Role autorizacija"
echo "   ✓ Kubernetes RBAC"
echo "   ✓ Calico NetworkPolicy"
echo "   ✓ Kyverno policy"
echo "   ✓ Prometheus monitoring"
echo "   ✓ Security alerting"
echo ""
echo "========================================"
echo " Pritisnite Ctrl+C za prekid rada"
echo "========================================"

# Keep port-forward processes alive and detect failures.
while true; do
    sleep 5

    for pid in "${PIDS[@]}"; do
        if ! kill -0 "$pid" 2>/dev/null; then
            fail "Neophodan port-forward proces se neočekivano zaustavio."
        fi
    done
done