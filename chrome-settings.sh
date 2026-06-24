# I had tried to manage a browser with this setup using
# something like brave or ungoogled chromium, but I don't think the security
# is there (e.g. i was trying brave but the policy settings wouldn't work on a mac)
# for now the solution is on macs to use safari as the default browser and use
# chrome when needed for ui testing.
#
# these setting can be reverted by the following command:
# defaults delete com.google.Chrome && killall cfprefsd
#
# the following settings turn off all tracking, calling home & ai features from chrome

#!/bin/bash
set -euo pipefail

echo "🛡️  Initiating Google Chrome Lockdown (Zero-Trust Configuration)..."

# Ensure Chrome is completely closed before modifying preferences
echo "🛑 Closing Google Chrome..."
killall "Google Chrome" 2>/dev/null || true

# 1. Kill Telemetry & Data Collection
echo "🚫 Disabling Telemetry & Analytics..."
defaults write com.google.Chrome MetricsReportingEnabled -bool false
defaults write com.google.Chrome SafeBrowsingExtendedReportingEnabled -bool false
defaults write com.google.Chrome UserFeedbackAllowed -bool false

# 2. Kill Cloud-based "Smart" Features
echo "🚫 Disabling Cloud-based Typing & Search Suggestions..."
defaults write com.google.Chrome SearchSuggestEnabled -bool false
defaults write com.google.Chrome SpellCheckServiceEnabled -bool false

# 3. Kill the Ad-Tracking "Privacy Sandbox"
echo "🚫 Disabling Google Privacy Sandbox..."
defaults write com.google.Chrome PrivacySandboxAdTopicsEnabled -bool false
defaults write com.google.Chrome PrivacySandboxSiteEnabledAdsEnabled -bool false
defaults write com.google.Chrome PrivacySandboxAdMeasurementEnabled -bool false

# 4. Disable internal Credential Managers
echo "🚫 Disabling Native Credential Managers..."
defaults write com.google.Chrome PasswordManagerEnabled -bool false
defaults write com.google.Chrome AutofillAddressEnabled -bool false
defaults write com.google.Chrome AutofillCreditCardEnabled -bool false

# 5. Disable background processing & Google Sync
echo "🚫 Disabling Background Persistence & Cloud Sync..."
defaults write com.google.Chrome EnableMediaRouter -bool false
defaults write com.google.Chrome BackgroundModeEnabled -bool false
defaults write com.google.Chrome SyncDisabled -bool true

# 6. Local AI & LLM Killswitch
echo "🤖 Eradicating Local AI & Gemini Nano..."
defaults write com.google.Chrome GenAILocalFoundationalModelSettings -int 1
defaults write com.google.Chrome AIModeSettings -int 1
defaults write com.google.Chrome DevToolsGenAiSettings -int 2
defaults write com.google.Chrome CreateThemesSettings -int 2

# Flush the macOS preferences cache to apply immediately
echo "🧹 Flushing macOS preference cache..."
killall cfprefsd

echo "✅ Chrome lockdown complete!"
echo "👉 Open Chrome and visit 'chrome://policy' to verify."

