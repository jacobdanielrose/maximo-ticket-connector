# Maximo DB2 JDBC Ticket Connector for IBM AIOps

This connector enables IBM AIOps to ingest incident tickets from IBM Maximo using JDBC connectivity to a DB2 view. The connector polls the Maximo database directly, extracting incident information for AI training and real-time incident management.

## Overview

The Maximo DB2 connector provides:

- **Direct database access** to Maximo incident data via JDBC
- **Dual-mode operation**: Historical data collection and live polling
- **Automatic field mapping** from Maximo to AIOps ticket format
- **Batch processing** for efficient data ingestion
- **Flexible configuration** supporting various DB2 connection options

## Architecture

```
┌─────────────────┐
│   IBM AIOps     │
│   Connector     │
└────────┬────────┘
         │ JDBC
         ▼
┌─────────────────┐
│  DB2 Database   │
│  (Maximo)       │
│                 │
│  ┌───────────┐  │
│  │ INCIDENT  │  │
│  │   VIEW    │  │
│  └───────────┘  │
└─────────────────┘
```

## Components

### 1. DB2JdbcHelper
- Manages JDBC connections to DB2
- Handles connection pooling and resource cleanup
- Supports SSL/TLS connections
- Provides query execution utilities

### 2. DB2PollingAction
- Polls the Maximo DB2 view for incidents
- Converts Maximo data to AIOps ticket format
- Supports both historical and live data collection
- Implements batch processing for performance

### 3. Configuration Model
- Extended to support JDBC connection parameters
- Includes DB2-specific settings (host, port, schema, view name)
- Supports SSL configuration

## Prerequisites

1. **Maximo Setup**
   - IBM Maximo 7.6 or higher
   - DB2 database with incident data
   - Database view created (see MAXIMO_DB2_VIEW_SETUP.md)
   - Read-only database user for connector

2. **Network Access**
   - JDBC connectivity from AIOps to Maximo DB2
   - Port 50000 (default DB2 port) accessible
   - Firewall rules configured

3. **AIOps Environment**
   - IBM Cloud Pak for AIOps 4.3 or higher
   - Connector framework deployed
   - Sufficient resources for connector pod

## Installation

### Step 1: Create DB2 View in Maximo

Follow the instructions in `MAXIMO_DB2_VIEW_SETUP.md` to:
1. Create the INCIDENT_VIEW in your Maximo database
2. Grant appropriate permissions
3. Create indexes for performance

### Step 2: Build the Connector

```bash
# Build the connector
mvn clean package

# Build Docker image
docker build -t maximo-connector:latest -f container/Dockerfile .
```

### Step 3: Deploy to AIOps

```bash
# Apply the bundle manifest
oc apply -f bundlemanifest.yaml

# Verify deployment
oc get bundlemanifest | grep maximo
```

## Configuration

### Basic Configuration

```json
{
  "jdbcUrl": "jdbc:db2://maximo-host:50000/MAXDB76",
  "dbHost": "maximo-host",
  "dbPort": "50000",
  "dbName": "MAXDB76",
  "dbSchema": "MAXIMO",
  "viewName": "INCIDENT_VIEW",
  "username": "aiops_connector",
  "password": "your_secure_password",
  "collectionMode": "live",
  "issueSamplingRate": 5
}
```

### Configuration Parameters

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| jdbcUrl | No* | Full JDBC connection URL | Constructed from components |
| dbHost | Yes* | Database hostname | - |
| dbPort | No | Database port | 50000 |
| dbName | Yes* | Database name | MAXDB76 |
| dbSchema | No | Schema name | MAXIMO |
| viewName | No | View name to query | INCIDENT_VIEW |
| username | Yes | Database username | - |
| password | Yes | Database password | - |
| useSSL | No | Enable SSL connection | false |
| collectionMode | Yes | "historical" or "live" | live |
| issueSamplingRate | No | Polling interval (minutes) | 5 |
| start | No** | Historical start time (epoch ms) | - |
| end | No** | Historical end time (epoch ms) | - |

\* Either provide `jdbcUrl` OR (`dbHost` + `dbName`)  
\** Required for historical mode

### SSL Configuration

For secure connections:

```json
{
  "jdbcUrl": "jdbc:db2://maximo-host:50000/MAXDB76:sslConnection=true;",
  "useSSL": true,
  "sslTrustStore": "/path/to/truststore.jks",
  "sslTrustStorePassword": "truststore_password"
}
```

## Usage

### Historical Data Collection

Collect historical incidents for AI training:

```json
{
  "collectionMode": "historical",
  "start": 1609459200000,
  "end": 1640995200000,
  "issueSamplingRate": 0
}
```

This will:
1. Query all incidents within the date range
2. Process in batches of 100
3. Insert into Elasticsearch for AI training
4. Generate completion alert

### Live Data Polling

Continuously monitor for new/updated incidents:

```json
{
  "collectionMode": "live",
  "issueSamplingRate": 5
}
```

This will:
1. Poll every 5 minutes
2. Fetch incidents modified since last poll
3. Emit to AIOps for real-time processing
4. Update incident status in AIOps

## Field Mapping

| Maximo Field | AIOps Field | Description |
|--------------|-------------|-------------|
| TICKETID | number | Incident number |
| TICKETUID | sys_id | Unique identifier |
| STATUS | state | Incident state |
| DESCRIPTION | short_description | Brief description |
| DESCRIPTION_LONGDESCRIPTION | description | Detailed description |
| REPORTEDBY | opened_by | Reporter |
| OWNER | assigned_to | Current owner |
| OWNERGROUP | business_service | Owning group |
| REPORTDATE | sys_created_on | Creation date |
| CHANGEDATE | sys_updated_on | Last update |
| STATUSDATE | closed_at | Closure date |
| PRIORITY | impact | Priority level |
| CLASSSTRUCTUREID | type | Classification |
| FAILURECODE | reason | Failure code |

