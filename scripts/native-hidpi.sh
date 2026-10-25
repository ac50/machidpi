#!/bin/bash
# Native HiDPI for an external display on Apple Silicon — no app, no virtual
# display, no mirroring. Installs a display override with extra 2x
# ("looks like") resolutions; macOS reads it at boot and lists the modes in
# System Settings → Displays.
#
#   bash native-hidpi.sh install <vendor-hex> <product-hex> <native-width> <native-height> [WxH ...]
#   bash native-hidpi.sh uninstall <vendor-hex> <product-hex>
#
# Reboot after either command. Extra WxH arguments add "looks like" sizes,
# e.g. 1470x956 to match a 13.6" MacBook Air. The IDs are hex, as printed by
# `system_profiler SPDisplaysDataType -json` (display-vendor-id / -product-id).
# NAME="..." sets the name the override gives the monitor (default below).
set -eu

BASE=${OVERRIDES_BASE:-/Library/Displays/Contents/Resources/Overrides}
SUDO=${SUDO-sudo}
NAME=${NAME:-HiDPI Display}
# 16:9 sizes; only those that fit inside the panel's native resolution are kept.
DEFAULT_SIZES="2560x1440 2048x1152 1920x1080 1680x945 1600x900 1440x810 1280x720"

usage() {
  echo "usage: bash $0 install <vendor-hex> <product-hex> <native-width> <native-height> [WxH ...]"
  echo "       bash $0 uninstall <vendor-hex> <product-hex>"
  exit 1
}

hexid() {  # normalise "0x410C" / "410c" to "410c"; reject anything else
  local id
  id=$(printf '%s' "$1" | tr 'A-F' 'a-f')
  id=${id#0x}
  case "$id" in ''|*[!0-9a-f]*) echo "not a hex ID: $1" >&2; exit 1 ;; esac
  # EDID IDs are 16-bit: more than 4 hex digits is almost surely a decimal
  # number (ioreg prints decimals) — convert it with: printf '%x\n' NUMBER
  [ $(( 16#$id )) -le 65535 ] || { echo "ID $1 is too large for hex — decimal? convert with: printf '%x\\n' $1" >&2; exit 1; }
  printf '%x' "$((16#$id))"
}

valid_size() {  # WxH, both positive integers
  case "$1" in [1-9]*x[1-9]*) ;; *) return 1 ;; esac
  local w=${1%%x*} h=${1#*x}
  case "$w$h" in *[!0-9]*) return 1 ;; esac
}

be32() {  # 32-bit big-endian bytes of $1
  printf "\\x$(printf %02x $(( ($1 >> 24) & 255 )))\\x$(printf %02x $(( ($1 >> 16) & 255 )))\\x$(printf %02x $(( ($1 >> 8) & 255 )))\\x$(printf %02x $(( $1 & 255 )))"
}

entry() {  # one scale-resolutions entry: 2x backing width, height, HiDPI flag
  { be32 $(( $1 * 2 )); be32 $(( $2 * 2 )); be32 1; } | base64 | tr -d '\n'
}

[ $# -ge 3 ] || usage
VENDOR=$(hexid "$2")
PRODUCT=$(hexid "$3")
DIR=$BASE/DisplayVendorID-$VENDOR
FILE=$DIR/DisplayProductID-$PRODUCT

case "$1" in
install)
  [ $# -ge 5 ] || usage
  W=$4; H=$5; shift 5
  valid_size "${W}x${H}" || { echo "native size must be positive numbers: $W $H" >&2; exit 1; }
  for r in "$@"; do valid_size "$r" || { echo "not a WxH size: $r" >&2; exit 1; }; done
  data=""; seen=" "
  for r in $DEFAULT_SIZES "$@"; do
    w=${r%%x*}; h=${r#*x}
    case "$seen" in *" $r "*) continue ;; esac
    if [ "$w" -le "$W" ] && [ "$h" -le "$H" ]; then
      data="$data<data>$(entry "$w" "$h")</data>"
      seen="$seen$r "
      echo "  looks like ${w}x${h} (renders $((w * 2))x$((h * 2)))"
    else
      echo "  skipped ${w}x${h}: larger than the ${W}x${H} panel"
    fi
  done
  [ -n "$data" ] || { echo "no size fits a ${W}x${H} panel" >&2; exit 1; }
  name=$(printf '%s' "$NAME" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
  tmp=$(mktemp)
  cat > "$tmp" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>DisplayProductID</key><integer>$((16#$PRODUCT))</integer>
  <key>DisplayVendorID</key><integer>$((16#$VENDOR))</integer>
  <key>DisplayProductName</key><string>$name</string>
  <key>scale-resolutions</key><array>$data</array>
</dict>
</plist>
PLIST
  if command -v plutil >/dev/null; then plutil -lint "$tmp"; fi
  $SUDO mkdir -p "$DIR"
  BACKUP=$HOME/DisplayVendorID-$VENDOR-DisplayProductID-$PRODUCT.backup
  if [ -e "$FILE" ] && [ ! -e "$BACKUP" ]; then  # keep the first file replaced; it may be another tool's
    cp "$FILE" "$BACKUP"
    echo "  previous override saved to $BACKUP"
  fi
  $SUDO cp "$tmp" "$FILE"; $SUDO chmod 644 "$FILE"; rm -f "$tmp"
  [ -z "$SUDO" ] || $SUDO defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool YES
  echo "Installed $FILE — reboot, then pick a resolution in System Settings → Displays."
  ;;
uninstall)
  $SUDO rm -f "$FILE"; $SUDO rmdir "$DIR" 2>/dev/null || true
  echo "Removed $FILE — reboot to go back to the default resolutions."
  BACKUP=$HOME/DisplayVendorID-$VENDOR-DisplayProductID-$PRODUCT.backup
  if [ -e "$BACKUP" ]; then
    echo "$BACKUP holds the first override this script replaced."
    echo "If it came from another tool, restore it with:"
    echo "  sudo mkdir -p '$DIR' && sudo cp '$BACKUP' '$FILE'"
  fi
  ;;
*) usage ;;
esac
