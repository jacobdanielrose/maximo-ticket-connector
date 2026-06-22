#!/usr/bin/env python3
"""
Create demo incidents in Maximo via REST API
Usage: python3 create-demo-incidents.py [--count 10] [--url https://maximo] [--user maxadmin] [--password pass]
"""

import requests
import json
import base64
import argparse
import random
import time
from datetime import datetime
from urllib3.exceptions import InsecureRequestWarning

# Suppress SSL warnings for self-signed certificates
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

# Sample data
DESCRIPTIONS = [
    "Network connectivity issues in Building A",
    "Email service not responding",
    "Printer offline in 3rd floor",
    "VPN connection timeout",
    "Database performance degradation",
    "Application server high CPU usage",
    "Disk space running low on server",
    "User unable to access shared drive",
    "Software installation request",
    "Password reset required",
    "Laptop screen flickering",
    "Mouse not working properly",
    "Keyboard keys stuck",
    "Monitor display issues",
    "Audio not working in conference room",
    "Projector not turning on",
    "Wi-Fi signal weak in area",
    "Phone system down",
    "Scanner not functioning",
    "Backup job failed",
    "Antivirus update failed",
    "System crash and restart",
    "Application error message",
    "Slow system performance",
    "File access denied error"
]

PRIORITIES = [1, 2, 3, 4]
STATUSES = ["NEW", "INPROG", "RESOLVED"]
SITES = ["BEDFORD", "TEXAS", "DEFAULT"]
OWNERS = ["MAXADMIN", "WILSON", "JONES", "SMITH"]
OWNERGROUPS = ["IT", "HELPDESK", "NETWORK", "SECURITY"]

def create_incident(session, base_url, num, total):
    """Create a single incident"""
    
    # Generate data
    description = random.choice(DESCRIPTIONS)
    priority = random.choice(PRIORITIES)
    status = random.choice(STATUSES)
    site = random.choice(SITES)
    owner = random.choice(OWNERS)
    ownergroup = random.choice(OWNERGROUPS)
    
    # Generate unique ticket ID
    ticketid = f"INC{datetime.now().strftime('%Y%m%d')}{num:04d}"
    
    # Create payload
    payload = {
        "ticketid": ticketid,
        "description": f"{description} - Demo #{num}",
        "reportedby": "MAXADMIN",
        "affectedperson": "MAXADMIN",
        "class": "INCIDENT",
        "status": status,
        "priority": priority,
        "siteid": site,
        "owner": owner,
        "ownergroup": ownergroup,
        "orgid": "EAGLENA"
    }
    
    # Make API call
    url = f"{base_url}/maximo/oslc/os/mxincident"
    
    try:
        response = session.post(url, json=payload, verify=False, timeout=30)
        
        if response.status_code in [200, 201]:
            print(f"✓ [{num}/{total}] Created {ticketid} (P{priority}, {status}, {ownergroup})")
            return True
        else:
            print(f"✗ [{num}/{total}] Failed {ticketid} - HTTP {response.status_code}")
            print(f"  Response: {response.text[:200]}")
            return False
            
    except Exception as e:
        print(f"✗ [{num}/{total}] Error creating {ticketid}: {str(e)}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Create demo incidents in Maximo')
    parser.add_argument('--count', type=int, default=10, help='Number of incidents to create')
    parser.add_argument('--url', default='https://your-maximo-host', help='Maximo base URL')
    parser.add_argument('--user', default='maxadmin', help='Maximo username')
    parser.add_argument('--password', default='maxadmin', help='Maximo password')
    parser.add_argument('--delay', type=float, default=0.5, help='Delay between requests (seconds)')
    
    args = parser.parse_args()
    
    # Create session
    session = requests.Session()
    
    # Set authentication header
    auth_string = f"{args.user}:{args.password}"
    auth_bytes = auth_string.encode('ascii')
    base64_bytes = base64.b64encode(auth_bytes)
    base64_string = base64_bytes.decode('ascii')
    
    session.headers.update({
        'Content-Type': 'application/json',
        'maxauth': base64_string
    })
    
    print(f"\n{'='*60}")
    print(f"Creating {args.count} demo incidents in Maximo")
    print(f"URL: {args.url}")
    print(f"User: {args.user}")
    print(f"{'='*60}\n")
    
    # Create incidents
    success_count = 0
    fail_count = 0
    
    for i in range(1, args.count + 1):
        if create_incident(session, args.url, i, args.count):
            success_count += 1
        else:
            fail_count += 1
        
        # Delay between requests
        if i < args.count:
            time.sleep(args.delay)
    
    # Summary
    print(f"\n{'='*60}")
    print(f"✓ Successfully created: {success_count}")
    print(f"✗ Failed: {fail_count}")
    print(f"{'='*60}\n")
    
    # Verification query
    today = datetime.now().strftime('%Y%m%d')
    print("Verify in DB2:")
    print(f'db2 "SELECT COUNT(*) FROM MAXIMO.INCIDENT WHERE TICKETID LIKE \'INC{today}%\'"')
    print(f'db2 "SELECT TICKETID, STATUS, PRIORITY, DESCRIPTION FROM MAXIMO.INCIDENT WHERE TICKETID LIKE \'INC{today}%\' FETCH FIRST 10 ROWS ONLY"')

if __name__ == '__main__':
    main()

# Made with Bob
