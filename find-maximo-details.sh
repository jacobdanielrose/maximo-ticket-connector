#!/bin/bash

# Comprehensive script to find Maximo details in OpenShift
# Usage: ./find-maximo-details.sh [namespace]

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Comprehensive Maximo Discovery${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check for oc or kubectl
if command -v oc >/dev/null 2>&1; then
    CMD="oc"
elif command -v kubectl >/dev/null 2>&1; then
    CMD="kubectl"
else
    echo -e "${RED}Error: Neither 'oc' nor 'kubectl' found${NC}"
    exit 1
fi

echo -e "${GREEN}Using command: ${CMD}${NC}\n"

# Get namespace
NAMESPACE="${1}"

# Step 1: Find all namespaces
echo -e "${BLUE}Step 1: Finding all namespaces...${NC}"
ALL_NAMESPACES=$($CMD get namespaces -o name 2>/dev/null | sed 's/namespace\///')
echo "Total namespaces: $(echo "$ALL_NAMESPACES" | wc -l)"

# Filter for Maximo-related
MAXIMO_NS=$(echo "$ALL_NAMESPACES" | grep -E "mas-|maximo|manage|db2" || true)
if [ -n "$MAXIMO_NS" ]; then
    echo -e "${GREEN}Maximo-related namespaces:${NC}"
    echo "$MAXIMO_NS"
else
    echo -e "${YELLOW}No obvious Maximo namespaces found${NC}"
fi
echo ""

# If no namespace provided, try to find one
if [ -z "$NAMESPACE" ]; then
    if [ -n "$MAXIMO_NS" ]; then
        NAMESPACE=$(echo "$MAXIMO_NS" | head -n 1)
        echo -e "${GREEN}Auto-selected namespace: ${NAMESPACE}${NC}\n"
    else
        echo -e "${YELLOW}Please specify a namespace:${NC}"
        echo "$CMD get namespaces"
        echo ""
        echo "Then run: $0 <namespace>"
        exit 1
    fi
fi

# Step 2: Check all resources in namespace
echo -e "${BLUE}Step 2: Checking resources in namespace: ${NAMESPACE}${NC}"

# Pods
echo -e "\n${YELLOW}Pods:${NC}"
$CMD get pods -n "$NAMESPACE" 2>/dev/null | head -20 || echo "No pods found"

# Services
echo -e "\n${YELLOW}Services:${NC}"
SERVICES=$($CMD get svc -n "$NAMESPACE" 2>/dev/null || true)
echo "$SERVICES"

# Routes (OpenShift)
echo -e "\n${YELLOW}Routes:${NC}"
ROUTES=$($CMD get routes -n "$NAMESPACE" 2>/dev/null || echo "No routes found (might be Kubernetes, not OpenShift)")
echo "$ROUTES"

# Ingresses (Kubernetes)
echo -e "\n${YELLOW}Ingresses:${NC}"
INGRESSES=$($CMD get ingress -n "$NAMESPACE" 2>/dev/null || echo "No ingresses found")
echo "$INGRESSES"

# Step 3: Look for Maximo UI service
echo -e "\n${BLUE}Step 3: Looking for Maximo UI service...${NC}"
UI_SERVICE=$($CMD get svc -n "$NAMESPACE" -o name 2>/dev/null | grep -E "ui|maximo|manage" | head -1 || true)

if [ -n "$UI_SERVICE" ]; then
    echo -e "${GREEN}Found UI service: ${UI_SERVICE}${NC}"
    
    # Get service details
    SERVICE_NAME=$(echo "$UI_SERVICE" | sed 's/service\///')
    SERVICE_PORT=$($CMD get svc "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
    
    echo -e "${YELLOW}Service: ${SERVICE_NAME}${NC}"
    echo -e "${YELLOW}Port: ${SERVICE_PORT}${NC}"
    echo ""
    
    echo -e "${GREEN}You can access Maximo via port-forward:${NC}"
    echo "$CMD port-forward -n $NAMESPACE svc/$SERVICE_NAME 8080:$SERVICE_PORT"
    echo ""
    echo -e "${GREEN}Then use this URL:${NC}"
    echo "http://localhost:8080"
    echo ""
fi

# Step 4: Check for external URLs in various places
echo -e "${BLUE}Step 4: Searching for external URLs...${NC}"

# Check all ConfigMaps
echo -e "\n${YELLOW}Checking ConfigMaps...${NC}"
CONFIGMAP_URLS=$($CMD get configmap -n "$NAMESPACE" -o json 2>/dev/null | \
    grep -oE "https?://[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]*)?" | \
    grep -v "localhost\|127.0.0.1\|example.com" | \
    sort -u || true)

if [ -n "$CONFIGMAP_URLS" ]; then
    echo -e "${GREEN}Found URLs in ConfigMaps:${NC}"
    echo "$CONFIGMAP_URLS"
fi

# Check Secrets (base64 decode)
echo -e "\n${YELLOW}Checking Secrets for URLs...${NC}"
SECRET_URLS=$($CMD get secrets -n "$NAMESPACE" -o json 2>/dev/null | \
    grep -oE "https?://[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]*)?" | \
    grep -v "localhost\|127.0.0.1\|example.com" | \
    sort -u || true)

if [ -n "$SECRET_URLS" ]; then
    echo -e "${GREEN}Found URLs in Secrets:${NC}"
    echo "$SECRET_URLS"
fi

# Check environment variables in pods
echo -e "\n${YELLOW}Checking Pod environment variables...${NC}"
FIRST_POD=$($CMD get pods -n "$NAMESPACE" -o name 2>/dev/null | grep -E "maximo|manage|ui" | head -1 || true)

if [ -n "$FIRST_POD" ]; then
    POD_NAME=$(echo "$FIRST_POD" | sed 's/pod\///')
    echo "Checking pod: $POD_NAME"
    
    ENV_URLS=$($CMD exec -n "$NAMESPACE" "$POD_NAME" -- env 2>/dev/null | \
        grep -E "URL|HOST|ENDPOINT" | \
        grep -oE "https?://[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]*)?" || true)
    
    if [ -n "$ENV_URLS" ]; then
        echo -e "${GREEN}Found URLs in pod environment:${NC}"
        echo "$ENV_URLS"
    fi
fi

# Step 5: Check for MAS (Maximo Application Suite) CRDs
echo -e "\n${BLUE}Step 5: Checking for MAS Custom Resources...${NC}"
MAS_SUITE=$($CMD get Suite -n "$NAMESPACE" 2>/dev/null || true)

if [ -n "$MAS_SUITE" ]; then
    echo -e "${GREEN}Found MAS Suite:${NC}"
    echo "$MAS_SUITE"
    
    # Get Manage URL
    MANAGE_URL=$($CMD get Suite -n "$NAMESPACE" -o jsonpath='{.items[0].status.components.manage.url}' 2>/dev/null || true)
    if [ -n "$MANAGE_URL" ]; then
        echo -e "${GREEN}Manage URL: ${MANAGE_URL}${NC}"
    fi
fi

# Step 6: Summary and recommendations
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Summary & Recommendations${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Collect all URLs
ALL_URLS=""
[ -n "$CONFIGMAP_URLS" ] && ALL_URLS="${ALL_URLS}${CONFIGMAP_URLS}\n"
[ -n "$SECRET_URLS" ] && ALL_URLS="${ALL_URLS}${SECRET_URLS}\n"
[ -n "$ENV_URLS" ] && ALL_URLS="${ALL_URLS}${ENV_URLS}\n"
[ -n "$MANAGE_URL" ] && ALL_URLS="${ALL_URLS}${MANAGE_URL}\n"

if [ -n "$ALL_URLS" ]; then
    echo -e "${GREEN}Found potential Maximo URLs:${NC}"
    echo -e "$ALL_URLS" | sort -u | grep -v "^$"
    echo ""
    
    FIRST_URL=$(echo -e "$ALL_URLS" | grep -v "^$" | head -1)
    
    echo -e "${YELLOW}Test with curl:${NC}"
    echo "curl -k ${FIRST_URL}/maximo/oslc/os/mxincident?oslc.pageSize=1"
    echo ""
    
    echo -e "${YELLOW}Use with demo script:${NC}"
    echo "python3 create-demo-incidents.py --url ${FIRST_URL} --user maxadmin --password pass --count 10"
    
elif [ -n "$UI_SERVICE" ]; then
    echo -e "${YELLOW}No external URL found, but you can use port-forward:${NC}"
    echo ""
    echo "1. Start port-forward:"
    echo "   $CMD port-forward -n $NAMESPACE svc/$SERVICE_NAME 8080:$SERVICE_PORT"
    echo ""
    echo "2. In another terminal, use:"
    echo "   python3 create-demo-incidents.py --url http://localhost:8080 --user maxadmin --password pass --count 10"
    
else
    echo -e "${RED}Could not find Maximo URL or service${NC}"
    echo ""
    echo -e "${YELLOW}Manual steps:${NC}"
    echo "1. Check if you're in the right namespace:"
    echo "   $CMD get namespaces | grep -E 'mas-|maximo'"
    echo ""
    echo "2. List all services:"
    echo "   $CMD get svc -n <namespace>"
    echo ""
    echo "3. Check routes (OpenShift):"
    echo "   $CMD get routes -n <namespace>"
    echo ""
    echo "4. Try port-forwarding to any Maximo service:"
    echo "   $CMD port-forward -n <namespace> svc/<service-name> 8080:80"
    echo ""
    echo "5. Or ask your Maximo admin for the URL"
fi

echo ""

# Made with Bob
