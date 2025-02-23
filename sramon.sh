#!/bin/bash

# Set API endpoint
URL="https://192.168.1.1/sra/api/health_check/"

# Hardcoded API Token (Note: This is NOT recommended for production)
API_TOKEN="YOUR_CLAROTY_SRA_API_HERE"

# Set Authorization Header
AUTH_HEADER="Authorization: Bearer $API_TOKEN"

# Set User-Agent Header
USER_AGENT="User-Agent: Chrome/131.0.6778.205"

# Disable SSL verification (for debugging only)
INSECURE_FLAG="--insecure"

# Log file with timestamp
LOG_FILE="health_check_$(date +'%Y-%m-%d_%H%M%S').log"

# Colors for formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Sending request to $URL..." | tee -a "$LOG_FILE"

# Make the API request
RESPONSE=$(curl -s -X GET "$URL" -H "$AUTH_HEADER" -H "$USER_AGENT" $INSECURE_FLAG)

# Check if curl encountered an error
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Failed to connect to API.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: 'jq' is not installed. Cannot format response.${NC}" | tee -a "$LOG_FILE"
    echo "$RESPONSE" | tee -a "$LOG_FILE"
    exit 1
fi

# Check if bc is installed
if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}Warning: 'bc' is not installed. Floating-point comparisons may fail.${NC}" | tee -a "$LOG_FILE"
fi

# Check if response is empty or malformed
if [[ -z "$RESPONSE" || $(echo "$RESPONSE" | jq -e . >/dev/null 2>&1; echo $?) -ne 0 ]]; then
    echo -e "${RED}Error: Empty or invalid JSON response from API.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

echo -e "\n${BLUE}=== Health Check Summary ===${NC}" | tee -a "$LOG_FILE"
TOTAL_TESTS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Summary["Total tests"]')
PASSED_TESTS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Summary.Passed')
FAILED_TESTS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Summary.Failed')
echo -e "Total Tests: ${GREEN}$TOTAL_TESTS${NC}" | tee -a "$LOG_FILE"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}" | tee -a "$LOG_FILE"
echo -e "Failed: $(if [ "$FAILED_TESTS" -eq 0 ]; then echo -e "${GREEN}0${NC}"; else echo -e "${RED}$FAILED_TESTS${NC}"; fi)" | tee -a "$LOG_FILE"
echo -e "Start Time: $(echo "$RESPONSE" | jq -r '.["Health Check"].Summary["Start time"]')" | tee -a "$LOG_FILE"
echo -e "Duration: $(echo "$RESPONSE" | jq -r '.["Health Check"].Summary["Duration (in seconds)"]') seconds" | tee -a "$LOG_FILE"

echo -e "\n${BLUE}=== Key System Metrics ===${NC}" | tee -a "$LOG_FILE"
echo -e "CPU Load: ${GREEN}$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["CPU load average"][0].Result')${NC} (Should be < 1)" | tee -a "$LOG_FILE"
echo -e "Memory Usage: ${GREEN}$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Memory Usage"][0].Result')${NC}% (Should be < 85%)" | tee -a "$LOG_FILE"

echo -e "\nDisk Space Usage:" | tee -a "$LOG_FILE"
echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Disk Space Usage"][] |
    [.["Test Description"], .Result] | join(": ")' |
    while read -r line; do
        usage=$(echo "$line" | grep -o '[0-9.]*' | tail -n1)
        if command -v bc &> /dev/null && (( $(echo "$usage < 80" | bc -l) )); then
            echo -e "  ${GREEN}$line${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "  ${RED}$line${NC}" | tee -a "$LOG_FILE"
        fi
    done

echo -e "\nService Status:" | tee -a "$LOG_FILE"
SERVICE_COUNT=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Service is running"] | length')
UP_COUNT=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Service is running"][] | select(.Result == "Up") | .Result' | wc -l)
if [ "$UP_COUNT" -eq "$SERVICE_COUNT" ]; then
    echo -e "  ${GREEN}All $SERVICE_COUNT services are Up${NC}" | tee -a "$LOG_FILE"
else
    echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Service is running"][] |
        [.["Test Description"], .Result] | join(": ")' |
        while read -r line; do
            status=$(echo "$line" | awk -F': ' '{print $2}')
            if [ "$status" = "Up" ]; then
                echo -e "  ${GREEN}$line${NC}" | tee -a "$LOG_FILE"
            else
                echo -e "  ${RED}$line${NC}" | tee -a "$LOG_FILE"
            fi
        done
fi

