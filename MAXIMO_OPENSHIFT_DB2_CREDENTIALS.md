# Getting DB2 Credentials from Maximo in OpenShift

This guide explains how to extract DB2 database credentials from a Maximo installation running in OpenShift/Kubernetes.

## Prerequisites

- Access to the OpenShift cluster where Maximo is installed
- `oc` CLI tool installed and configured
- Appropriate permissions to view secrets and pods in the Maximo namespace

## Quick Reference

```bash
# Login to OpenShift
oc login <your-cluster-url>

# Switch to Maximo namespace
oc project <maximo-namespace>

# Get DB2 credentials
oc get secret <db2-secret-name> -o jsonpath='{.data.username}' | base64 -d
oc get secret <db2-secret-name> -o jsonpath='{.data.password}' | base64 -d
```

## Step-by-Step Guide

### Step 1: Login to OpenShift

```bash
# Login to your OpenShift cluster
oc login https://api.your-cluster.com:6443

# Or if using token
oc login --token=<your-token> --server=https://api.your-cluster.com:6443
```

### Step 2: Find the Maximo Namespace

There are two common Maximo deployment types. Let's identify which one you have:

#### Option A: Maximo Application Suite (MAS) - Modern Deployment

```bash
# Check for MAS namespaces
oc get projects | grep -i mas

# MAS creates multiple namespaces:
# mas-inst1-core          <- DB2 is here
# mas-inst1-manage        <- Maximo Manage app
# mas-inst1-health        <- Maximo Health app
```

**If you see `-core` namespace:** Use that one (e.g., `mas-inst1-core`)

#### Option B: Standalone Maximo - Traditional Deployment

```bash
# Check for standalone Maximo namespaces
oc get projects | grep -i maximo

# Common patterns:
# maximo
# maximo-prod
# maximo-dev
# ibm-maximo
```

**If you DON'T see `-core`:** You have standalone Maximo. Use the main maximo namespace.

#### Universal Method: Find DB2 Directly

If you're unsure, search for DB2 across all namespaces:

```bash
# Search for DB2 pods in all namespaces
echo "Searching for DB2 in all namespaces..."
for ns in $(oc get projects -o name | cut -d'/' -f2); do
  DB2_PODS=$(oc get pods -n $ns 2>/dev/null | grep -i db2 | head -n 1)
  if [ ! -z "$DB2_PODS" ]; then
    echo "✅ Found DB2 in namespace: $ns"
    echo "   Pod: $(echo $DB2_PODS | awk '{print $1}')"
  fi
done
```

#### Quick Decision Tree

```
Do you see namespaces with "-core" suffix?
├─ YES → Use the -core namespace (e.g., mas-inst1-core)
└─ NO  → Do you see "maximo" namespace?
    ├─ YES → Use that namespace
    └─ NO  → Run the universal search above
```

#### Namespace Comparison

| Deployment Type | Namespace Pattern | Example |
|----------------|-------------------|---------|
| **MAS (Modern)** | `mas-<id>-core` | `mas-inst1-core` |
| **Standalone** | `maximo` or `maximo-<env>` | `maximo-prod` |
| **Legacy** | `ibm-maximo` | `ibm-maximo` |

#### What to Do Next

Once you identify your namespace:

```bash
# Set it as a variable
MAXIMO_NS="<your-namespace-here>"

# Verify it has DB2
oc get pods -n $MAXIMO_NS | grep -i db2

# If you see DB2 pods, you're in the right place!
```

### Step 3: Switch to the Correct Namespace

Based on your search results, you need to determine which namespace to use:

#### If You Found Multiple Namespaces with DB2

**Common scenario:** DB2 found in both `db2u` and `mas-xxx-pipelines`

```bash
# Example output:
# Found DB2 in namespace: db2u
# Found DB2 in namespace: mas-dev-pipelines
```

**Which one to use?**

| Namespace | Purpose | Use This? |
|-----------|---------|-----------|
| `db2u` | Shared DB2 operator/instance | ✅ **YES** - Use this for Maximo DB |
| `mas-xxx-pipelines` | CI/CD pipelines | ❌ No - This is for automation |

**The `db2u` namespace** is typically where the actual DB2 database instance runs that Maximo uses.

#### Verify the Correct Namespace

```bash
# Check db2u namespace for Maximo database
oc project db2u

# List DB2 instances
oc get db2ucluster

# You should see something like:
# NAME          STATE   AGE
# db2u-maximo   Ready   30d

# Check for Maximo-related databases
oc get pods | grep db2u

# Look for pods like:
# db2u-maximo-db2u-0
# db2u-maximo-db2u-1
```

