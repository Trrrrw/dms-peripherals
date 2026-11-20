#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
target=${TARGET:-x86_64-unknown-linux-musl}
cargo_home=${CARGO_HOME:-$HOME/.cargo}
rustup_home=${RUSTUP_HOME:-$HOME/.rustup}
default_rustflags="-C linker=rust-lld --remap-path-prefix ${cargo_home}=/cargo --remap-path-prefix ${rustup_home}=/rustup --remap-path-prefix ${root}=/src"
RUSTFLAGS="${RUSTFLAGS:-$default_rustflags}" cargo build --manifest-path backend/Cargo.toml --locked --release --target "$target"
stage="$root/.build/runtime"
mkdir -p "$stage/native-hid/src" plugin/licenses
cp "backend/target/$target/release/dms-peripherals" "$stage/dms-peripherals"
cp runtime/package.json runtime/package-lock.json "$stage/native-hid/"
npm ci --prefix "$stage/native-hid" --cache "$root/.build/npm-cache" --allow-git=all --omit=dev --no-audit --no-fund
cp runtime/hid-device-adapter.mjs "$stage/native-hid/src/"
cp backend/helper/*.mjs "$stage/native-hid/src/"
# These directories contain generated runtime artifacts, never user state.
rm -rf plugin/bin
mv "$stage" plugin/bin
cp LICENSE THIRD_PARTY_NOTICES.md runtime/BRIDGE_LICENSE.txt plugin/licenses/
python3 scripts/collect-licenses.py
