#!/bin/bash

# Script to create 100 realistic demo incidents in Maximo DB2
# Usage: ./create-100-incidents.sh [namespace] [db-name]

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
NAMESPACE="${1:-db2u}"
DB_NAME="${2:-BLUDB}"
NUM_INCIDENTS=100

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Creating 100 Realistic Demo Incidents${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check for oc command
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: 'oc' command not found${NC}"
    exit 1
fi

# Get DB2 pod
echo -e "${BLUE}Finding DB2 pod in namespace: ${NAMESPACE}${NC}"
DB2_POD=$(oc get pods -n "$NAMESPACE" 2>/dev/null | grep db2u | grep -v Completed | grep Running | head -n 1 | awk '{print $1}')

if [ -z "$DB2_POD" ]; then
    echo -e "${RED}Error: No running DB2 pod found in namespace ${NAMESPACE}${NC}"
    exit 1
fi

echo -e "${GREEN}Found DB2 pod: ${DB2_POD}${NC}\n"

# Realistic incident descriptions
DESCRIPTIONS=(
    "Network connectivity issues in Building A"
    "Email service not responding for multiple users"
    "Printer offline on 3rd floor"
    "VPN connection timeout for remote workers"
    "Database performance degradation"
    "Application server high CPU usage"
    "Disk space running low on production server"
    "User unable to access shared drive"
    "Software installation request for Adobe Creative Suite"
    "Password reset required for locked account"
    "Laptop screen flickering intermittently"
    "Mouse not working properly"
    "Keyboard keys stuck"
    "Monitor display issues - no signal"
    "Audio not working in conference room"
    "Projector not turning on"
    "Wi-Fi signal weak in west wing"
    "Phone system down in sales department"
    "Scanner not functioning"
    "Backup job failed last night"
    "Antivirus update failed on workstation"
    "System crash and unexpected restart"
    "Application error message on startup"
    "Slow system performance"
    "File access denied error"
    "Cannot connect to network printer"
    "Outlook not syncing emails"
    "Teams video call quality poor"
    "SharePoint site not loading"
    "CRM system login issues"
    "ERP system timeout errors"
    "Website loading slowly"
    "Mobile app crashing on iOS"
    "Android app not updating"
    "Cloud storage sync issues"
    "Two-factor authentication not working"
    "SSL certificate expired"
    "Firewall blocking legitimate traffic"
    "Router needs firmware update"
    "Switch port not working"
    "Cable management in server room"
    "UPS battery replacement needed"
    "Air conditioning failure in data center"
    "Badge reader malfunction"
    "Security camera offline"
    "Access control system error"
    "Elevator phone not working"
    "Fire alarm panel showing fault"
    "Emergency lighting test required"
    "Generator maintenance overdue"
)

STATUSES=("NEW" "NEW" "NEW" "INPROG" "INPROG" "RESOLVED" "CLOSED")
SITES=("BEDFORD" "TEXAS" "DEFAULT")
OWNERS=("MAXADMIN" "WILSON" "JONES" "SMITH" "BROWN")
OWNERGROUPS=("IT" "HELPDESK" "NETWORK" "SECURITY" "FACILITIES")

echo -e "${BLUE}Generating SQL for 100 incidents...${NC}\n"

# Generate SQL file
SQL_FILE="/tmp/maximo_incidents_$$.sql"

cat > "$SQL_FILE" <<'EOSQL'
CONNECT TO DBNAME;
EOSQL

# Generate 100 INSERT statements
for i in $(seq 1 $NUM_INCIDENTS); do
    # Random selections
    DESC_IDX=$((RANDOM % ${#DESCRIPTIONS[@]}))
    STATUS_IDX=$((RANDOM % ${#STATUSES[@]}))
    SITE_IDX=$((RANDOM % ${#SITES[@]}))
    OWNER_IDX=$((RANDOM % ${#OWNERS[@]}))
    GROUP_IDX=$((RANDOM % ${#OWNERGROUPS[@]}))
    
    DESCRIPTION="${DESCRIPTIONS[$DESC_IDX]}"
    STATUS="${STATUSES[$STATUS_IDX]}"
    SITE="${SITES[$SITE_IDX]}"
    OWNER="${OWNERS[$OWNER_IDX]}"
    OWNERGROUP="${OWNERGROUPS[$GROUP_IDX]}"
    
    # Generate ticket ID with padding
    TICKETID=$(printf "INC%05d" $i)
    
    # Add to SQL file
    cat >> "$SQL_FILE" <<EOSQL
INSERT INTO MAXIMO.INCIDENT (TICKETID, TICKETUID, CLASS, STATUS, ACTLABCOST, ACTLABHRS, CHANGEBY, CHANGEDATE, HASACTIVITY, HASLD, HASSOLUTION, HISTORYFLAG, INHERITSTATUS, ISGLOBAL, ISKNOWNERROR, LANGCODE, ONCALLAUTOASSIGN, ORIGFROMALERT, PLUSPPOREQ, RELATEDTOGLOBAL, ROWSTAMP, SELFSERVSOLACCESS, SITEVISIT, STATUSDATE, TEMPLATE, DESCRIPTION, REPORTEDBY, OWNER, OWNERGROUP, SITEID, ORGID, REPORTDATE) VALUES ('$TICKETID', $i, 'INCIDENT', '$STATUS', 0, 0, 'MAXADMIN', CURRENT TIMESTAMP, 0, 0, 0, 0, 1, 0, 0, 'EN', 0, 0, 0, 0, 1, 0, 0, CURRENT TIMESTAMP, 0, 'Demo $i: $DESCRIPTION', 'MAXADMIN', '$OWNER', '$OWNERGROUP', '$SITE', 'EAGLENA', CURRENT TIMESTAMP);
EOSQL
    
    # Progress indicator
    if [ $((i % 10)) -eq 0 ]; then
        echo -e "${GREEN}Generated $i/$NUM_INCIDENTS incidents...${NC}"
    fi
done

# Add verification queries
cat >> "$SQL_FILE" <<'EOSQL'
SELECT COUNT(*) AS TOTAL_DEMO_INCIDENTS FROM MAXIMO.INCIDENT_VIEW WHERE TICKETID LIKE 'INC%';
SELECT STATUS, COUNT(*) AS COUNT FROM MAXIMO.INCIDENT_VIEW WHERE TICKETID LIKE 'INC%' GROUP BY STATUS;
CONNECT RESET;
EOSQL

# Replace DBNAME
sed -i.bak "s/DBNAME/$DB_NAME/g" "$SQL_FILE"

echo -e "\n${BLUE}Uploading SQL file to pod...${NC}"

# Copy SQL file to pod
oc cp "$SQL_FILE" "$NAMESPACE/$DB2_POD:/tmp/incidents.sql"

echo -e "${BLUE}Executing SQL (this may take a minute)...${NC}\n"

# Execute SQL
oc exec -n "$NAMESPACE" "$DB2_POD" -- su - db2inst1 -c "db2 +c -t -f /tmp/incidents.sql"

EXIT_CODE=$?

# Cleanup
rm -f "$SQL_FILE" "${SQL_FILE}.bak"
oc exec -n "$NAMESPACE" "$DB2_POD" -- rm -f /tmp/incidents.sql

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Successfully created 100 demo incidents${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    echo -e "${YELLOW}Incident IDs: INC00001 through INC00100${NC}"
    echo -e "${YELLOW}Statuses: Mixed (NEW, INPROG, RESOLVED, CLOSED)${NC}"
    echo -e "${YELLOW}Sites: BEDFORD, TEXAS, DEFAULT${NC}"
    echo -e "${YELLOW}Owner Groups: IT, HELPDESK, NETWORK, SECURITY, FACILITIES${NC}\n"
    
    echo -e "${YELLOW}Verify in your connector:${NC}"
    echo "The connector should now pick up these 100 demo incidents from the view."
    echo ""
    echo -e "${YELLOW}To view incidents directly:${NC}"
    echo "oc exec -n $NAMESPACE $DB2_POD -- su - db2inst1 -c \"db2 'CONNECT TO $DB_NAME; SELECT COUNT(*) FROM MAXIMO.INCIDENT_VIEW WHERE TICKETID LIKE \\'INC%\\''\""
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ Failed to create incidents${NC}"
    echo -e "${RED}========================================${NC}\n"
    
    echo -e "${YELLOW}Check the error messages above for details${NC}"
fi

exit $EXIT_CODE

# Made with Bob
