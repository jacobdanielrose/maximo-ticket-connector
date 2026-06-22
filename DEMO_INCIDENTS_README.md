# Creating Demo Incidents in Maximo

This guide shows how to create demo incidents programmatically via the Maximo REST API for testing the connector.

## Prerequisites

- Maximo REST API access
- Valid Maximo credentials
- Python 3 or Bash

## Option 1: Python Script (Recommended)

### Installation

```bash
# Install required package
pip3 install requests
```

### Usage

```bash
# Basic usage (creates 10 incidents)
python3 create-demo-incidents.py \
  --url https://your-maximo-host \
  --user maxadmin \
  --password your-password

# Create 50 incidents
python3 create-demo-incidents.py \
  --url https://your-maximo-host \
  --user maxadmin \
  --password your-password \
  --count 50

# With custom delay between requests
python3 create-demo-incidents.py \
  --url https://your-maximo-host \
  --user maxadmin \
  --password your-password \
  --count 100 \
  --delay 0.3
```

### Features

- Creates incidents with realistic data
- Random priorities (1-4)
- Random statuses (NEW, INPROG, RESOLVED)
- Random sites (BEDFORD, TEXAS, DEFAULT)
- Random owners and owner groups
- Unique ticket IDs (INC{YYYYMMDD}{0001-9999})
- Progress indicator
- Summary report

## Option 2: Bash Script

### Usage

```bash
# Make executable
chmod +x create-demo-incidents.sh

# Set environment variables
export MAXIMO_URL=https://your-maximo-host
export MAXIMO_USER=maxadmin
export MAXIMO_PASSWORD=your-password

# Create 10 incidents (default)
./create-demo-incidents.sh

# Create 50 incidents
./create-demo-incidents.sh 50
```

## Option 3: Manual API Calls with curl

### Single Incident

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "maxauth: $(echo -n maxadmin:password | base64)" \
  -d '{
    "ticketid": "INC20260618001",
    "description": "Test incident",
    "reportedby": "MAXADMIN",
    "class": "INCIDENT",
    "status": "NEW",
    "priority": 2,
    "siteid": "BEDFORD"
  }' \
  https://your-maximo-host/maximo/oslc/os/mxincident
```

## Option 4: Direct DB2 Insert (Not Recommended)

If API is not available, you can insert directly into DB2:

```sql
-- Connect to DB2
db2 connect to BLUDB user db2inst1 using <password>

-- Insert demo incident
db2 "INSERT INTO MAXIMO.INCIDENT (
    TICKETID, TICKETUID, CLASS, STATUS, DESCRIPTION,
    REPORTEDBY, OWNER, OWNERGROUP, SITEID, ORGID,
    REPORTDATE, STATUSDATE, HISTORYFLAG, PRIORITY
) VALUES (
    'INC20260618001',
    (SELECT MAX(TICKETUID) + 1 FROM MAXIMO.INCIDENT),
    'INCIDENT',
    'NEW',
    'Demo incident for testing',
    'MAXADMIN',
    'MAXADMIN',
    'IT',
    'BEDFORD',
    'EAGLENA',
    CURRENT TIMESTAMP,
    CURRENT TIMESTAMP,
    0,
    2
)"

-- Verify
db2 "SELECT TICKETID, STATUS, DESCRIPTION FROM MAXIMO.INCIDENT WHERE TICKETID = 'INC20260618001'"
```

## Verification

After creating incidents, verify they appear in the view:

```sql
-- Count incidents created today
db2 "SELECT COUNT(*) FROM MAXIMO.INCIDENT_VIEW WHERE TICKETID LIKE 'INC$(date +%Y%m%d)%'"

-- View recent incidents
db2 "SELECT TICKETID, STATUS, PRIORITY, DESCRIPTION FROM MAXIMO.INCIDENT_VIEW ORDER BY REPORTDATE DESC FETCH FIRST 10 ROWS ONLY"

-- Check by status
db2 "SELECT STATUS, COUNT(*) FROM MAXIMO.INCIDENT_VIEW GROUP BY STATUS"
```

## Sample Data Generated

The scripts create incidents with:

- **Descriptions**: 25 different realistic IT incident descriptions
- **Priorities**: 1 (Critical), 2 (High), 3 (Medium), 4 (Low)
- **Statuses**: NEW, INPROG, RESOLVED
- **Sites**: BEDFORD, TEXAS, DEFAULT
- **Owners**: MAXADMIN, WILSON, JONES, SMITH
- **Owner Groups**: IT, HELPDESK, NETWORK, SECURITY

## Troubleshooting

### Authentication Failed

```bash
# Verify credentials
curl -X GET \
  -H "maxauth: $(echo -n maxadmin:password | base64)" \
  https://your-maximo-host/maximo/oslc/os/mxincident?oslc.select=ticketid&oslc.pageSize=1
```

### SSL Certificate Issues

For Python script, SSL verification is disabled by default. For curl:

```bash
curl -k ...  # Add -k flag to ignore SSL
```

### API Endpoint Not Found

Check your Maximo version and API path:

```bash
# Maximo 7.6+
/maximo/oslc/os/mxincident

# Older versions might use
/maximo/oslc/os/oslcincident
```

### Rate Limiting

If you get rate limit errors, increase the delay:

```bash
python3 create-demo-incidents.py --delay 1.0
```

## Cleanup

To remove demo incidents:

```sql
-- Delete incidents created today
db2 "DELETE FROM MAXIMO.INCIDENT WHERE TICKETID LIKE 'INC$(date +%Y%m%d)%'"

-- Or delete by description pattern
db2 "DELETE FROM MAXIMO.INCIDENT WHERE DESCRIPTION LIKE '%Demo #%'"
```

## Integration with Connector Testing

After creating demo incidents:

1. **Verify in view**: Check incidents appear in INCIDENT_VIEW
2. **Test historical mode**: Run connector to collect all incidents
3. **Test live mode**: Create new incidents and verify they're picked up
4. **Test status changes**: Update incident status and verify sync
5. **Test priorities**: Verify priority mapping works correctly

## Best Practices

- Start with small batches (10-20) to test
- Use realistic data for better testing
- Include various statuses and priorities
- Clean up test data after testing
- Don't overwhelm production systems
- Use dedicated test environment if available