# Cross-Cluster DB2 Access Setup Guide

## Overview

This guide explains how to expose Maximo DB2 externally so that IBM AIOps running on a **different OpenShift cluster** can connect to it via JDBC.

## Architecture

```
┌─────────────────────────────┐         ┌─────────────────────────────┐
│   Maximo Cluster            │         │   AIOps Cluster             │
│                             │         │                             │
│  ┌──────────────────────┐   │         │  ┌──────────────────────┐   │
│  │  DB2 Pod             │   │         │  │  Connector Pod       │   │
│  │  (db2u namespace)    │   │         │  │  (aiops namespace)   │   │
│  └──────────┬───────────┘   │         │  └──────────┬───────────┘   │
│             │               │         │             │               │
│  ┌──────────▼───────────┐   │         │             │               │
│  │  DB2 Service         │   │         │             │               │
│  │  (internal)          │   │         │             │               │
│  └──────────┬───────────┘   │         │             │               │
│             │               │         │             │               │
│  ┌──────────▼───────────┐   │         │             │               │
│  │  OpenShift Route     │◄──┼─────────┼─────────────┘               │
│  │  (external)          │   │  HTTPS  │                             │
│  └──────────────────────┘   │  SSL    │                             │
│                             │         │                             │
└─────────────────────────────┘         └─────────────────────────────┘
         Internet/VPN                           Internet/VPN
```

## Why External Route is Needed

**Internal Service URLs** (e.g., `db2-service.db2u.svc.cluster.local`) only work **within the same OpenShift cluster**. They use Kubernetes internal DNS and are not routable from outside.

**External Routes** expose services via the OpenShift router, making them accessible from:
- Other OpenShift clusters
- External applications
- Developer workstations
- CI/CD pipelines

## Step-by-Step Setup

### 1. Login to Maximo Cluster

```bash
# Login to the cluster where Maximo/DB2 is running
oc login https://api.maximo-cluster.example.com:6443

# Verify you're on the right cluster
oc cluster-info
```

### 2. Switch to DB2 Namespace

```bash
# Find DB2 namespace
oc get projects | grep -E 'db2|maximo'

# Switch to it (commonly 'db2u' or 'mas-*-core')
oc project db2u
```

### 3. Identify DB2 Service

```bash
# List all services
oc get svc

# Find DB2 service (look for db2u in the name)
DB2_SERVICE=$(oc get svc | grep db2u | grep engn-svc | awk '{print $1}')
echo "DB2 Service: $DB2_SERVICE"

# Get service details
oc describe svc $DB2_SERVICE
```

**Example output:**
```
Name:              c-mas-dev-system-db2u-engn-svc
Namespace:         db2u
Type:              ClusterIP
Port:              db2-server  50001/TCP
```

### 4. Create Passthrough Route

**Passthrough route** preserves SSL/TLS encryption end-to-end (recommended for security).

```bash
# Create the route
oc create route passthrough db2-external \
  --service=$DB2_SERVICE \
  --port=50001

# Verify route was created
oc get route db2-external

# Get the external hostname
EXTERNAL_HOST=$(oc get route db2-external -o jsonpath='{.spec.host}')
echo "External DB2 URL: $EXTERNAL_HOST"
```

**Example output:**
```
NAME           HOST/PORT                                          PATH   SERVICES                        PORT    TERMINATION   WILDCARD
db2-external   db2-external-db2u.apps.maximo-cluster.example.com         c-mas-dev-system-db2u-engn-svc  50001   passthrough   None
```

### 5. Test Connectivity

#### From Local Machine

```bash
# Test if route is accessible
curl -k https://$EXTERNAL_HOST:443

# Test DB2 port (should timeout or refuse, but proves routing works)
nc -zv $EXTERNAL_HOST 443
```

#### From AIOps Cluster

```bash
# Login to AIOps cluster
oc login https://api.aiops-cluster.example.com:6443

# Create test pod
oc run test-db2 --image=busybox --rm -it --restart=Never -- sh

# Inside the pod, test connectivity
nc -zv db2-external-db2u.apps.maximo-cluster.example.com 443
```

### 6. Update Connector Configuration

Use the **external hostname** in your JDBC URL:

```
jdbc:db2://db2-external-db2u.apps.maximo-cluster.example.com:50001/BLUDB:sslConnection=true;
```

**NOT** the internal service name:
```
❌ jdbc:db2://c-mas-dev-system-db2u-engn-svc.db2u.svc:50001/BLUDB
```

## Route Types Comparison

### Passthrough Route (Recommended)

```bash
oc create route passthrough db2-external \
  --service=$DB2_SERVICE \
  --port=50001
```

**Pros:**
- ✅ End-to-end SSL encryption
- ✅ DB2's SSL certificate is used
- ✅ Most secure option
- ✅ No certificate management needed

**Cons:**
- ⚠️ Requires DB2 to have SSL enabled (usually is)

### Edge Route (Alternative)

```bash
oc create route edge db2-external \
  --service=$DB2_SERVICE \
  --port=50001
```

