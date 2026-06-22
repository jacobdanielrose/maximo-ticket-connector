#!/bin/bash

# Script to create demo incidents in Maximo via REST API
# Usage: ./create-demo-incidents.sh [number_of_incidents]

set -e

# Configuration
MAXIMO_URL="${MAXIMO_URL:-https://your-maximo-host}"
MAXIMO_USER="${MAXIMO_USER:-maxadmin}"
MAXIMO_PASSWORD="${MAXIMO_PASSWORD:-maxadmin}"
NUM_INCIDENTS="${1:-10}"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Creating ${NUM_INCIDENTS} demo incidents in Maximo...${NC}"

# Sample data arrays
DESCRIPTIONS=(
    "Network connectivity issues in Building A"
    "Email service not responding"
    "Printer offline in 3rd floor"
    "VPN connection timeout"
    "Database performance degradation"
    "Application server high CPU usage"
    "Disk space running low on server"
    "User unable to access shared drive"
    "Software installation request"
    "Password reset required"
    "Laptop screen flickering"
    "Mouse not working properly"
    "Keyboard keys stuck"
    "Monitor display issues"
    "Audio not working in conference room"
    "Projector not turning on"
    "Wi-Fi signal weak in area"
    "Phone system down"
    "Scanner not functioning"
    "Backup job failed"
)

PRIORITIES=(1 2 3 4)
STATUSES=("NEW" "INPROG" "RESOLVED")
SITES=("BEDFORD" "TEXAS" "DEFAULT")

# Function to generate random element from array
get_random() {
    local arr=("$@")
    local size=${#arr[@]}
    local index=$((RANDOM % size))
    echo "${arr[$index]}"
}

# Function to create incident
create_incident() {
    local num=$1
    local description="${DESCRIPTIONS[$((RANDOM % ${#DESCRIPTIONS[@]}))]}"
    local priority=$(get_random "${PRIORITIES[@]}")
    local status=$(get_random "${STATUSES[@]}")
    local site=$(get_random "${SITES[@]}")
    
    # Generate unique ticket ID
    local ticketid="INC$(date +%Y%m%d)$(printf "%04d" $num)"
    
    # Create JSON payload
    local json_payload=$(cat <<EOF
{
    "ticketid": "${ticketid}",
    "description": "${description} - Demo #${num}",
    "reportedby": "MAXADMIN",
    "affectedperson": "MAXADMIN",
    "class": "INCIDENT",
    "status": "${status}",
    "priority": ${priority},
    "siteid": "${site}",
    "orgid": "EAGLENA"
}
EOF
)
    
    # Make API call
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "maxauth: $(echo -n ${MAXIMO_USER}:${MAXIMO_PASSWORD} | base64)" \
        -d "${json_payload}" \
        "${MAXIMO_URL}/maximo/oslc/os/mxincident")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq 201 ] || [ "$http_code" -eq 200 ]; then
        echo -e "${GREEN}✓ Created incident ${ticketid} (Priority: ${priority}, Status: ${status})${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to create incident ${ticketid} (HTTP ${http_code})${NC}"
        echo "Response: $body"
        return 1
    fi
}

# Main loop
success_count=0
fail_count=0

for i in $(seq 1 $NUM_INCIDENTS); do
    if create_incident $i; then
        ((success_count++))
    else
        ((fail_count++))
    fi
    
    # Small delay to avoid overwhelming the API
    sleep 0.5
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Successfully created: ${success_count}${NC}"
echo -e "${RED}Failed: ${fail_count}${NC}"
echo -e "${BLUE}========================================${NC}"

# Verify in database
echo ""
echo -e "${BLUE}Verifying incidents in database...${NC}"
echo "Run this in DB2:"
echo "db2 \"SELECT COUNT(*) FROM MAXIMO.INCIDENT WHERE TICKETID LIKE 'INC$(date +%Y%m%d)%'\""

# Made with Bob
