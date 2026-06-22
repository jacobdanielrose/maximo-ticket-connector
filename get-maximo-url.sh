#!/bin/bash

# Script to find Maximo URL from OpenShift/Kubernetes
# Usage: ./get-maximo-url.sh [namespace]

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Finding Maximo URL in OpenShift${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for oc or kubectl
if command_exists oc; then
    CMD="oc"
elif command_exists kubectl; then
    CMD="kubectl"
else
    echo -e "${RED}Error: Neither 'oc' nor 'kubectl' found${NC}"
    exit 1
fi

# Get namespace
NAMESPACE="${1}"

if [ -z "$NAMESPACE" ]; then
    echo -e "${YELLOW}No namespace provided. Searching all namespaces...${NC}\n"
    
    # Search for Maximo-related namespaces
    echo -e "${BLUE}Looking for Maximo namespaces:${NC}"
    MAXIMO_NAMESPACES=$($CMD get namespaces -o name 2>/dev/null | grep -E "mas-|maximo" | sed 's/namespace\///')
    
    if [ -z "$MAXIMO_NAMESPACES" ]; then
        echo -e "${RED}No Maximo namespaces found${NC}"
        echo -e "${YELLOW}Try: $CMD get namespaces${NC}"
        exit 1
    fi
    
    echo "$MAXIMO_NAMESPACES"
    echo ""
    
    # Use first namespace found
    NAMESPACE=$(echo "$MAXIMO_NAMESPACES" | head -n 1)
    echo -e "${GREEN}Using namespace: ${NAMESPACE}${NC}\n"
fi

# Method 1: Check Routes (OpenShift)
echo -e "${BLUE}Method 1: Checking Routes...${NC}"
ROUTES=$($CMD get routes -n "$NAMESPACE" 2>/dev/null | grep -E "maximo|manage" || true)

if [ -n "$ROUTES" ]; then
    echo "$ROUTES"
    echo ""
    
    # Extract URLs
    MAXIMO_ROUTE=$($CMD get routes -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="maximo" || @.metadata.name=="manage")].spec.host}' 2>/dev/null || true)
    
    if [ -n "$MAXIMO_ROUTE" ]; then
        echo -e "${GREEN}✓ Found Maximo Route:${NC}"
        echo -e "  https://${MAXIMO_ROUTE}"
        echo ""
    fi
fi

# Method 2: Check Ingresses (Kubernetes)
echo -e "${BLUE}Method 2: Checking Ingresses...${NC}"
INGRESSES=$($CMD get ingress -n "$NAMESPACE" 2>/dev/null | grep -E "maximo|manage" || true)

if [ -n "$INGRESSES" ]; then
    echo "$INGRESSES"
    echo ""
    
    # Extract URLs
    MAXIMO_INGRESS=$($CMD get ingress -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="maximo" || @.metadata.name=="manage")].spec.rules[0].host}' 2>/dev/null || true)
    
    if [ -n "$MAXIMO_INGRESS" ]; then
        echo -e "${GREEN}✓ Found Maximo Ingress:${NC}"
        echo -e "  https://${MAXIMO_INGRESS}"
        echo ""
    fi
fi

# Method 3: Check Services
echo -e "${BLUE}Method 3: Checking Services...${NC}"
SERVICES=$($CMD get svc -n "$NAMESPACE" 2>/dev/null | grep -E "maximo|manage|ui" || true)

if [ -n "$SERVICES" ]; then
    echo "$SERVICES"
    echo ""
fi

# Method 4: Check for MAS (Maximo Application Suite) specific resources
echo -e "${BLUE}Method 4: Checking MAS Resources...${NC}"
MAS_WORKSPACES=$($CMD get Suite -n "$NAMESPACE" -o jsonpath='{.items[*].status.components.manage.url}' 2>/dev/null || true)

if [ -n "$MAS_WORKSPACES" ]; then
    echo -e "${GREEN}✓ Found MAS Manage URL:${NC}"
    echo -e "  ${MAS_WORKSPACES}"
    echo ""
fi

# Method 5: Check ConfigMaps for URLs
echo -e "${BLUE}Method 5: Checking ConfigMaps...${NC}"
CONFIGMAP_URLS=$($CMD get configmap -n "$NAMESPACE" -o json 2>/dev/null | grep -oE "https?://[a-zA-Z0-9.-]+/maximo" | sort -u || true)

if [ -n "$CONFIGMAP_URLS" ]; then
    echo -e "${GREEN}✓ Found URLs in ConfigMaps:${NC}"
    echo "$CONFIGMAP_URLS"
    echo ""
fi

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Collect all found URLs
ALL_URLS=""
[ -n "$MAXIMO_ROUTE" ] && ALL_URLS="${ALL_URLS}https://${MAXIMO_ROUTE}\n"
[ -n "$MAXIMO_INGRESS" ] && ALL_URLS="${ALL_URLS}https://${MAXIMO_INGRESS}\n"
[ -n "$MAS_WORKSPACES" ] && ALL_URLS="${ALL_URLS}${MAS_WORKSPACES}\n"
[ -n "$CONFIGMAP_URLS" ] && ALL_URLS="${ALL_URLS}${CONFIGMAP_URLS}\n"

if [ -n "$ALL_URLS" ]; then
    echo -e "${GREEN}Found Maximo URLs:${NC}"
    echo -e "$ALL_URLS" | sort -u
    echo ""
    
    # Get the first URL
    FIRST_URL=$(echo -e "$ALL_URLS" | head -n 1)
    
    echo -e "${YELLOW}To use with the demo script:${NC}"
    echo -e "python3 create-demo-incidents.py \\"
    echo -e "  --url ${FIRST_URL} \\"
    echo -e "  --user maxadmin \\"
    echo -e "  --password your-password \\"
    echo -e "  --count 10"
    echo ""
    
    echo -e "${YELLOW}To test the URL:${NC}"
    echo -e "curl -k ${FIRST_URL}/maximo/oslc/os/mxincident?oslc.pageSize=1"
else
    echo -e "${RED}No Maximo URLs found${NC}\n"
    
    echo -e "${YELLOW}Manual steps:${NC}"
    echo "1. List all namespaces:"
    echo "   $CMD get namespaces | grep -E 'mas-|maximo'"
    echo ""
    echo "2. Check routes in namespace:"
    echo "   $CMD get routes -n <namespace>"
    echo ""
    echo "3. Check ingresses:"
    echo "   $CMD get ingress -n <namespace>"
    echo ""
    echo "4. Port forward to service:"
    echo "   $CMD port-forward -n <namespace> svc/maximo-ui 8080:80"
    echo "   Then use: http://localhost:8080"
fi

echo ""
echo -e "${BLUE}========================================${NC}"

# Made with Bob
