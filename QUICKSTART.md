# Maximo DB2 Connector - Quick Start Guide

Complete step-by-step guide to set up the Maximo DB2 JDBC connector for IBM AIOps.

## 📋 Prerequisites

- ✅ OpenShift cluster with Maximo installed
- ✅ Access to Maximo's DB2 database namespace
- ✅ IBM AIOps cluster (can be different from Maximo cluster)
- ✅ `oc` CLI installed and configured
- ✅ Podman or Docker installed
- ✅ Container registry account (Docker Hub, Quay.io, etc.)

## 🚀 Complete Setup (6 Steps)

### Step 0: Expose DB2 Externally (5 minutes) - REQUIRED for Cross-Cluster

**If Maximo and AIOps are on different clusters, you MUST expose DB2 externally:**

```bash
# 1. Login to Maximo cluster
oc login https://maximo-cluster.com

# 2. Switch to DB2 namespace
oc project db2u

# 3. Find DB2 service
DB2_SERVICE=$(oc get svc | grep db2u | grep engn-svc | awk '{print $1}')
echo "DB2 Service: $DB2_SERVICE"

# 4. Create external route
oc create route passthrough db2-external \
  --service=$DB2_SERVICE \
  --port=50001

# 5. Get external hostname
oc get route db2-external -o jsonpath='{.spec.host}'
```

**Save the external hostname** - you'll use it in all configurations!

### Step 1: Extract DB2 Credentials (5 minutes)

```bash
# 1. Login to Maximo cluster
oc login https://maximo-cluster.com

# 2. Find DB2 namespace
oc get projects | grep -i db2

# 3. Extract credentials (now includes external route)
./get-maximo-db2-creds.sh db2u

# 4. Copy the output - you'll need it for Step 3
```

**Expected output:**
```bash
Configuration for connector .env file:
=======================================
export DB_HOST=db2-external-db2u.apps.maximo-cluster.com
export DB_PORT=50001
export DB_NAME=BLUDB
export DB_USERNAME=db2inst1
export DB_PASSWORD='your-password'
export DB_SCHEMA=MAXIMO
export VIEW_NAME=INCIDENT_VIEW

JDBC URL for AIOps Integration:
================================
jdbc:db2://db2-external-db2u.apps.maximo-cluster.com:50001/BLUDB:sslConnection=true;

✅ Using external route - works across clusters
```

### Step 2: Create DB2 View in Maximo (10 minutes)

The connector needs a view in DB2 to query incident data.

#### Option A: Using OpenShift Terminal

```bash
# 1. Get DB2 pod name
oc project db2u
DB2_POD=$(oc get pods | grep db2u | grep -v Completed | head -n 1 | awk '{print $1}')

# 2. Connect to DB2
oc exec -it $DB2_POD -- su - db2inst1

# 3. Connect to database
db2 connect to BLUDB  # or MAXDB76, use the DB_NAME from Step 1

# 4. First check what columns exist (IMPORTANT!)
db2 "SELECT COLNAME FROM SYSCAT.COLUMNS WHERE TABSCHEMA = 'MAXIMO' AND TABNAME = 'INCIDENT' ORDER BY COLNAME"

# 5. Create minimal view with only core columns (NO ORDER BY in views!)
db2 "CREATE OR REPLACE VIEW MAXIMO.INCIDENT_VIEW AS SELECT TICKETID, TICKETUID, CLASS, STATUS, DESCRIPTION, REPORTEDBY, OWNER, OWNERGROUP, SITEID, REPORTDATE, STATUSDATE, CHANGEDATE FROM MAXIMO.INCIDENT WHERE HISTORYFLAG = 0"

# 6. After view is created, add more columns based on what exists in your schema
# Run the column check from step 4, then add columns like:
# - AFFECTEDPERSON, ASSETNUM, LOCATION, PRIORITY, EXTERNALSYSTEM, EXTERNALREFID
# Use: DROP VIEW and recreate with additional columns

# 6. Verify the view
db2 "SELECT COUNT(*) FROM MAXIMO.INCIDENT_VIEW"

# 7. Exit
exit
```

#### Option B: Using Port Forward and DB2 Client

