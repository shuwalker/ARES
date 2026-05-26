#!/bin/bash
# NAS Auto-Recovery Script — Mac Studio
# Attempts to mount Jenkins_Robotics SMB share from UNAS-Pro.
# Run via cron or launchd. Falls back gracefully when unavailable.

NAS_HOST="10.15.0.190"
NAS_SHARE="Jenkins_Robotics"
MOUNT_POINT="/Volumes/Jenkins_Robotics"
CRED_FILE="$HOME/.hermes/nas_creds.txt"  # user:password on single line
LOG_FILE="$HOME/ARES_Brain/logs/nas_mount.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Already mounted?
if mount | grep -q "$MOUNT_POINT"; then
    exit 0  # already up, nothing to do
fi

# Make mount point if missing
if [ ! -d "$MOUNT_POINT" ]; then
    mkdir -p "$MOUNT_POINT" 2>/dev/null
fi

# Try with credentials file
if [ -f "$CRED_FILE" ]; then
    log "Attempting authenticated mount to //$NAS_HOST/$NAS_SHARE"
    CREDS=$(cat "$CRED_FILE")
    mount -t smbfs "//${CREDS}@${NAS_HOST}/${NAS_SHARE}" "$MOUNT_POINT" 2>&1 | tee -a "$LOG_FILE"
    if mount | grep -q "$MOUNT_POINT"; then
        log "SUCCESS: NAS mounted at $MOUNT_POINT"
        exit 0
    fi
fi

# Try guest access as fallback
log "Attempting guest mount to //$NAS_HOST/$NAS_SHARE"
mount -t smbfs "//guest@${NAS_HOST}/${NAS_SHARE}" "$MOUNT_POINT" 2>&1 | tee -a "$LOG_FILE"

if mount | grep -q "$MOUNT_POINT"; then
    log "SUCCESS: NAS mounted via guest at $MOUNT_POINT"
    exit 0
fi

log "FAILED: Could not mount NAS. Credentials file may be needed at $CRED_FILE"
exit 1
