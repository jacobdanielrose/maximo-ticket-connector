#!/bin/bash

################################################################################
# Maximo DB2 Credentials Extractor
# 
# This script extracts DB2 credentials from a Maximo installation in OpenShift
#
# Usage:
#   ./get-maximo-db2-creds.sh <namespace>
#
# Example:
#   ./get-maximo-db2-creds.sh db2u
#   ./get-maximo-db2-creds.sh mas-inst1-core
################################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if namespace provided
if [ -z "$1" ]; then
    log_error "No namespace provided"
    echo ""
    echo "Usage: $0 <namespace>"
    echo ""
    echo "Examples:"
    echo "  $0 db2u"
    echo "  $0 mas-inst1-core"
    echo "  $0 maximo-prod"
    echo ""
    echo "To find namespaces with DB2:"
    echo "  oc get projects | grep -i maximo"
    echo "  oc get projects | grep -i db2"
    exit 1
fi

NAMESPACE="$1"

echo "=================================================="
echo "Maximo DB2 Credentials Extractor"
echo "=================================================="
echo "Namespace: $NAMESPACE"
echo "=================================================="
echo ""

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    log_error "oc CLI is not installed or not in PATH"
    exit 1
fi

# Check if logged in
if ! oc whoami &> /dev/null; then
    log_error "Not logged in to OpenShift"
    echo "Please run: oc login <your-cluster-url>"
    exit 1
fi

log_success "Logged in as: $(oc whoami)"

# Switch to namespace
log_info "Switching to namespace: $NAMESPACE"
if ! oc project $NAMESPACE &> /dev/null; then
    log_error "Failed to switch to namespace: $NAMESPACE"
    echo ""
    echo "Available namespaces:"
    oc get projects | grep -i -E 'maximo|db2|mas'
    exit 1
fi

log_success "Switched to namespace: $NAMESPACE"
echo ""

# Check for DB2U cluster first
log_info "Checking for DB2U clusters..."
if oc get db2ucluster &> /dev/null 2>&1; then
    DB2U_CLUSTERS=$(oc get db2ucluster -o name 2>/dev/null | cut -d'/' -f2)
    if [ ! -z "$DB2U_CLUSTERS" ]; then
        log_success "Found DB2U clusters:"
        echo "$DB2U_CLUSTERS" | sed 's/^/  - /'
        echo ""
        
        # Try to get credentials from db2ucluster
        for CLUSTER in $DB2U_CLUSTERS; do
            log_info "Extracting credentials from cluster: $CLUSTER"
            
            # DB2U stores credentials in specific secret patterns
            INSTANCE_SECRET="c-${CLUSTER}-instancepassword"
            LDAP_SECRET="c-${CLUSTER}-ldap-bluadmin"
            
            # Try instance password secret
            if oc get secret $INSTANCE_SECRET &> /dev/null; then
                log_success "Found instance password secret: $INSTANCE_SECRET"
                FOUND_PASSWORD=$(oc get secret $INSTANCE_SECRET -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null)
                FOUND_USERNAME="db2inst1"  # Default DB2 instance user
                echo "  Username: $FOUND_USERNAME"
                echo "  Password: $FOUND_PASSWORD"
            fi
            
            # Try LDAP secret
            if oc get secret $LDAP_SECRET &> /dev/null; then
                log_success "Found LDAP admin secret: $LDAP_SECRET"
                LDAP_USER=$(oc get secret $LDAP_SECRET -o jsonpath='{.data.username}' 2>/dev/null | base64 -d 2>/dev/null)
                LDAP_PASS=$(oc get secret $LDAP_SECRET -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null)
                if [ ! -z "$LDAP_USER" ]; then
                    echo "  LDAP Username: $LDAP_USER"
                    echo "  LDAP Password: $LDAP_PASS"
                    # Use LDAP credentials if instance credentials not found
                    if [ -z "$FOUND_USERNAME" ]; then
                        FOUND_USERNAME="$LDAP_USER"
                        FOUND_PASSWORD="$LDAP_PASS"
                    fi
                fi
            fi
            
            # Get database name from cluster
            FOUND_DATABASE=$(oc get db2ucluster $CLUSTER -o jsonpath='{.spec.environment.database.name}' 2>/dev/null)
            if [ -z "$FOUND_DATABASE" ]; then
                FOUND_DATABASE="BLUDB"  # Default DB2U database name
            fi
            echo "  Database: $FOUND_DATABASE"
            echo ""
        done
    fi
fi

# Also check for standard secrets
log_info "Looking for additional DB2 secrets..."
DB2_SECRETS=$(oc get secrets 2>/dev/null | grep -i -E 'db2|jdbc|database' | grep -v 'c-.*-' | awk '{print $1}')

if [ -z "$DB2_SECRETS" ] && [ -z "$FOUND_USERNAME" ]; then
    log_warning "No DB2 secrets found"
    echo ""
    echo "All secrets in namespace:"
    oc get secrets
    echo ""
    log_info "You may need to check secrets manually"
