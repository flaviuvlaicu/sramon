#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Host configuration file with IP, host, token, and URL base
HOST_FILE="${SCRIPT_DIR}/hosts.conf"

# Set User-Agent Header
USER_AGENT="User-Agent: Chrome/131.0.6778.205"

# Disable SSL verification (for debugging only)
INSECURE_FLAG="--insecure"

# Log file with timestamp
LOG_FILE="${SCRIPT_DIR}/logs/sramon_$(date +'%Y-%m-%d_%H%M%S').log"

# Colors for formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'  # For distinct visual separation
NC='\033[0m' # No Color

# Function to validate and get IP from input (hostname or IP)
get_ip() {
    local target=$1
    # Check if the target is an IP (contains dots and numbers, allowing leading zeros)
    if [[ $target =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # Validate each octet (0-255)
        IFS='.' read -r -a octets <<< "$target"
        for octet in "${octets[@]}"; do
            if [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        echo "$target"
    else
        # Look up IP from hosts.conf, case-insensitive, ensuring proper spacing
        local ip=$(grep -i "^[0-9.]*[[:space:]]*$target[[:space:]]" "$HOST_FILE" | awk '{print $1}' | head -n 1)
        if [ -z "$ip" ]; then
            echo -e "${RED}Error: Could not find IP for hostname $target in $HOST_FILE.${NC}" | tee -a "$LOG_FILE"
            exit 1
        fi
        echo "$ip"
    fi
}

# Function to get hostname for a given IP
get_hostname() {
    local ip=$1
    # Look up hostname from hosts.conf, case-insensitive, ensuring proper spacing
    local hostname=$(grep -i "^$ip[[:space:]]" "$HOST_FILE" | awk '{print $2}' | head -n 1)
    if [ -z "$hostname" ]; then
        echo -e "${RED}Error: Could not find hostname for IP $ip in $HOST_FILE.${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
    echo "$hostname"
}

# Function to get API token for a given IP or hostname
get_token() {
    local target=$1
    # First, get the IP if the target is a hostname
    local ip=$(get_ip "$target")
    if [ -z "$ip" ]; then
        echo ""
        return 1
    fi
    # Look up token for the IP in hosts.conf (handles blank tokens)
    local token=$(grep -i "^$ip[[:space:]]" "$HOST_FILE" | awk '{print $3}' | head -n 1)
    # Remove any whitespace and check if token is empty
    token=$(echo "$token" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -z "$token" ]; then
        echo -e "${YELLOW}Warning: No API token found for $target (IP: $ip) in $HOST_FILE. Please populate the token in hosts.conf.${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
    echo "$token"
}

# Function to get URL base for a given IP or hostname
get_url_base() {
    local target=$1
    # First, get the IP if the target is a hostname
    local ip=$(get_ip "$target")
    if [ -z "$ip" ]; then
        echo ""
        return 1
    fi
    # Look up URL base for the IP in hosts.conf
    local url_base=$(grep -i "^$ip[[:space:]]" "$HOST_FILE" | awk '{print $4}' | head -n 1)
    if [ -z "$url_base" ]; then
        echo -e "${RED}Error: No URL base found for $target (IP: $ip) in $HOST_FILE.${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
    echo "$url_base"
}

# Verify hosts.conf exists and is readable at the start
if [ ! -f "$HOST_FILE" ] || [ ! -r "$HOST_FILE" ]; then
    echo -e "${RED}Error: Host configuration file $HOST_FILE does not exist or is not readable.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# Initialize debug flag
DEBUG=false

# Parse command-line arguments (using long options --ip, --host, and --debug)
while [[ $# -gt 0 ]]; do
    case $1 in
        --ip)
            shift
            TARGET_IP="$1"
            if ! [[ "$TARGET_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                echo -e "${RED}Error: Invalid IP address format for --ip argument: $TARGET_IP${NC}" | tee -a "$LOG_FILE"
                exit 1
            fi
            # Validate each octet (0-255)
            IFS='.' read -r -a octets <<< "$TARGET_IP"
            for octet in "${octets[@]}"; do
                if [ "$octet" -gt 255 ]; then
                    echo -e "${RED}Error: Invalid IP address format for --ip argument: $TARGET_IP (octet $octet > 255)${NC}" | tee -a "$LOG_FILE"
                    exit 1
                fi
            done
            TARGET=$(get_hostname "$TARGET_IP")
            if [ "$DEBUG" = true ]; then
                echo -e "${GREEN}Found hostname $TARGET for IP $TARGET_IP in $HOST_FILE.${NC}" | tee -a "$LOG_FILE"
            fi
            shift
            ;;
        --host)
            shift
            TARGET="$1"
            TARGET_IP=$(get_ip "$TARGET")
            if [ -z "$TARGET_IP" ]; then
                echo -e "${RED}Error: Hostname $TARGET not found in $HOST_FILE.${NC}" | tee -a "$LOG_FILE"
                exit 1
            fi
            if [ "$DEBUG" = true ]; then
                echo -e "${GREEN}Found IP $TARGET_IP for hostname $TARGET in $HOST_FILE.${NC}" | tee -a "$LOG_FILE"
            fi
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        *)
            echo -e "${RED}Error: Invalid option: $1${NC}" | tee -a "$LOG_FILE"
            echo "Usage: $0 --ip <IP_ADDRESS> or $0 --host <HOSTNAME> [--debug]" | tee -a "$LOG_FILE"
            exit 1
            ;;
    esac
done

# Check if either --ip or --host was provided
if [ -z "$TARGET" ] || [ -z "$TARGET_IP" ]; then
    echo -e "${RED}Error: Please provide either --ip <IP_ADDRESS> or --host <HOSTNAME> as an argument.${NC}"
    echo "Usage: $0 --ip <IP_ADDRESS> or $0 --host <HOSTNAME> [--debug]" | tee -a "$LOG_FILE"
    exit 1
fi

# Ensure IP and TARGET are set
IP=$TARGET_IP

# Debug: Log the retrieved values from hosts.conf only if --debug is set
if [ "$DEBUG" = true ]; then
    echo -e "${BLUE}Debug: Processing $TARGET (IP: $IP)${NC}" | tee -a "$LOG_FILE"
fi
TOKEN=$(get_token "$TARGET")
URL_BASE=$(get_url_base "$TARGET")
if [ "$DEBUG" = true ]; then
    echo -e "${GREEN}Retrieved Token: $TOKEN${NC}" | tee -a "$LOG_FILE"
    echo -e "${GREEN}Retrieved URL Base: $URL_BASE${NC}" | tee -a "$LOG_FILE"
fi

# Get API token for the target (IP or hostname)
if [ -z "$TOKEN" ]; then
    echo -e "${RED}Error: No API token found for $TARGET (IP: $IP) in $HOST_FILE. Please populate the token in hosts.conf.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# Get URL base for the target (IP or hostname)
if [ -z "$URL_BASE" ]; then
    echo -e "${RED}Error: No URL base found for $TARGET (IP: $IP) in $HOST_FILE.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# Construct the full URL (use only the base URL, not appending IP, based on API response)
URL="$URL_BASE"

# Debug: Log the API request details only if --debug is set
if [ "$DEBUG" = true ]; then
    echo -e "${BLUE}Debug: Sending request to $URL with token $TOKEN${NC}" | tee -a "$LOG_FILE"
fi

# Make the API request and capture HTTP status code
RESPONSE=$(curl -s -w "%{http_code}" -X GET "$URL" -H "Authorization: Bearer $TOKEN" -H "$USER_AGENT" $INSECURE_FLAG -o response.txt)
HTTP_STATUS=${RESPONSE: -3}
RESPONSE=$(cat response.txt)
rm response.txt

# Check if curl encountered an error or non-200 status
if [ "$HTTP_STATUS" -ne 200 ]; then
    echo -e "${RED}Error: API request to $URL failed with status $HTTP_STATUS. Raw response: $RESPONSE${NC}" | tee -a "$LOG_FILE"
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
if [[ -z "$RESPONSE" ]]; then
    echo -e "${RED}Error: Empty response from API at $URL.${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# Try to parse the response with jq to detect JSON structure
if ! echo "$RESPONSE" | jq -e . >/dev/null 2>&1; then
    echo -e "${RED}Error: Invalid JSON response from API at $URL. Raw response: $RESPONSE${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

echo -e "\n${BLUE}=== Health Check Summary for $TARGET (IP: $IP) ===${NC}" | tee -a "$LOG_FILE"
TOTAL_TESTS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Summary["Total tests"]' || echo "null")
PASSED_TESTS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Summary.Passed' || echo "null")
FAILED_TESTS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Summary.Failed' || echo "0")
echo -e "Total Tests: ${GREEN}$TOTAL_TESTS${NC}" | tee -a "$LOG_FILE"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}" | tee -a "$LOG_FILE"
echo -e "Failed: $(if [ "$FAILED_TESTS" = "null" ] || [ "$FAILED_TESTS" -eq 0 ]; then echo -e "${GREEN}0${NC}"; else echo -e "${RED}$FAILED_TESTS${NC}"; fi)" | tee -a "$LOG_FILE"
echo -e "Start Time: $(echo "$RESPONSE" | jq -r '.["Health Check"].Summary["Start time"]' || echo "null")" | tee -a "$LOG_FILE"
echo -e "Duration: $(echo "$RESPONSE" | jq -r '.["Health Check"].Summary["Duration (in seconds)"]' || echo "null") seconds" | tee -a "$LOG_FILE"

echo -e "\n${BLUE}=== Key System Metrics ===${NC}" | tee -a "$LOG_FILE"
echo -e "CPU Load: ${GREEN}$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["CPU load average"][0].Result' || echo "null")${NC} (Should be < 1)" | tee -a "$LOG_FILE"
echo -e "Memory Usage: ${GREEN}$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Memory Usage"][0].Result' || echo "null")${NC}% (Should be < 85%)" | tee -a "$LOG_FILE"

echo -e "\nDisk Space Usage:" | tee -a "$LOG_FILE"
if echo "$RESPONSE" | jq -e '.["Health Check"].Tests["Disk Space Usage"][]' >/dev/null 2>&1; then
    echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Disk Space Usage"][] |
        [.["Test Description"], .Result] | join(": ")' |
        while read -r line; do
            usage=$(echo "$line" | grep -o '[0-9.]*' | tail -n1 || echo "0")
            if command -v bc &> /dev/null && (( $(echo "$usage < 80" | bc -l) )); then
                echo -e "  ${GREEN}$line${NC}" | tee -a "$LOG_FILE"
            else
                echo -e "  ${RED}$line${NC}" | tee -a "$LOG_FILE"
            fi
        done
else
    echo -e "${YELLOW}No Disk Space Usage data available.${NC}" | tee -a "$LOG_FILE"
fi

echo -e "\n${BLUE}Service Status:${NC}" | tee -a "$LOG_FILE"
if echo "$RESPONSE" | jq -e '.["Health Check"].Tests["Service is running"][]' >/dev/null 2>&1; then
    echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Service is running"][] |
        [.["Test Description"], .Result] | join(": ")' |
        while read -r line; do
            status=$(echo "$line" | awk -F': ' '{print $2}' || echo "Down")
            if [ "$status" = "Up" ]; then
                echo -e "  ${GREEN}$line${NC}" | tee -a "$LOG_FILE"
            else
                echo -e "  ${RED}$line${NC}" | tee -a "$LOG_FILE"
            fi
        done
else
    echo -e "${YELLOW}No Service Status data available.${NC}" | tee -a "$LOG_FILE"
fi

echo -e "\n${BLUE}=== Worker Status ===${NC}" | tee -a "$LOG_FILE"
if echo "$RESPONSE" | jq -e '.["Health Check"].Tests["Workers Running"][]' >/dev/null 2>&1; then
    WORKER_COUNT=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Workers Running"] | length' || echo "0")
    FAILED_WORKERS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Workers Running"][] | select(.Passed == false) | [.["Test Description"], .Result] | join(": ")' || echo "")
    if [ -z "$FAILED_WORKERS" ]; then
        echo -e "  ${GREEN}All $WORKER_COUNT workers are running${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}Failed Workers:${NC}" | tee -a "$LOG_FILE"
        echo "$FAILED_WORKERS" | while read -r line; do
            # Extract the worker name (Test Description) and status from the line
            worker_name=$(echo "$line" | awk -F': ' '{print $1}')
            status=$(echo "$line" | awk -F': ' '{print $2}')
            echo -e "  ${RED}✗ $worker_name is stopped: $status${NC}" | tee -a "$LOG_FILE"
        done
        echo -e "\n${YELLOW}All Workers:${NC}" | tee -a "$LOG_FILE"
        echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Workers Running"][] |
            if .Passed == true
            then "✓ " + .["Test Description"] + ": " + .Result
            else "✗ " + .["Test Description"] + ": " + .Result
            end' | while read -r line; do
            if [[ $line == ✓* ]]; then
                echo -e "  ${GREEN}$line${NC}" | tee -a "$LOG_FILE"
            else
                echo -e "  ${RED}$line${NC}" | tee -a "$LOG_FILE"
            fi
        done
    fi
else
    echo -e "${YELLOW}No Worker Status data available.${NC}" | tee -a "$LOG_FILE"
fi

echo -e "\n${BLUE}=== Container Status ===${NC}" | tee -a "$LOG_FILE"
for container in "sra-debezium" "sra-db" "sra"; do
    status=$(echo "$RESPONSE" | jq -r --arg c "$container" '.["Health Check"].Tests[$c + " container Running "][0].Result' || echo "null")
    passed=$(echo "$RESPONSE" | jq -r --arg c "$container" '.["Health Check"].Tests[$c + " container Running "][0].Passed' || echo "false")
    if [ "$passed" = "true" ]; then
        echo -e "$container: ${GREEN}$status${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "$container: ${RED}$status${NC}" | tee -a "$LOG_FILE"
    fi
done

echo -e "\n${BLUE}=== Additional Health Checks ===${NC}" | tee -a "$LOG_FILE"
# DB Sync Status
DB_SYNC=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["DB sync on Site"][0].Result' || echo "null")
echo -e "DB Sync: $(if [ "$DB_SYNC" = "ON" ]; then echo -e "${GREEN}$DB_SYNC${NC}"; else echo -e "${RED}$DB_SYNC${NC}"; fi)" | tee -a "$LOG_FILE"

# Remote Site Connection
REMOTE_STATUS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Testing remote site connection"][0].Result' || echo "null")
echo -e "Remote Site (SAC): $(if [ "$REMOTE_STATUS" = "Connected" ]; then echo -e "${GREEN}$REMOTE_STATUS${NC}"; else echo -e "${RED}$REMOTE_STATUS${NC}"; fi)" | tee -a "$LOG_FILE"

# SSH Configuration
if echo "$RESPONSE" | jq -e '.["Health Check"].Tests["Validate sshd configuration"][]' >/dev/null 2>&1; then
    SSH_VALID=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests["Validate sshd configuration"][] | select(.Passed == false) | .["Test Description"]' || echo "")
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
else
    echo -e "${YELLOW}No SSH Configuration data available.${NC}" | tee -a "$LOG_FILE"
fi

echo -e "\n${BLUE}=== SRA Statistics ===${NC}" | tee -a "$LOG_FILE"
if echo "$RESPONSE" | jq -e '.["Health Check"].Tests["SRA Statistics"][]' >/dev/null 2>&1; then
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
else
    echo -e "${YELLOW}No SRA Statistics data available.${NC}" | tee -a "$LOG_FILE"
fi

# Check for any failed tests
if echo "$RESPONSE" | jq -e '.["Health Check"].Tests | to_entries[] | .value[] | select(.Passed == false)' >/dev/null 2>&1; then
    FAILED_TESTS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Tests | to_entries[] | .value[] | select(.Passed == false) | .["Test Description"]' || echo "")
    if [ -n "$FAILED_TESTS" ]; then
        echo -e "\n${RED}=== Failed Tests ===${NC}" | tee -a "$LOG_FILE"
        echo "$FAILED_TESTS" | while read -r line; do echo -e "${RED}✗ $line${NC}" | tee -a "$LOG_FILE"; done
    fi
else
    PASSED_TESTS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Summary.Passed' || echo "0")
    TOTAL_TESTS=$(echo "$RESPONSE" | jq -r '.["Health Check"].Summary["Total tests"]' || echo "0")
    echo -e "\n${CYAN}----------------------------------------${NC}"
    echo -e "${CYAN}No failed tests data available for $TARGET. (Passed: $PASSED_TESTS, Total: $TOTAL_TESTS)${NC}"
    echo -e "${CYAN}----------------------------------------${NC}" | tee -a "$LOG_FILE"
fi

echo -e "\nResults saved to $LOG_FILE" | tee -a "$LOG_FILE"
# Made with ❤️ by vlaicu.io: Wrapping up with a smile!
