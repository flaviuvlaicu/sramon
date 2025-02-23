# Claroty SRA 4.0.2 Health Check API Script

This Bash script queries a health check API endpoint, processes the JSON response, and presents a detailed, color-coded summary of system health metrics. It is designed to monitor system status, including CPU load, memory usage, disk space, service statuses, and more, while logging the results to a timestamped file.

## Features

- **API Interaction**: Sends a GET request to a specified health check API endpoint.
- **Color-Coded Output**: Displays results in the terminal with ANSI colors (green for success, red for issues, etc.).
- **Comprehensive Reporting**: Summarizes test results, system metrics, service statuses, worker statuses, container statuses, and additional health checks.
- **Logging**: Saves all output to a timestamped log file (e.g., `health_check_2025-02-22_134512.log`).
- **Dependency Checks**: Verifies the presence of required tools (`jq`, `bc`) and provides warnings if they’re missing.
- **Error Handling**: Detects and reports issues like API connection failures or invalid JSON responses.

## Script Breakdown

### Sections

- **Initialization**:
  - Defines variables for the API endpoint, token, headers, and colors.
  - Sets up a timestamped log file.
- **API Request**:
  - Uses `curl` to fetch data from the API.
  - Checks for connection errors.
- **Dependency Checks**:
  - Verifies `jq` (required for JSON parsing) and `bc` (optional for floating-point math).
  - Warns if either is missing.
- **Response Validation**:
  - Ensures the API response is non-empty and valid JSON.
- **Health Check Summary**:
  - Reports total tests, passed/failed counts, start time, and duration.
- **System Metrics**:
  - Displays CPU load and memory usage with thresholds (< 1 for CPU, < 85% for memory).
  - Lists disk space usage, coloring results based on an 80% threshold.
- **Service and Worker Status**:
  - Checks if services and workers are running, highlighting failures.
- **Container Status**:
  - Monitors specific containers (`sra-debezium`, `sra-db`, `sra`).
- **Additional Checks**:
  - Validates DB sync, remote site connection, and SSH configuration.
- **SRA Statistics**:
  - Lists miscellaneous statistics from the API.
- **Failed Tests**:
  - Summarizes any failed tests at the end.
- **Logging**:
  - Appends all output to the log file using `tee`.

### Color Coding

- **Green**: Indicates success or healthy status.
- **Red**: Highlights failures or issues.
- **Blue**: Section headers.
- **Yellow**: Neutral or warning information.