#### Quick Validation

```bash
# Switch to db2u namespace
oc project db2u

# Check if Maximo database exists
oc exec -it $(oc get pods | grep db2u | grep -v Completed | head -n 1 | awk '{print $1}') -- su - db2inst1 -c "db2 list db directory" | grep -i max

# If you see MAXDB76 or similar, you're in the right place!
```

#### Set Your Namespace

```bash
# For most Maximo installations with db2u:
MAXIMO_NS="db2u"

# Switch to it
oc project $MAXIMO_NS
```

### Step 4: Find DB2 Secrets

Maximo typically stores DB2 credentials in Kubernetes secrets. Look for secrets with names containing "db2", "database", or "jdbc":

```bash
# List all secrets
oc get secrets

# Filter for DB2-related secrets
oc get secrets | grep -i db2
oc get secrets | grep -i database
oc get secrets | grep -i jdbc

# Common secret names:
# - <instance-id>-jdbc
# - maxinst-db2-secret
# - mas-<instance-id>-db2
# - db2-credentials
```

### Step 5: Extract DB2 Credentials

Once you've identified the secret name, extract the credentials:

```bash
# Set the secret name
SECRET_NAME="<your-db2-secret-name>"

# Get username
oc get secret $SECRET_NAME -o jsonpath='{.data.username}' | base64 -d
echo ""

# Get password
oc get secret $SECRET_NAME -o jsonpath='{.data.password}' | base64 -d
echo ""

# Get database name (if available)
oc get secret $SECRET_NAME -o jsonpath='{.data.database}' | base64 -d
echo ""

# Get all keys in the secret
oc get secret $SECRET_NAME -o jsonpath='{.data}' | jq 'keys'
```

### Step 6: Get DB2 Service Information

Find the DB2 service to get the hostname and port:

```bash
# List services
oc get services | grep -i db2

# Get service details
oc get service <db2-service-name> -o yaml

# Common service names:
# - db2-service
# - <instance-id>-db2
# - maxdb76
```

### Step 7: Get DB2 Connection Details

```bash
# Get DB2 hostname (internal cluster DNS)
oc get service <db2-service-name> -o jsonpath='{.metadata.name}.{.metadata.namespace}.svc.cluster.local'
echo ""

# Get DB2 port
oc get service <db2-service-name> -o jsonpath='{.spec.ports[0].port}'
echo ""

# Example output:
# db2-service.mas-inst1-core.svc.cluster.local
# 50000
```

## Complete Extraction Script

Save this as `get-maximo-db2-creds.sh`:

```bash
#!/bin/bash

# Configuration
NAMESPACE="${1:-mas-inst1-core}"

echo "Extracting DB2 credentials from namespace: $NAMESPACE"
echo "=================================================="

# Switch to namespace
oc project $NAMESPACE

# Find DB2 secret
echo ""
echo "Looking for DB2 secrets..."
DB2_SECRETS=$(oc get secrets | grep -i -E 'db2|jdbc|database' | awk '{print $1}')

if [ -z "$DB2_SECRETS" ]; then
    echo "No DB2 secrets found. Listing all secrets:"
    oc get secrets
    exit 1
fi

echo "Found potential DB2 secrets:"
echo "$DB2_SECRETS"
echo ""

# Use first secret found
SECRET_NAME=$(echo "$DB2_SECRETS" | head -n 1)
echo "Using secret: $SECRET_NAME"
echo ""

# Extract credentials
echo "Extracting credentials..."
echo "------------------------"

USERNAME=$(oc get secret $SECRET_NAME -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)
PASSWORD=$(oc get secret $SECRET_NAME -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
DATABASE=$(oc get secret $SECRET_NAME -o jsonpath='{.data.database}' 2>/dev/null | base64 -d)
DBNAME=$(oc get secret $SECRET_NAME -o jsonpath='{.data.dbname}' 2>/dev/null | base64 -d)

echo "Username: $USERNAME"
echo "Password: $PASSWORD"
echo "Database: ${DATABASE:-$DBNAME}"
echo ""

# Find DB2 service
echo "Looking for DB2 service..."
DB2_SERVICE=$(oc get services | grep -i db2 | head -n 1 | awk '{print $1}')

if [ -z "$DB2_SERVICE" ]; then
    echo "No DB2 service found. Listing all services:"
    oc get services
else
    echo "Found DB2 service: $DB2_SERVICE"
    
    # Get service details
    HOSTNAME="${DB2_SERVICE}.${NAMESPACE}.svc.cluster.local"
    PORT=$(oc get service $DB2_SERVICE -o jsonpath='{.spec.ports[0].port}')
    
    echo ""
    echo "Connection Details:"
    echo "-------------------"
    echo "Hostname: $HOSTNAME"
    echo "Port: $PORT"
    echo "Database: ${DATABASE:-${DBNAME:-MAXDB76}}"
    echo ""
    echo "JDBC URL:"
    echo "jdbc:db2://${HOSTNAME}:${PORT}/${DATABASE:-${DBNAME:-MAXDB76}}"
fi

echo ""
echo "=================================================="
echo "Configuration for connector:"
echo "=================================================="
cat <<EOF
export REGISTRY_URL=quay.io
export REGISTRY_USERNAME=your-username
export REGISTRY_PASSWORD=your-password
export IMAGE_NAME=your-org/maximo-connector
export IMAGE_TAG=latest

# DB2 Configuration
export DB_HOST=$HOSTNAME
export DB_PORT=$PORT
export DB_NAME=${DATABASE:-${DBNAME:-MAXDB76}}
export DB_USERNAME=$USERNAME
export DB_PASSWORD=$PASSWORD
export DB_SCHEMA=MAXIMO
export VIEW_NAME=INCIDENT_VIEW
EOF
```