### Status Mapping

| Maximo Status | AIOps State |
|---------------|-------------|
| NEW, REPORTED | Open |
| INPROG, QUEUED, PENDING | In Progress |
| CLOSED, RESOLVED, COMP, COMPLETED | Closed |
| CANCELLED, CANCEL | Cancelled |

## Monitoring

### Metrics

The connector exposes the following metrics:

- `ticket.maximo.issue.poll.action` - Successful polls
- `ticket.maximo.issue.poll.action.error` - Failed polls
- `ticket.maximo.issue.action.action` - Successful actions
- `ticket.maximo.issue.action.error` - Failed actions

### Logs

Monitor connector logs:

```bash
# Get connector pod name
oc get pods | grep maximo-connector

# View logs
oc logs -f <pod-name>

# Search for errors
oc logs <pod-name> | grep ERROR
```

### Health Checks

The connector provides health endpoints:

- `/health/live` - Liveness probe
- `/health/ready` - Readiness probe

## Troubleshooting

### Connection Issues

**Problem**: Cannot connect to DB2 database

**Solutions**:
1. Verify network connectivity: `telnet maximo-host 50000`
2. Check credentials: Test with DB2 client
3. Verify firewall rules
4. Check SSL configuration if enabled

```bash
# Test connection from connector pod
oc exec -it <pod-name> -- bash
curl -v telnet://maximo-host:50000
```

### No Data Retrieved

**Problem**: Connector runs but no incidents are ingested

**Solutions**:
1. Verify view exists and has data:
   ```sql
   SELECT COUNT(*) FROM MAXIMO.INCIDENT_VIEW;
   ```
2. Check date range for historical mode
3. Verify user permissions on view
4. Check connector logs for SQL errors

### Performance Issues

**Problem**: Slow data ingestion

**Solutions**:
1. Create indexes on REPORTDATE and CHANGEDATE
2. Reduce batch size in code
3. Increase connector resources
4. Optimize view query

```yaml
# Increase resources in deployment.yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

### SSL/TLS Errors

**Problem**: SSL handshake failures

**Solutions**:
1. Import DB2 certificate into truststore
2. Verify SSL is enabled on DB2
3. Check certificate validity
4. Update JDBC URL with SSL parameters

## Testing

### Unit Tests

```bash
# Run unit tests
mvn test

# Run with coverage
mvn test jacoco:report
```

### Integration Testing

1. **Test Database Connection**:
   ```java
   DB2JdbcHelper helper = new DB2JdbcHelper(config);
   boolean connected = helper.testConnection();
   ```

2. **Test Query Execution**:
   ```sql
   SELECT * FROM MAXIMO.INCIDENT_VIEW 
   WHERE REPORTDATE >= CURRENT_TIMESTAMP - 1 DAY
   FETCH FIRST 10 ROWS ONLY;
   ```

3. **Test Data Ingestion**:
   - Configure historical mode with small date range
   - Verify incidents appear in AIOps
   - Check Elasticsearch indices

## Best Practices

1. **Security**
   - Use read-only database user
   - Enable SSL for production
   - Rotate passwords regularly
   - Store credentials in secrets

2. **Performance**
   - Create appropriate indexes
   - Use reasonable polling intervals (5-15 minutes)
   - Monitor database load
   - Implement connection pooling

3. **Reliability**
   - Set up monitoring and alerts
   - Configure resource limits
   - Implement retry logic
   - Handle connection failures gracefully

4. **Maintenance**
   - Regular database statistics updates
   - Monitor view performance
   - Archive old data
   - Review and optimize queries

## Advanced Configuration

### Custom View

Create a custom view with additional fields:

```sql
CREATE VIEW MAXIMO.CUSTOM_INCIDENT_VIEW AS
SELECT 
    I.*,
    A.DESCRIPTION AS ASSET_DESC,
    L.DESCRIPTION AS LOCATION_DESC
FROM MAXIMO.INCIDENT I
LEFT JOIN MAXIMO.ASSET A ON I.ASSETNUM = A.ASSETNUM
LEFT JOIN MAXIMO.LOCATIONS L ON I.LOCATION = L.LOCATION
WHERE I.HISTORYFLAG = 0;
```

Update configuration:
```json
{
  "viewName": "CUSTOM_INCIDENT_VIEW"
}
```

### Multiple Maximo Instances

Deploy separate connectors for each instance:

```bash
# Instance 1
oc apply -f bundlemanifest-prod.yaml

# Instance 2
oc apply -f bundlemanifest-test.yaml
```

## Support

For issues and questions:

1. Check logs: `oc logs <pod-name>`
2. Review documentation: `MAXIMO_DB2_VIEW_SETUP.md`
3. Verify configuration
4. Contact IBM Support with:
   - Connector version
   - Error messages
   - Configuration (sanitized)
   - Relevant logs

## References

- [IBM Maximo Documentation](https://www.ibm.com/docs/en/mam)
- [DB2 JDBC Driver Documentation](https://www.ibm.com/docs/en/db2/11.5)
- [IBM AIOps Connector SDK](https://www.ibm.com/docs/en/cloud-paks/cloud-pak-aiops)
- [Maximo Database Schema](https://www.ibm.com/docs/en/mam/7.6.1)

## License

See LICENSE file for details.

## Version History

- **1.0.0** - Initial release with DB2 JDBC support
  - Historical and live data collection
  - SSL support
  - Batch processing
  - Comprehensive field mapping