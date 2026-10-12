#!/bin/bash
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode'

# Give the OS a split second to register the change
sleep 0.2

# Check the NEW system state
APPEARANCE=$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo "Light")

# Target config files
ALACRITTY_CONFIG="$HOME/.config/alacritty/alacritty.toml"
NVIM_THEME_FILE="$HOME/.config/nvim/lua/plugins/theme.lua"

echo "🌗 Switching environment to $APPEARANCE mode..."

# Update Alacritty and Neovim files, and notify running Neovim instances
if [ "$APPEARANCE" == "Dark" ]; then
  # Alacritty
  sed -i '' 's/background = ".*/background = "#1a1b26"/' "$ALACRITTY_CONFIG"
  sed -i '' 's/foreground = ".*/foreground = "#c0caf5"/' "$ALACRITTY_CONFIG"

  # Neovim (Update config file for next startup)
  sed -i '' 's/colorscheme = "tokyonight-day"/colorscheme = "tokyonight-night"/' "$NVIM_THEME_FILE"

  # Live-update any currently running Neovim instances
  for server in $(find "${TMPDIR-/tmp}" -name "nvim.*" -type s 2>/dev/null); do
    nvim --server "$server" --remote-send '<C-\><C-n>:set background=dark<CR>:colorscheme tokyonight-night<CR>' 2>/dev/null || true
  done

else
  # Alacritty
  sed -i '' 's/background = ".*/background = "#e1e2e7"/' "$ALACRITTY_CONFIG"
  sed -i '' 's/foreground = ".*/foreground = "#3760bf"/' "$ALACRITTY_CONFIG"

  # Neovim (Update config file for next startup)
  sed -i '' 's/colorscheme = "tokyonight-night"/colorscheme = "tokyonight-day"/' "$NVIM_THEME_FILE"

  # Live-update any currently running Neovim instances
  for server in $(find "${TMPDIR-/tmp}" -name "nvim.*" -type s 2>/dev/null); do
    nvim --server "$server" --remote-send '<C-\><C-n>:set background=light<CR>:colorscheme tokyonight-day<CR>' 2>/dev/null || true
  done
fi

echo "✅ Terminal and Editor synced."
