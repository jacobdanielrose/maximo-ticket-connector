# Maximo DB2 Connector - Complete Deployment Guide

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] OpenShift CLI (`oc`) installed and logged in
- [ ] Access to IBM AIOps namespace
- [ ] Access to DB2 namespace (`db2u`)
- [ ] Quay.io account (or other container registry)
- [ ] Maven installed (or use containerized build)
- [ ] Podman or Docker installed

## Step 1: Get DB2 Credentials (5 minutes)

### 1.1 Extract DB2 Connection Details

```bash
# Run the credential extraction script
./get-maximo-db2-creds.sh db2u
```

**Save these values - you'll need them later:**
- DB_HOST (e.g., `c-mas-dev-system-db2u-engn-svc.db2u.svc`)
- DB_PORT (e.g., `50001`)
- DB_NAME (e.g., `BLUDB`)
- DB_USER (e.g., `db2inst1`)
- DB_PASSWORD (the password shown)

## Step 2: Create DB2 View (10 minutes)

### 2.1 Connect to DB2 Pod

```bash
# Switch to DB2 namespace
oc project db2u

# Get DB2 pod name
DB2_POD=$(oc get pods | grep db2u | grep -v Completed | grep Running | head -n 1 | awk '{print $1}')
echo "DB2 Pod: $DB2_POD"

# Connect to DB2
oc exec -it $DB2_POD -- su - db2inst1
```

### 2.2 Create the View

```bash
# Connect to database (use DB_NAME from Step 1)
db2 connect to BLUDB

# Create the view (single line, copy-paste this)
db2 "CREATE OR REPLACE VIEW MAXIMO.INCIDENT_VIEW AS SELECT TICKETID, TICKETUID, CLASS, STATUS, DESCRIPTION, REPORTEDBY, OWNER, OWNERGROUP, SITEID, ORGID, REPORTDATE, STATUSDATE, CHANGEDATE FROM MAXIMO.INCIDENT WHERE HISTORYFLAG = 0"

# Verify
db2 "SELECT COUNT(*) FROM MAXIMO.INCIDENT_VIEW"

# Exit
exit
```

## Step 3: Create Demo Incidents (Optional, 5 minutes)

```bash
# Make script executable
chmod +x create-100-incidents.sh

# Create 100 demo incidents
./create-100-incidents.sh db2u BLUDB
```

**Wait for completion** - you should see "Successfully created 100 demo incidents"

## Step 4: Configure Environment (2 minutes)

### 4.1 Create .env File

```bash
# Copy example
cp .env.example .env

# Edit with your values
nano .env
```

### 4.2 Fill in These Values:

```bash
# Container Registry
export REGISTRY_URL=quay.io
export REGISTRY_USERNAME=jacobdanielrose
export REGISTRY_PASSWORD=<your-quay-password>
export IMAGE_NAME=jacobdanielrose/maximo-ticket-connector
export IMAGE_TAG=latest

# DB2 Connection (from Step 1)
export DB_HOST=c-mas-dev-system-db2u-engn-svc.db2u.svc
export DB_PORT=50001
export DB_NAME=BLUDB
export DB_USER=db2inst1
export DB_PASSWORD=<your-db2-password>
export DB_SCHEMA=MAXIMO
export VIEW_NAME=INCIDENT_VIEW
```

Save and exit (Ctrl+X, Y, Enter)

## Step 5: Build Container Image (10 minutes)

```bash
# Source environment variables
source .env

# Build and push image
./build-and-push.sh
```

**Expected output:**
- Maven build successful
- Container image built
- Image pushed to quay.io/jacobdanielrose/maximo-ticket-connector:latest

**Verify:**
```bash
# Check image exists in registry
# Go to https://quay.io/repository/jacobdanielrose/maximo-ticket-connector
```

## Step 6: Deploy to OpenShift (5 minutes)

### 6.1 Switch to AIOps Namespace

```bash
# Find your AIOps namespace
oc get namespaces | grep aiops

# Switch to it (replace with your namespace)
oc project ibm-aiops
```

### 6.2 Clean Up Any Existing Deployment

```bash
# Delete old resources if they exist
oc delete bundlemanifest ticket-template 2>/dev/null || true
oc delete deployment ticket-template 2>/dev/null || true
oc delete connectorschema ticket-template 2>/dev/null || true
oc delete microedgeconfiguration ticket-template 2>/dev/null || true
```

### 6.3 Deploy Prerequisites

```bash
# Deploy connector schema and configuration
oc apply -f bundle-artifacts/prereqs/connectorschema.yaml
oc apply -f bundle-artifacts/prereqs/microedgeconfiguration.yaml
oc apply -f bundle-artifacts/prereqs/topics.yaml

# Wait for resources to be created
sleep 5

# Verify
oc get connectorschema ticket-template
oc get microedgeconfiguration ticket-template
```

### 6.4 Deploy Connector

```bash
# Deploy using kustomize
oc apply -k bundle-artifacts/connector/

# Check deployment
oc get deployment ticket-template
oc get pods -l app=ticket-template
```

**Expected output:**
- Deployment created
- Pod in "Pending" or "Init:0/1" state (waiting for integration to be created)