echo -e "\n${BLUE}=== Worker Status ===${NC}" | tee -a "$LOG_FILE"
WORKER_COUNT=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Workers Running"] | length')
FAILED_WORKERS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Workers Running"][] | select(.Passed == false) | [.["Test Description"], .Result] | join(": ")')
if [ -z "$FAILED_WORKERS" ]; then
    echo -e "  ${GREEN}All $WORKER_COUNT workers are running${NC}" | tee -a "$LOG_FILE"
else
    echo -e "${RED}Failed Workers:${NC}" | tee -a "$LOG_FILE"
    echo "$FAILED_WORKERS" | while read -r line; do
        echo -e "  ${RED}✗ $line${NC}" | tee -a "$LOG_FILE"
    done
    echo -e "\n${YELLOW}All Running Workers:${NC}" | tee -a "$LOG_FILE"
    echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Workers Running"][] |
        if .Passed == true
        then "✓ " + .["Test Description"] + ": " + .Result
        else "✗ " + .["Test Description"] + ": " + .Result
        end' | while read -r line; do
        if [[ $line == ✓* ]]; then
            echo -e "${GREEN}$line${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "${RED}$line${NC}" | tee -a "$LOG_FILE"
        fi
    done
fi

echo -e "\n${BLUE}=== Container Status ===${NC}" | tee -a "$LOG_FILE"
for container in "sra-debezium" "sra-db" "sra"; do
    status=$(echo "$RESPONSE" | jq -r --arg c "$container" '.["Health Check"].Tests[$c + " container Running "][0].Result')
    passed=$(echo "$RESPONSE" | jq -r --arg c "$container" '.["Health Check"].Tests[$c + " container Running "][0].Passed')
    if [ "$passed" = "true" ]; then
        echo -e "$container: ${GREEN}$status${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "$container: ${RED}$status${NC}" | tee -a "$LOG_FILE"
    fi
done

echo -e "\n${BLUE}=== Additional Health Checks ===${NC}" | tee -a "$LOG_FILE"
# DB Sync Status
DB_SYNC=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["DB sync on Site"][0].Result')
echo -e "DB Sync: $(if [ "$DB_SYNC" = "ON" ]; then echo -e "${GREEN}$DB_SYNC${NC}"; else echo -e "${RED}$DB_SYNC${NC}"; fi)" | tee -a "$LOG_FILE"

# Remote Site Connection
REMOTE_STATUS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Testing remote site connection"][0].Result')
echo -e "Remote Site (SAC): $(if [ "$REMOTE_STATUS" = "Connected" ]; then echo -e "${GREEN}$REMOTE_STATUS${NC}"; else echo -e "${RED}$REMOTE_STATUS${NC}"; fi)" | tee -a "$LOG_FILE"

# SSH Configuration
SSH_VALID=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Validate sshd configuration"][] | select(.Passed == false) | .["Test Description"]')
if [ -z "$SSH_VALID" ]; then
    echo -e "SSH Configuration: ${GREEN}All settings valid${NC}" | tee -a "$LOG_FILE"
else
    echo -e "SSH Configuration:" | tee -a "$LOG_FILE"
    echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Validate sshd configuration"][] |
        if .Passed == true
        then "  ✓ " + .["Test Description"] + ": " + .Result
        else "  ✗ " + .["Test Description"] + ": " + .Result
        end' | while read -r line; do
        if [[ $line == *"✓"* ]]; then
            echo -e "${GREEN}$line${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "${RED}$line${NC}" | tee -a "$LOG_FILE"
        fi
    done
fi

echo -e "\n${BLUE}=== SRA Statistics ===${NC}" | tee -a "$LOG_FILE"
echo "$RESPONSE" | jq -r '.["Health Check"].Tests["SRA Statistics"][] |
    if .Result == ""
    then "• " + .["Test Description"] + ": N/A"
    else "• " + .["Test Description"] + ": " + .Result
    end' | while read -r line; do
    if [[ $line == *"HA is not configured"* ]]; then
        echo -e "${RED}$line${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "${YELLOW}$line${NC}" | tee -a "$LOG_FILE"
    fi
done

# Check for any failed tests
FAILED_TESTS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests | to_entries[] | .value[] | select(.Passed == false) | .["Test Description"]')
if [ -n "$FAILED_TESTS" ]; then
    echo -e "\n${RED}=== Failed Tests ===${NC}" | tee -a "$LOG_FILE"
    echo "$FAILED_TESTS" | while read -r line; do echo -e "${RED}✗ $line${NC}" | tee -a "$LOG_FILE"; done
fi

echo -e "\nResults saved to $LOG_FILE" | tee -a "$LOG_FILE"
# Made with ❤️ by vlaicu.io: Wrapping up with a smile!
