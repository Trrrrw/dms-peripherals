#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
destination="${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins/peripherals"
mkdir -p "$destination/bin"
for file in "$root"/plugin/*.qml "$root"/plugin/plugin.json; do cp "$file" "$destination/"; done
rm -rf "$destination/bin/native-hid" "$destination/licenses"
cp -a "$root/plugin/bin/native-hid" "$destination/bin/"
cp -a "$root/plugin/licenses" "$destination/"
cp "$root/plugin/bin/dms-peripherals" "$destination/bin/dms-peripherals.new"
mv "$destination/bin/dms-peripherals.new" "$destination/bin/dms-peripherals"
dms restart