```bash
# 1. Forward DB2 port
oc port-forward -n db2u service/db2-service 50000:50000

# 2. In another terminal, connect with DB2 client
db2 connect to BLUDB user db2inst1 using <password>

# 3. Create view (same SQL as above)

# 4. Verify
db2 "SELECT COUNT(*) FROM MAXIMO.INCIDENT_VIEW"
```

### Step 3: Configure the Connector (2 minutes)

```bash
# 1. Update your .env file with credentials from Step 1
nano .env

# Add these lines (use values from Step 1):
export REGISTRY_URL=quay.io
export REGISTRY_USERNAME=your-username
export REGISTRY_PASSWORD=your-password
export IMAGE_NAME=your-org/maximo-connector
export IMAGE_TAG=1.0.0

# DB2 Configuration (from Step 1 - use EXTERNAL hostname!)
export DB_HOST=db2-external-db2u.apps.maximo-cluster.com
export DB_PORT=50001
export DB_NAME=BLUDB
export DB_USERNAME=db2inst1
export DB_PASSWORD='your-db-password'
export DB_SCHEMA=MAXIMO
export VIEW_NAME=INCIDENT_VIEW
```

**⚠️ CRITICAL:** Use the **external route hostname**, not internal service!

**Complete .env example:**
```bash
# Container Registry
export REGISTRY_URL=quay.io
export REGISTRY_USERNAME=jacobdanielrose
export REGISTRY_PASSWORD='your-registry-token'
export IMAGE_NAME=jacobdanielrose/maximo-connector
export IMAGE_TAG=1.0.0

# DB2 Configuration (EXTERNAL hostname for cross-cluster)
export DB_HOST=db2-external-db2u.apps.maximo-cluster.com
export DB_PORT=50001
export DB_NAME=BLUDB
export DB_USERNAME=db2inst1
export DB_PASSWORD='your-db-password'
export DB_SCHEMA=MAXIMO
export VIEW_NAME=INCIDENT_VIEW
```

### Step 4: Build and Push Container Image (10 minutes)

```bash
# Build and push in one command
source .env && ./build-and-push.sh
```

**What happens:**
1. ✅ Builds Java application with Maven (in container)
2. ✅ Creates container image
3. ✅ Pushes to your registry
4. ✅ Tags as latest

**Expected output:**
```bash
[SUCCESS] Maven build completed successfully
[SUCCESS] Container image built successfully
[SUCCESS] Image pushed successfully

Image Details:
  Full Image: quay.io/jacobdanielrose/maximo-connector:1.0.0
```

### Step 5: Deploy to AIOps (15 minutes)

#### A. Update Bundle Manifest

Edit `bundlemanifest.yaml` to use your image:

```yaml
apiVersion: connectors.aiops.ibm.com/v1beta1
kind: BundleManifest
metadata:
  name: maximo-db2-connector
spec:
  images:
    - name: connector
      image: quay.io/jacobdanielrose/maximo-connector:1.0.0  # Your image
```

#### B. Deploy to OpenShift

```bash
# 1. Login to AIOps cluster
oc login https://aiops-cluster.com

# 2. Switch to AIOps namespace
oc project cp4waiops  # or your AIOps namespace

# 3. Apply bundle manifest
oc apply -f bundlemanifest.yaml

# 4. Verify deployment
oc get bundlemanifest | grep maximo
```

#### C. Create Integration in AIOps UI

1. **Open AIOps UI** → Integrations
2. **Click "Add Integration"**
3. **Search for** "Maximo DB2 Connector"
4. **Fill in configuration:**
   - **Name:** Maximo Production
   - **JDBC URL:** `jdbc:db2://db2-external-db2u.apps.maximo-cluster.com:50001/BLUDB:sslConnection=true;`
     - ⚠️ **Use external route hostname from Step 0/1**
   - **Username:** `db2inst1`
   - **Password:** `your-db-password`
   - **Schema:** `MAXIMO`
   - **View Name:** `INCIDENT_VIEW`
   - **Collection Mode:** `live` (or `historical` for initial load)
   - **Sampling Rate:** `5` (minutes)

