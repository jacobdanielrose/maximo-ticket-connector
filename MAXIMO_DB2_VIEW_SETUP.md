# Maximo DB2 View Setup for AIOps Integration

This document provides instructions for creating a DB2 view in Maximo that exposes incident data for ingestion into IBM AIOps.

## Overview

The connector uses JDBC to connect to a DB2 view that consolidates incident information from Maximo's incident management tables. This approach provides:

- **Read-only access** to Maximo data
- **Simplified data model** for AIOps consumption
- **Performance optimization** through indexed views
- **Security** through database-level access control

## Prerequisites

- Maximo 7.6 or higher with DB2 database
- Database administrator access to create views
- JDBC connectivity from AIOps environment to Maximo DB2

## Step 1: Create the Incident View

Connect to your Maximo DB2 database and execute the following SQL to create the incident view:

**STEP 1: Check what columns exist in your INCIDENT table:**

```sql
SELECT COLNAME, TYPENAME, LENGTH FROM SYSCAT.COLUMNS WHERE TABSCHEMA = 'MAXIMO' AND TABNAME = 'INCIDENT' ORDER BY COLNAME;
```

**STEP 2: Create minimal view with guaranteed core columns (NO ORDER BY - views can't have it!):**

```sql
CREATE OR REPLACE VIEW MAXIMO.INCIDENT_VIEW AS SELECT TICKETID, TICKETUID, CLASS, STATUS, DESCRIPTION, REPORTEDBY, OWNER, OWNERGROUP, SITEID, REPORTDATE, STATUSDATE, CHANGEDATE FROM MAXIMO.INCIDENT WHERE HISTORYFLAG = 0;
```

**STEP 3: Verify the view works:**

```sql
SELECT COUNT(*) FROM MAXIMO.INCIDENT_VIEW;
SELECT * FROM MAXIMO.INCIDENT_VIEW ORDER BY REPORTDATE DESC FETCH FIRST 5 ROWS ONLY;
```

**STEP 4: Add optional columns based on your schema:**

After confirming the minimal view works, you can add more columns. Common optional columns:
- `AFFECTEDPERSON` - Affected user
- `ORGID` - Organization ID
- `ASSETNUM` - Asset number
- `LOCATION` - Location code
- `PRIORITY` - Priority level
- `REPORTEDPRIORITY` - Reported priority
- `EXTERNALSYSTEM` - External system name
- `EXTERNALREFID` - External reference ID
- `CLASSSTRUCTUREID` - Classification structure
- `FAILURECODE` - Failure code

To add columns, drop and recreate the view:

```sql
DROP VIEW MAXIMO.INCIDENT_VIEW;
CREATE OR REPLACE VIEW MAXIMO.INCIDENT_VIEW AS SELECT TICKETID, TICKETUID, CLASS, STATUS, DESCRIPTION, REPORTEDBY, OWNER, OWNERGROUP, SITEID, REPORTDATE, STATUSDATE, CHANGEDATE, AFFECTEDPERSON, PRIORITY FROM MAXIMO.INCIDENT WHERE HISTORYFLAG = 0;
```

**Alternative: Query to generate the CREATE VIEW statement automatically:**

```sql
SELECT 'CREATE OR REPLACE VIEW MAXIMO.INCIDENT_VIEW AS SELECT ' || LISTAGG(COLNAME, ', ') WITHIN GROUP (ORDER BY COLNO) || ' FROM MAXIMO.INCIDENT WHERE HISTORYFLAG = 0;' AS CREATE_STATEMENT FROM SYSCAT.COLUMNS WHERE TABSCHEMA = 'MAXIMO' AND TABNAME = 'INCIDENT' AND COLNAME IN ('TICKETID', 'TICKETUID', 'CLASS', 'STATUS', 'DESCRIPTION', 'REPORTEDBY', 'OWNER', 'OWNERGROUP', 'SITEID', 'REPORTDATE', 'STATUSDATE', 'CHANGEDATE');
```

## Step 2: Grant Access Permissions

Create a dedicated database user for the AIOps connector and grant read-only access:

```sql
-- Create user for AIOps connector (if not exists)
-- Note: Adjust authentication method based on your security requirements
CREATE USER AIOPS_CONNECTOR IDENTIFIED BY 'your_secure_password';

-- Grant SELECT permission on the view
GRANT SELECT ON MAXIMO.INCIDENT_VIEW TO AIOPS_CONNECTOR;

-- Grant CONNECT privilege
GRANT CONNECT ON DATABASE TO AIOPS_CONNECTOR;
```

## Step 3: Create Indexes for Performance (Optional but Recommended)

To optimize query performance, especially for date-range queries:

```sql
-- Index on REPORTDATE for historical data collection
CREATE INDEX MAXIMO.IDX_INCIDENT_REPORTDATE 
ON MAXIMO.INCIDENT(REPORTDATE DESC) 
WHERE HISTORYFLAG = 0;

-- Index on CHANGEDATE for live data polling
CREATE INDEX MAXIMO.IDX_INCIDENT_CHANGEDATE 
ON MAXIMO.INCIDENT(CHANGEDATE DESC) 
WHERE HISTORYFLAG = 0;

-- Index on STATUS for filtering
CREATE INDEX MAXIMO.IDX_INCIDENT_STATUS 
ON MAXIMO.INCIDENT(STATUS) 
WHERE HISTORYFLAG = 0;
```

## Step 4: Verify the View

Test the view to ensure it returns data correctly:

```sql
-- Test query to verify view
SELECT COUNT(*) as TOTAL_INCIDENTS
FROM MAXIMO.INCIDENT_VIEW;

-- Sample recent incidents
SELECT 
    TICKETID,
    STATUS,
    DESCRIPTION,
    REPORTEDBY,
    REPORTDATE
FROM MAXIMO.INCIDENT_VIEW
WHERE REPORTDATE >= CURRENT_TIMESTAMP - 7 DAYS
ORDER BY REPORTDATE DESC
FETCH FIRST 10 ROWS ONLY;
```

## Alternative View Configurations

### Option 1: Include Work Log Information

If you need to include work log/comments:

```sql
CREATE OR REPLACE VIEW MAXIMO.INCIDENT_VIEW_WITH_WORKLOG AS
SELECT 
    I.*,
    WL.DESCRIPTION AS WORKLOG_DESCRIPTION,
    WL.CREATEDATE AS WORKLOG_DATE,
    WL.CREATEBY AS WORKLOG_AUTHOR
FROM MAXIMO.INCIDENT_VIEW I
LEFT JOIN MAXIMO.WORKLOG WL ON I.TICKETID = WL.RECORDKEY
    AND WL.CLASS = 'INCIDENT'
    AND WL.LOGTYPE = 'CLIENTNOTE';
```

### Option 2: Include Related CI/Asset Details

If you need configuration item details:

```sql
CREATE OR REPLACE VIEW MAXIMO.INCIDENT_VIEW_WITH_CI AS
SELECT 
    I.*,
    A.ASSETNUM AS CI_ASSETNUM,
    A.DESCRIPTION AS CI_DESCRIPTION,
    A.STATUS AS CI_STATUS,
    A.SERIALNUM AS CI_SERIALNUM,
    L.LOCATION AS CI_LOCATION,
    L.DESCRIPTION AS CI_LOCATION_DESC
FROM MAXIMO.INCIDENT_VIEW I
LEFT JOIN MAXIMO.ASSET A ON I.ASSETNUM = A.ASSETNUM
LEFT JOIN MAXIMO.LOCATIONS L ON I.LOCATION = L.LOCATION;
```

### Option 3: Filter by Specific Criteria

Create a filtered view for specific incident types:

```sql
CREATE OR REPLACE VIEW MAXIMO.INCIDENT_VIEW_ACTIVE AS
SELECT *
FROM MAXIMO.INCIDENT_VIEW
WHERE STATUS IN ('NEW', 'INPROG', 'QUEUED', 'PENDING')
    AND REPORTDATE >= CURRENT_TIMESTAMP - 90 DAYS;
```

## Connector Configuration

Once the view is created, configure the AIOps connector with these parameters:

```json
{
  "jdbcUrl": "jdbc:db2://maximo-host:50000/MAXDB76",
  "dbHost": "maximo-host",
  "dbPort": "50000",
  "dbName": "MAXDB76",
  "dbSchema": "MAXIMO",
  "viewName": "INCIDENT_VIEW",
  "username": "AIOPS_CONNECTOR",
  "password": "your_secure_password",
  "useSSL": true,
  "collectionMode": "live",
  "issueSamplingRate": 5
}
```

## Field Mapping Reference

| Maximo Field | AIOps Ticket Field | Description |
|--------------|-------------------|-------------|
| TICKETID | number | Incident ticket number |
| TICKETUID | sys_id | Unique identifier |
| STATUS | state | Incident status |
| DESCRIPTION | short_description | Brief description |
| DESCRIPTION_LONGDESCRIPTION | description | Detailed description |
| REPORTEDBY | opened_by | Person who reported |
| OWNER | assigned_to | Current owner |
| OWNERGROUP | business_service | Owning group |
| REPORTDATE | sys_created_on | Creation date |
| CHANGEDATE | sys_updated_on | Last update date |
| STATUSDATE | closed_at | Status change date |
| PRIORITY | impact | Priority level |
| CLASSSTRUCTUREID | type | Classification |
| FAILURECODE | reason | Failure/problem code |

## Status Mapping

The connector maps Maximo statuses to AIOps states:

| Maximo Status | AIOps State |
|---------------|-------------|
| NEW, REPORTED | Open |
| INPROG, QUEUED, PENDING | In Progress |
| CLOSED, RESOLVED, COMP, COMPLETED | Closed |
| CANCELLED, CANCEL | Cancelled |

## Troubleshooting

### Connection Issues

```sql
-- Verify user permissions
SELECT * FROM SYSCAT.TABAUTH 
WHERE GRANTEE = 'AIOPS_CONNECTOR' 
AND TABNAME = 'INCIDENT_VIEW';

-- Check if view exists
SELECT * FROM SYSCAT.VIEWS 
WHERE VIEWNAME = 'INCIDENT_VIEW' 
AND VIEWSCHEMA = 'MAXIMO';
```

### Performance Issues

```sql
-- Check query execution plan
EXPLAIN PLAN FOR
SELECT * FROM MAXIMO.INCIDENT_VIEW
WHERE REPORTDATE >= CURRENT_TIMESTAMP - 7 DAYS;

-- Monitor active queries
SELECT * FROM SYSIBMADM.SNAPAPPL_INFO
WHERE APPL_NAME LIKE '%AIOPS%';
```

### Data Validation

```sql
-- Verify data completeness
SELECT 
    STATUS,
    COUNT(*) as COUNT,
    MIN(REPORTDATE) as OLDEST,
    MAX(REPORTDATE) as NEWEST
FROM MAXIMO.INCIDENT_VIEW
GROUP BY STATUS;
```

## Security Considerations

1. **Use SSL/TLS** for database connections in production
2. **Rotate passwords** regularly for the connector user
3. **Limit network access** to Maximo DB2 using firewall rules
4. **Monitor access logs** for suspicious activity
5. **Use read-only permissions** - never grant write access
6. **Consider using service accounts** with certificate-based authentication

## Maintenance

### Regular Tasks

1. **Monitor view performance** - Check query execution times
2. **Update statistics** - Run RUNSTATS on underlying tables
3. **Review indexes** - Ensure indexes are being used effectively
4. **Archive old data** - Consider data retention policies

```sql
-- Update table statistics (run periodically)
RUNSTATS ON TABLE MAXIMO.INCIDENT 
WITH DISTRIBUTION AND DETAILED INDEXES ALL;

-- Reorganize table if needed
REORG TABLE MAXIMO.INCIDENT;
```

## Support and References

- [Maximo Database Schema Documentation](https://www.ibm.com/docs/en/mam/7.6.1)
- [DB2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5)
- [AIOps Connector SDK Documentation](https://www.ibm.com/docs/en/cloud-paks/cloud-pak-aiops)

## Example Queries for Testing

```sql
-- Get incidents from last 24 hours
SELECT TICKETID, STATUS, DESCRIPTION, REPORTDATE
FROM MAXIMO.INCIDENT_VIEW
WHERE REPORTDATE >= CURRENT_TIMESTAMP - 1 DAY
ORDER BY REPORTDATE DESC;

-- Get incidents by priority
SELECT PRIORITY, COUNT(*) as COUNT
FROM MAXIMO.INCIDENT_VIEW
WHERE STATUS IN ('NEW', 'INPROG')
GROUP BY PRIORITY
ORDER BY PRIORITY;

-- Get incidents by owner group
SELECT OWNERGROUP, COUNT(*) as COUNT
FROM MAXIMO.INCIDENT_VIEW
WHERE STATUS NOT IN ('CLOSED', 'RESOLVED')
GROUP BY OWNERGROUP
ORDER BY COUNT DESC;