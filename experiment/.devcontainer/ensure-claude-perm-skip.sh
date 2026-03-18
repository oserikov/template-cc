#!/usr/bin/env bash
set -e
CONFIG="${CLAUDE_CONFIG_DIR:-/home/node/.claude}/settings.local.json"
mkdir -p "$(dirname "$CONFIG")"

# Merge in permissions.mode = "bypassPermissions", preserve existing .permissions.allow
(cat "$CONFIG" 2>/dev/null || echo '{}') | jq '
  .permissions = ((.permissions // {}) | .mode = "bypassPermissions" | .allow = (.allow // []))
  | .defaultMode = "bypassPermissions"
  | .skipDangerousModePermissionPrompt = true
' > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