5. **Test Connection** → Should show success
6. **Save** → Connector starts polling

## ✅ Verification

### Check Connector is Running

```bash
# Get connector pod
oc get pods | grep maximo-connector

# Check logs
oc logs -f <maximo-connector-pod-name>

# Should see:
# [INFO] Successfully connected to DB2 database
# [INFO] Fetching incidents from DB2 view
# [INFO] Successfully fetched X incidents from DB2
```

### Verify Data in AIOps

1. **Go to AIOps UI** → Stories
2. **Check for incidents** from Maximo
3. **Verify incident details** match Maximo data

### Test Historical Data Collection

```bash
# In AIOps UI, edit integration:
# - Change mode to "historical"
# - Set date range (last 90 days)
# - Save

# Check logs for data collection
oc logs -f <connector-pod-name>

# Should see:
# [INFO] Start collecting historical data from DB2
# [INFO] Inserted batch of 100 incidents
# [INFO] Successfully fetched 500 incidents from DB2
```

## 🔧 Troubleshooting

### Issue: Cannot connect to DB2

**Check:**
```bash
# 1. Verify DB2 service exists
oc get service -n db2u | grep db2

# 2. Test connectivity from connector pod
oc exec -it <connector-pod> -- nc -zv db2-service.db2u.svc.cluster.local 50000

# 3. Check credentials
oc exec -it <connector-pod> -- env | grep DB_
```

**Solution:** Verify hostname, port, and credentials in integration config

### Issue: View not found

**Check:**
```bash
# Connect to DB2
oc exec -it <db2-pod> -n db2u -- su - db2inst1 -c "db2 connect to BLUDB"

# List views
oc exec -it <db2-pod> -n db2u -- su - db2inst1 -c "db2 'SELECT VIEWNAME FROM SYSCAT.VIEWS WHERE VIEWSCHEMA='\''MAXIMO'\'''"
```

**Solution:** Create the view (see Step 2)

### Issue: No data being ingested

**Check:**
```bash
# 1. Verify view has data
oc exec -it <db2-pod> -n db2u -- su - db2inst1 -c "db2 'SELECT COUNT(*) FROM MAXIMO.INCIDENT_VIEW'"

# 2. Check connector logs
oc logs <connector-pod> | grep -i error

# 3. Verify date range (for historical mode)
```

**Solution:** Adjust date range or check view query

### Issue: Build fails

**Check:**
```bash
# 1. Verify Maven build
podman run --rm -v $(pwd):/workspace -w /workspace maven:3.9-eclipse-temurin-21 mvn clean compile

# 2. Check dependencies
cat pom.xml | grep db2
```

**Solution:** Ensure DB2 JDBC driver is in pom.xml

## 📚 Additional Resources

- **Full Documentation:** `MAXIMO_CONNECTOR_README.md`
- **DB2 View Setup:** `MAXIMO_DB2_VIEW_SETUP.md`
- **Credential Extraction:** `MAXIMO_OPENSHIFT_DB2_CREDENTIALS.md`
- **Build Guide:** `BUILD_GUIDE.md`

## 🎯 Next Steps

After successful setup:

1. **Train AI Models** - Use historical data for Similar Incident training
2. **Create Policies** - Set up automation rules in AIOps
3. **Monitor Performance** - Check connector metrics and logs
4. **Optimize Queries** - Add indexes to DB2 view if needed

## 💡 Tips

- **Start with historical mode** to load past incidents for AI training
- **Use live mode** for ongoing incident monitoring
- **Set sampling rate** based on incident volume (5-15 minutes typical)
- **Monitor DB2 load** - adjust polling frequency if needed
- **Create read-only user** for production (see MAXIMO_DB2_VIEW_SETUP.md)

## 🆘 Support

If you encounter issues:

1. Check logs: `oc logs <connector-pod>`
2. Verify configuration in AIOps UI
3. Test DB2 connectivity manually
4. Review troubleshooting section above
5. Check documentation files for detailed guides

---

**Estimated Total Time:** 30-45 minutes

**Difficulty:** Intermediate

**Prerequisites:** OpenShift access, DB2 knowledge helpful