Make it executable and run:

```bash
chmod +x get-maximo-db2-creds.sh
./get-maximo-db2-creds.sh <maximo-namespace>
```

## Alternative Methods

### Method 1: Check Maximo ConfigMaps

```bash
# List ConfigMaps
oc get configmaps | grep -i maximo

# Check ConfigMap for DB connection info
oc get configmap <maximo-configmap> -o yaml | grep -i db
```

### Method 2: Check Maximo Pod Environment Variables

```bash
# Find Maximo pods
oc get pods | grep -i maximo

# Check environment variables
oc exec <maximo-pod-name> -- env | grep -i db

# Or describe the pod
oc describe pod <maximo-pod-name> | grep -i db
```

### Method 3: Check Maximo Deployment

```bash
# Get deployment
oc get deployment | grep -i maximo

# Check deployment environment
oc get deployment <maximo-deployment> -o yaml | grep -A 10 env
```

## Port Forwarding for Testing

To test the DB2 connection from your local machine:

```bash
# Forward DB2 port to localhost
oc port-forward service/<db2-service-name> 50000:50000

# In another terminal, test connection
# Using db2 client:
db2 connect to MAXDB76 user <username> using <password>

# Or using JDBC test tool
java -cp db2jcc4.jar com.ibm.db2.jcc.DB2Jcc \
  -url jdbc:db2://localhost:50000/MAXDB76 \
  -user <username> \
  -password <password>
```

## Security Considerations

1. **Never commit credentials** to version control
2. **Use OpenShift secrets** for storing credentials in the connector
3. **Rotate credentials** regularly
4. **Use read-only accounts** for the connector
5. **Limit network access** to DB2 using NetworkPolicies

## Creating a Read-Only User

Once you have admin access to DB2, create a dedicated read-only user:

```sql
-- Connect as admin
db2 connect to MAXDB76

-- Create user
db2 "CREATE USER aiops_reader IDENTIFIED BY 'secure_password'"

-- Grant connect
db2 "GRANT CONNECT ON DATABASE TO USER aiops_reader"

-- Grant select on schema
db2 "GRANT SELECT ON SCHEMA MAXIMO TO USER aiops_reader"

-- Grant select on specific view
db2 "GRANT SELECT ON MAXIMO.INCIDENT_VIEW TO USER aiops_reader"
```

## Troubleshooting

### Issue: Cannot find DB2 secret

**Solution:** Check if Maximo uses a different secret structure:

```bash
# List all secrets with details
oc get secrets -o wide

# Check Maximo operator secrets
oc get secrets | grep -i operator

# Check for secrets in related namespaces
oc get secrets -n ibm-common-services | grep -i db2
```

### Issue: Permission denied

**Solution:** Request appropriate RBAC permissions:

```bash
# Check your permissions
oc auth can-i get secrets
oc auth can-i get services

# Request cluster admin to grant permissions
```

### Issue: DB2 not accessible from connector

**Solution:** Check NetworkPolicies and create route if needed:

```bash
# Check NetworkPolicies
oc get networkpolicies

# Create route for external access (if needed)
oc expose service <db2-service-name>
```

## Next Steps

After obtaining credentials:

1. Update your connector configuration with the DB2 details
2. Create the INCIDENT_VIEW in DB2 (see MAXIMO_DB2_VIEW_SETUP.md)
3. Test the connection
4. Deploy the connector

## References

- [OpenShift CLI Documentation](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Maximo Application Suite Documentation](https://www.ibm.com/docs/en/mas)