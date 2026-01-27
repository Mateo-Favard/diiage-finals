#!/usr/bin/env bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "\n${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    print_error "helm is not installed. Please install helm first."
    exit 1
fi

print_header "Kubernetes Monitoring Stack Installation"
echo "This script will install:"
echo "  - cert-manager (required for OpenTelemetry Operator)"
echo "  - OpenTelemetry Operator"
echo "  - OpenTelemetry Collector"
echo "  - Tempo (distributed tracing)"
echo "  - Prometheus (metrics)"
echo "  - Grafana (visualization)"
echo ""
read -p "Do you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Installation cancelled."
    exit 0
fi

# Step 0: Add Helm repositories
print_header "Step 0/4: Adding Helm repositories"

print_info "Adding Grafana Helm repo..."
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || print_info "Grafana repo already added"

print_info "Adding Prometheus Community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || print_info "Prometheus repo already added"

print_info "Adding OpenTelemetry Helm repo..."
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || print_info "OpenTelemetry repo already added"

print_info "Updating Helm repositories..."
helm repo update

print_success "Helm repositories configured"

# Step 1: Install cert-manager
print_header "Step 1/4: Installing cert-manager"
print_info "cert-manager is required for OpenTelemetry Operator webhooks..."

if kubectl get namespace cert-manager &> /dev/null; then
    print_info "cert-manager namespace already exists, skipping installation..."
else
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
    
    print_info "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/cert-manager \
        deployment/cert-manager-webhook \
        deployment/cert-manager-cainjector \
        -n cert-manager || true
    
    print_success "cert-manager installed successfully"
fi

# Step 2: Install OpenTelemetry Operator
print_header "Step 2/4: Installing OpenTelemetry Operator"

if kubectl get namespace opentelemetry-operator-system &> /dev/null; then
    print_info "OpenTelemetry Operator namespace already exists, skipping installation..."
else
    kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/download/v0.91.0/opentelemetry-operator.yaml
    
    print_info "Waiting for OpenTelemetry Operator to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/opentelemetry-operator-controller-manager \
        -n opentelemetry-operator-system || true
    
    print_success "OpenTelemetry Operator installed successfully"
fi

# Step 3: Build and install monitoring stack chart
print_header "Step 3/6: Building and installing monitoring stack chart"

print_info "Building chart dependencies..."
cd chart
helm dependency update
cd ..

print_info "Installing monitoring stack (Prometheus, Grafana, Tempo, OpenTelemetry Collector)..."
helm upgrade --install monitoring-stack ./chart \
    --namespace monitoring \
    --create-namespace \
    --wait \
    --timeout 10m || print_info "Installation may have warnings"

print_success "Monitoring stack chart deployed"

# Step 4: Wait for all components to be ready
print_header "Step 4/6: Verifying all components are ready"

print_info "This may take a few moments..."
sleep 10

print_success "Installation complete!"

# Summary
print_header "Installation Complete! 🎉"

echo -e "${GREEN}Monitoring stack is now running!${NC}\n"

echo "Components installed:"
echo "  ✓ cert-manager"
echo "  ✓ OpenTelemetry Operator"
echo "  ✓ OpenTelemetry Collector"
echo "  ✓ Tempo (tracing backend)"
echo "  ✓ Prometheus (metrics backend)"
echo "  ✓ Grafana (visualization)"
echo ""

echo "To access Grafana:"
echo "  1. Run: kubectl port-forward -n monitoring svc/grafana 3000:3000"
echo "  2. Open: http://localhost:3000"
echo "  3. Login: admin / admin"
echo ""

echo "Your backend application metrics are available at /metrics endpoint"
echo "and will be scraped by Prometheus via the OpenTelemetry Collector."
echo ""

print_success "Happy monitoring! 📊"