fi

echo "Found potential DB2 secrets:"
echo "$DB2_SECRETS" | sed 's/^/  - /'
echo ""

# Try each secret
for SECRET_NAME in $DB2_SECRETS; do
    echo "=================================================="
    log_info "Checking secret: $SECRET_NAME"
    echo "=================================================="
    
    # Get all keys in secret
    KEYS=$(oc get secret $SECRET_NAME -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[]' 2>/dev/null)
    
    if [ -z "$KEYS" ]; then
        log_warning "Could not read secret or secret is empty"
        continue
    fi
    
    echo "Available keys in secret:"
    echo "$KEYS" | sed 's/^/  - /'
    echo ""
    
    # Try to extract common credential fields
    USERNAME=$(oc get secret $SECRET_NAME -o jsonpath='{.data.username}' 2>/dev/null | base64 -d 2>/dev/null)
    PASSWORD=$(oc get secret $SECRET_NAME -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null)
    DATABASE=$(oc get secret $SECRET_NAME -o jsonpath='{.data.database}' 2>/dev/null | base64 -d 2>/dev/null)
    DBNAME=$(oc get secret $SECRET_NAME -o jsonpath='{.data.dbname}' 2>/dev/null | base64 -d 2>/dev/null)
    
    if [ ! -z "$USERNAME" ] || [ ! -z "$PASSWORD" ]; then
        echo "Credentials found:"
        echo "-------------------"
        [ ! -z "$USERNAME" ] && echo "Username: $USERNAME"
        [ ! -z "$PASSWORD" ] && echo "Password: $PASSWORD"
        [ ! -z "$DATABASE" ] && echo "Database: $DATABASE"
        [ ! -z "$DBNAME" ] && echo "DB Name: $DBNAME"
        echo ""
        
        # Save for later use
        FOUND_USERNAME="$USERNAME"
        FOUND_PASSWORD="$PASSWORD"
        FOUND_DATABASE="${DATABASE:-$DBNAME}"
    else
        log_warning "No standard username/password fields found in this secret"
    fi
    echo ""
done

# Find DB2 service
echo "=================================================="
log_info "Looking for DB2 service..."
echo "=================================================="

DB2_SERVICE=$(oc get services 2>/dev/null | grep -i db2 | head -n 1 | awk '{print $1}')

if [ -z "$DB2_SERVICE" ]; then
    log_warning "No DB2 service found with standard name"
    echo ""
    echo "All services in namespace:"
    oc get services
    echo ""
else
    log_success "Found DB2 service: $DB2_SERVICE"
    
    # Get service details
    HOSTNAME="${DB2_SERVICE}.${NAMESPACE}.svc.cluster.local"
    PORT=$(oc get service $DB2_SERVICE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
    
    echo ""
    echo "Connection Details:"
    echo "-------------------"
    echo "Hostname: $HOSTNAME"
    echo "Port: $PORT"
    echo "Database: ${FOUND_DATABASE:-MAXDB76}"
    echo ""
    
    if [ ! -z "$FOUND_USERNAME" ]; then
        echo "JDBC URL:"
        echo "jdbc:db2://${HOSTNAME}:${PORT}/${FOUND_DATABASE:-MAXDB76}"
        echo ""
    fi
fi

# Summary
if [ ! -z "$FOUND_USERNAME" ] && [ ! -z "$FOUND_PASSWORD" ]; then
    echo "=================================================="
    log_success "Credentials extracted successfully!"
    echo "=================================================="
    echo ""
    echo "Configuration for connector .env file:"
    echo "======================================="
    cat <<EOF
export DB_HOST=${HOSTNAME:-db2-service.${NAMESPACE}.svc.cluster.local}
export DB_PORT=${PORT:-50000}
export DB_NAME=${FOUND_DATABASE:-MAXDB76}
export DB_USERNAME=$FOUND_USERNAME
export DB_PASSWORD='$FOUND_PASSWORD'
export DB_SCHEMA=MAXIMO
export VIEW_NAME=INCIDENT_VIEW
EOF
    echo ""
    echo "Copy the above to your .env file!"
else
    echo "=================================================="
    log_warning "Could not extract complete credentials"
    echo "=================================================="
    echo ""
    echo "Manual steps:"
    echo "1. Review the secrets listed above"
    echo "2. Extract credentials manually:"
    echo "   oc get secret <secret-name> -o yaml"
    echo "3. Decode base64 values:"
    echo "   echo '<base64-value>' | base64 -d"
fi

echo ""
echo "=================================================="
echo "Next Steps:"
echo "=================================================="
echo "1. Create the INCIDENT_VIEW in DB2 (see MAXIMO_DB2_VIEW_SETUP.md)"
echo "2. Update your connector .env file with the credentials above"
echo "3. Build and deploy the connector"
echo "=================================================="

# Made with Bob
