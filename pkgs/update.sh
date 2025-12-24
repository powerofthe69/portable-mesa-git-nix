#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Configuration
SOURCES_FILE="./sources.json"
TEMP_FILE=$(mktemp)

# Check for dependencies
command -v jq >/dev/null 2>&1 || { echo >&2 "Error: 'jq' is not installed."; exit 1; }
command -v nix-prefetch-git >/dev/null 2>&1 || { echo >&2 "Error: 'nix-prefetch-git' is not installed."; exit 1; }

# Ensure sources file exists
if [ ! -f "$SOURCES_FILE" ]; then
    echo "Error: $SOURCES_FILE not found!"
    exit 1
fi

# Copy original to temp to work on it
cp "$SOURCES_FILE" "$TEMP_FILE"

# Read keys (mesa, libdrm, etc.)
KEYS=$(jq -r 'keys[]' "$SOURCES_FILE")

UPDATED=0

for KEY in $KEYS; do
    # Extract current info
    URL=$(jq -r --arg k "$KEY" '.[$k].url' "$SOURCES_FILE")
    CURRENT_REV=$(jq -r --arg k "$KEY" '.[$k].rev // ""' "$SOURCES_FILE")

    # Check if URL exists
    if [ -z "$URL" ] || [ "$URL" == "null" ]; then
        echo "Skipping $KEY: No URL found."
        continue
    fi

    echo "Checking $KEY..."

    # Fetch latest info (capture JSON output)
    # We allow this to fail without exiting the whole script immediately if the network is down
    if ! PREFETCH_JSON=$(nix-prefetch-git --url "$URL" --quiet 2>/dev/null); then
        echo "  [ERROR] Failed to fetch $KEY"
        continue
    fi

    NEW_REV=$(echo "$PREFETCH_JSON" | jq -r '.rev')
    NEW_SHA=$(echo "$PREFETCH_JSON" | jq -r '.sha256')

    # Compare revisions
    if [ "$CURRENT_REV" != "$NEW_REV" ]; then
        # Use short hashes for readability
        SHORT_OLD=${CURRENT_REV:0:7}
        SHORT_NEW=${NEW_REV:0:7}

        echo "  [UPDATE] $KEY: ${SHORT_OLD:-empty} -> $SHORT_NEW"

        # Update the temporary file using jq
        # We write to a .tmp file then move it back to avoid race conditions
        jq --arg k "$KEY" --arg rev "$NEW_REV" --arg sha "$NEW_SHA" \
           '.[$k].rev = $rev | .[$k].sha256 = $sha' \
           "$TEMP_FILE" > "${TEMP_FILE}.tmp" && mv "${TEMP_FILE}.tmp" "$TEMP_FILE"

        UPDATED=1
    else
        echo "  [OK] $KEY is up to date."
    fi
done

# Finalize
if [ "$UPDATED" -eq 1 ]; then
    echo -e "\nWriting updates to $SOURCES_FILE..."
    mv "$TEMP_FILE" "$SOURCES_FILE"
    echo "Done."
else
    echo -e "\nNo updates found."
    rm "$TEMP_FILE"
fi
