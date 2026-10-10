#!/usr/bin/env bash
# Morax Garage Safe Uninstallation Script
# Removes Morax Garage applications, preferences, and logs without requiring root privileges.

set -euo pipefail

echo "==> Uninstalling Morax Garage..."

# 1. Terminate running instances
killall "Morax Garage" 2>/dev/null || true
killall MoraxGarage 2>/dev/null || true
killall MoraxCockpit 2>/dev/null || true
killall "Morax Garage Menu" 2>/dev/null || true
killall MoraxGarageMenu 2>/dev/null || true
killall MoraxCockpitMenu 2>/dev/null || true

# 2. Remove log directory
for dir in "$HOME/Library/Logs/MoraxGarage" "$HOME/Library/Logs/MoraxCockpit"; do
    if [ -d "$dir" ]; then
        echo "Removing log directory: $dir"
        rm -rf "$dir"
    fi
done

# 3. Remove application support directory
for dir in "$HOME/Library/Application Support/MoraxGarage" "$HOME/Library/Application Support/MoraxCockpit"; do
    if [ -d "$dir" ]; then
        echo "Removing Application Support: $dir"
        rm -rf "$dir"
    fi
done

# 4. Remove preferences / defaults
echo "Removing user defaults preferences..."
defaults delete com.morax.garage 2>/dev/null || true
defaults delete com.morax.cockpit 2>/dev/null || true
defaults delete com.morax.garage.menu 2>/dev/null || true
defaults delete com.morax.cockpit.menu 2>/dev/null || true

# 5. Remove applications if installed in /Applications or ~/Applications
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "/Applications/Morax Garage.app" 2>/dev/null || true
    "$LSREGISTER" -u "/Applications/MoraxGarage.app" 2>/dev/null || true
    "$LSREGISTER" -u "/Applications/MoraxCockpit.app" 2>/dev/null || true
    "$LSREGISTER" -u "/Applications/MoraxCockpitMenu.app" 2>/dev/null || true
fi

rm -rf "/Applications/Morax Garage.app" 2>/dev/null || true
rm -rf "$HOME/Applications/Morax Garage.app" 2>/dev/null || true
rm -rf "/Applications/MoraxGarage.app" 2>/dev/null || true
rm -rf "$HOME/Applications/MoraxGarage.app" 2>/dev/null || true
rm -rf "/Applications/MoraxCockpit.app" 2>/dev/null || true
rm -rf "$HOME/Applications/MoraxCockpit.app" 2>/dev/null || true
rm -rf "/Applications/MoraxCockpitMenu.app" 2>/dev/null || true
rm -rf "$HOME/Applications/MoraxCockpitMenu.app" 2>/dev/null || true
rm -rf "/Applications/Morax Garage Menu.app" 2>/dev/null || true

echo "==> Morax Garage uninstalled successfully."
