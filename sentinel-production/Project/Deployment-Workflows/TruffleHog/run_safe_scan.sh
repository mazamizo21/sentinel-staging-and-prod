#!/bin/bash
# Fix and Scan script for TruffleHog
# This script runs TruffleHog in filesystem mode to avoid "No space left on device" errors
# caused by cloning the massive Azure-Sentinel repository (17GB+).

LOG_FILE="sentinel-production/Project/Deployment-Workflows/TruffleHog/scan_results.txt"
mkdir -p sentinel-production/Project/Deployment-Workflows/TruffleHog

echo "=== Starting TruffleHog Fix & Scan ===" | tee -a "$LOG_FILE"

# 1. Prune Docker to ensure we have space (optional, but good practice)
echo "Cleaning up Docker system..." | tee -a "$LOG_FILE"
# We use --force to avoid interactive prompt
docker system prune -f

# 2. Run TruffleHog in filesystem mode
# -v "$PWD:/pwd": Mount current directory to /pwd in container
# filesystem /pwd: Scan the mounted directory directly (no git clone)
# --exclude-paths: Exclude the massive Azure-Sentinel folder and .git
echo "Running TruffleHog scan (excluding Azure-Sentinel)..." | tee -a "$LOG_FILE"

docker run --rm -v "$PWD:/pwd" trufflesecurity/trufflehog:latest filesystem /pwd \
    --exclude-paths "/pwd/sentinel-production/Project/Deployment-Workflows/TruffleHog/trufflehog_exclude_patterns.txt" \
    --no-verification \
    --json \
    >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "Scan completed successfully. Results in $LOG_FILE" | tee -a "$LOG_FILE"
else
    echo "Scan failed with exit code $EXIT_CODE. Check $LOG_FILE" | tee -a "$LOG_FILE"
fi

# 3. Cleanup diagnostics scripts
if [ -f "sentinel-production/Project/Deployment-Workflows/TruffleHog/diagnose_space.sh" ]; then
    mv sentinel-production/Project/Deployment-Workflows/TruffleHog/diagnose_space.sh sentinel-production/Project/Deployment-Workflows/TruffleHog/diagnose_space.sh.outofscope
fi
if [ -f "sentinel-production/Project/Deployment-Workflows/TruffleHog/investigate_repo.sh" ]; then
    mv sentinel-production/Project/Deployment-Workflows/TruffleHog/investigate_repo.sh sentinel-production/Project/Deployment-Workflows/TruffleHog/investigate_repo.sh.outofscope
fi
if [ -f "sentinel-production/Project/Deployment-Workflows/TruffleHog/investigate_repo_2.sh" ]; then
    mv sentinel-production/Project/Deployment-Workflows/TruffleHog/investigate_repo_2.sh sentinel-production/Project/Deployment-Workflows/TruffleHog/investigate_repo_2.sh.outofscope
fi

echo "Cleanup complete." | tee -a "$LOG_FILE"
