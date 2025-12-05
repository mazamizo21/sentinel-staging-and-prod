# TruffleHog Scan Fix

## Issue
The TruffleHog scan was failing with `fatal: cannot create directory ... No space left on device`.
This was caused by the presence of a massive git repository (Azure-Sentinel, ~17GB) within the project structure (`sentinel-production/Project/Tools/Azure-Sentinel`).
When TruffleHog runs in default mode (or `git` mode), it attempts to clone the repository. If running in Docker, this cloning process (copying 17GB+ to the container's filesystem) exhausted the available disk space in the Docker environment.

## Solution
To fix this, we must:
1.  Run TruffleHog in `filesystem` mode instead of `git` mode. This scans the mounted volume directly without cloning/copying the data.
2.  Exclude the massive `Azure-Sentinel` directory from the scan to improve performance and avoid processing third-party code.
3.  Use an exclude file with regex patterns for TruffleHog v3+.

## How to Run the Scan
Use the provided script `run_safe_scan.sh` which executes the following command:

```bash
docker run --rm -v "$PWD:/pwd" trufflesecurity/trufflehog:latest filesystem /pwd \
    --exclude-paths "/pwd/Project/Docs/TruffleHog_Fix/trufflehog_exclude_patterns.txt" \
    --no-verification \
    --json
```

## Artifacts
-   `run_safe_scan.sh`: Script to run the scan safely.
-   `trufflehog_exclude_patterns.txt`: Regex patterns for exclusion.
-   `scan_results.txt`: Results of the last successful scan.
