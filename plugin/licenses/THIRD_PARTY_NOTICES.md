# Third-party notices

DMS Peripherals is an unofficial DMS plugin. OpenMouse is an upstream project, not the publisher of this plugin.

- OpenMouse mouse-protocol: AGPL-3.0-or-later. https://github.com/OpenMouse-Project/mouse-protocol
- OpenMouse keyboard-protocol: AGPL-3.0-or-later. https://github.com/OpenMouse-Project/keyboard-protocol
- OpenMouse Bridge HID adapter: MIT, from commit `30a3290ef88200f83a8083a88a3143d5e12eeaa8`. https://github.com/OpenMouse-Project/OpenMouse-Bridge
- node-hid: BSD-3-Clause. Includes HIDAPI and its original licensing options; see the bundled license files.
- pkg-prebuilds and node-addon-api: see their bundled license files.
- Rust backend: serde_json and transitive dependencies; see `backend/Cargo.lock` and the license texts in the runtime bundle.

The runtime dependency versions and Git revisions are pinned in `runtime/package-lock.json`.
The installable plugin carries license texts under `licenses/` and inside the dependency packages.