**Pros:**
- ✅ OpenShift manages SSL certificate
- ✅ Works even if DB2 doesn't have SSL

**Cons:**
- ⚠️ SSL terminates at router, not DB2
- ⚠️ Less secure (traffic unencrypted between router and DB2)

### Re-encrypt Route (Most Secure)

```bash
oc create route reencrypt db2-external \
  --service=$DB2_SERVICE \
  --port=50001 \
  --dest-ca-cert=/path/to/db2-ca.crt
```

**Pros:**
- ✅ SSL at router AND to DB2
- ✅ Most secure option
- ✅ OpenShift manages external certificate

**Cons:**
- ⚠️ Requires DB2 CA certificate
- ⚠️ More complex setup

## Security Considerations

### 1. Network Policies

Restrict access to DB2 route:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-db2-from-aiops
  namespace: db2u
spec:
  podSelector:
    matchLabels:
      app: db2u
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: aiops-namespace
    ports:
    - protocol: TCP
      port: 50001
```

### 2. Firewall Rules

If clusters are in different networks, configure firewall:

```bash
# Allow AIOps cluster IP range to access Maximo cluster
# Example: Allow 10.20.0.0/16 to access 10.10.0.0/16 on port 443
```

### 3. SSL Certificate Validation

Ensure connector validates SSL certificates:

```
jdbc:db2://db2-external.example.com:50001/BLUDB:sslConnection=true;sslTrustStoreLocation=/path/to/truststore.jks;
```

### 4. Database User Permissions

Create read-only user for connector:

```sql
-- Connect to DB2
db2 connect to BLUDB

-- Create read-only user
CREATE USER aiops_reader IDENTIFIED BY 'secure_password';

-- Grant only SELECT on view
GRANT SELECT ON MAXIMO.INCIDENT_VIEW TO aiops_reader;
GRANT CONNECT ON DATABASE TO aiops_reader;

-- Verify permissions
SELECT * FROM SYSCAT.TABAUTH WHERE GRANTEE = 'AIOPS_READER';
```

## Troubleshooting

### Route Not Accessible

```bash
# Check route status
oc get route db2-external -o yaml

# Check router pods
oc get pods -n openshift-ingress

# Check route logs
oc logs -n openshift-ingress -l app=router
```

### SSL Certificate Issues

```bash
# Get route certificate
openssl s_client -connect $EXTERNAL_HOST:443 -showcerts

# Check DB2 SSL configuration
oc exec -it $DB2_POD -- su - db2inst1 -c "db2 get dbm cfg | grep SSL"
```

### Connection Timeout

```bash
# Check if route is in correct namespace
oc get route -A | grep db2

# Verify service endpoints
oc get endpoints $DB2_SERVICE

# Check DB2 pod is running
oc get pods | grep db2
```

### DNS Resolution Issues

```bash
# Test DNS from AIOps cluster
oc run test-dns --image=busybox --rm -it --restart=Never -- nslookup $EXTERNAL_HOST

# Check if hostname resolves
dig $EXTERNAL_HOST
```

## Monitoring and Maintenance

### Check Route Health

```bash
# Monitor route traffic
oc get route db2-external -w

# Check route metrics (if monitoring enabled)
oc get --raw /apis/route.openshift.io/v1/namespaces/db2u/routes/db2-external/status
```

### Update Route

```bash
# Delete old route
oc delete route db2-external

# Create new route with updated configuration
oc create route passthrough db2-external \
  --service=$DB2_SERVICE \
  --port=50001 \
  --hostname=custom-db2.example.com
```

### Backup Route Configuration

```bash
# Export route configuration
oc get route db2-external -o yaml > db2-route-backup.yaml

# Restore if needed
oc apply -f db2-route-backup.yaml
```

## Alternative: LoadBalancer Service

If routes don't work, use LoadBalancer service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: db2-external-lb
  namespace: db2u
spec:
  type: LoadBalancer
  ports:
  - port: 50001
    targetPort: 50001
    protocol: TCP
  selector:
    app: db2u
```

```bash
# Apply configuration
oc apply -f db2-loadbalancer.yaml

# Get external IP
oc get svc db2-external-lb
```

## Summary Checklist

- [ ] Logged into Maximo cluster
- [ ] Identified DB2 service and port
- [ ] Created passthrough route
- [ ] Verified route is accessible
- [ ] Updated connector configuration with external hostname
- [ ] Tested connectivity from AIOps cluster
- [ ] Configured security (network policies, firewall)
- [ ] Created read-only database user
- [ ] Documented external hostname for team

## Next Steps

After exposing DB2:

1. Update `get-maximo-db2-creds.sh` output with external hostname
2. Configure connector with external JDBC URL
3. Test connection from AIOps cluster
4. Monitor route performance and security
5. Set up alerts for route availability

## Support

For issues:
- Check OpenShift router logs: `oc logs -n openshift-ingress -l app=router`
- Verify DB2 SSL configuration
- Test connectivity with `curl` and `nc`
- Review firewall rules between clusters
- Contact OpenShift support for route issues