## Step 7: Create Integration in AIOps UI (5 minutes)

### 7.1 Access AIOps Console

1. Open IBM AIOps console in browser
2. Log in with your credentials

### 7.2 Navigate to Integrations

1. Click **Integrations** in left menu
2. Click **Available Integrations** tab
3. Search for **"Ticket Template"** or **"ticket-template"**

**If you don't see it:**
- Wait 2-3 minutes
- Hard refresh browser (Ctrl+Shift+R)
- Check connector-manager pod: `oc get pods | grep connector-manager`
- Restart connector-manager: `oc delete pod -l app=connector-manager`

### 7.3 Create Integration Instance

1. Click **"Add Integration"** on the Ticket Template card
2. Fill in the form:

**Connection Details:**
- **Name**: `Maximo DB2 Connector`
- **Description**: `Connects to Maximo DB2 to ingest incidents`
- **JDBC URL**: `jdbc:db2://c-mas-dev-system-db2u-engn-svc.db2u.svc:50001/BLUDB:sslConnection=true;`
- **Database Username**: `db2inst1`
- **Database Password**: `<your-db2-password>`
- **Database Schema**: `MAXIMO`
- **View Name**: `INCIDENT_VIEW`

**Deployment Type:**
- Select **"Local"** (runs in AIOps cluster)

**Data Collection** (if shown):
- Toggle **ON**
- Mode: **"Live"**
- Sampling Rate: `1` minute

3. Click **"Test Connection"** (if available)
4. Click **"Save"** or **"Create"**

## Step 8: Verify Deployment (5 minutes)

### 8.1 Check Pod Status

```bash
# Get pod name
POD=$(oc get pods -l app=ticket-template -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD"

# Check status
oc get pod $POD

# Should show: Running (1/1)
```

### 8.2 View Logs

```bash
# Follow logs
oc logs -f $POD

# Look for:
# - "Connected to DB2"
# - "Polling MAXIMO.INCIDENT_VIEW"
# - "Found X incidents"
# - "Inserted X tickets"
```

### 8.3 Check in AIOps UI

1. Go to **Integrations** → **Configured Integrations**
2. Find your **"Maximo DB2 Connector"**
3. Status should be **"Connected"** or **"Active"**
4. Click to view details and metrics

### 8.4 Verify Incidents Ingested

1. Go to **Incidents** or **Alerts** in AIOps
2. Look for incidents from Maximo
3. Should see your 100 demo incidents (if you created them)

## Troubleshooting

### Pod Stuck in Init:0/1

**Cause:** Missing connector secret

**Solution:**
```bash
# Check for secret
oc get secret | grep connector

# If missing, integration wasn't created properly
# Delete pod and recreate integration in UI
oc delete pod $POD
```

### Pod CrashLoopBackOff

**Cause:** Application error

**Solution:**
```bash
# Check logs
oc logs $POD

# Common issues:
# - Can't connect to DB2 (check credentials)
# - View doesn't exist (check Step 2)
# - Missing permissions (check DB2 grants)
```

### Integration Not Showing in UI

**Cause:** ConnectorSchema not registered

**Solution:**
```bash
# Check schema exists
oc get connectorschema ticket-template

# Restart connector-manager
oc delete pod -l app=connector-manager

# Wait 2 minutes, hard refresh browser
```

### No Incidents Appearing

**Cause:** View is empty or connector not polling

**Solution:**
```bash
# Check view has data
oc exec -it $DB2_POD -- su - db2inst1 -c "db2 'CONNECT TO BLUDB; SELECT COUNT(*) FROM MAXIMO.INCIDENT_VIEW'"

# Check connector logs
oc logs $POD | grep -i incident

# Verify polling is enabled in integration config
```

## Success Criteria

✅ DB2 view created and contains incidents
✅ Container image built and pushed to registry
✅ Connector deployed and pod running
✅ Integration created in AIOps UI
✅ Incidents appearing in AIOps
✅ Connector logs show successful polling

## Next Steps

After successful deployment:

1. **Configure Policies** - Set up incident routing and notifications
2. **Test Updates** - Modify incidents in Maximo, verify sync
3. **Monitor Performance** - Check connector metrics and logs
4. **Adjust Polling** - Tune sampling rate based on load
5. **Production Deployment** - Move from demo to production data

## Support

If you encounter issues:

1. Check logs: `oc logs -f $POD`
2. Review this guide from the beginning
3. Contact IBM AIOps support with:
   - Pod logs
   - ConnectorSchema YAML
   - Integration configuration
   - Error messages

## Quick Reference

```bash
# View connector status
oc get pods -l app=ticket-template
oc logs -f deployment/ticket-template

# View DB2 data
oc exec -it $DB2_POD -- su - db2inst1 -c "db2 'CONNECT TO BLUDB; SELECT COUNT(*) FROM MAXIMO.INCIDENT_VIEW'"

# Restart connector
oc delete pod -l app=ticket-template

# Update configuration
# Edit integration in AIOps UI, save changes
# Pod will restart automatically

# View all connector resources
oc get connectorschema,microedgeconfiguration,deployment,pod -l app=ticket-template