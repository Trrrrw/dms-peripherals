# DMS OpenMouse

基于 [OpenMouse](https://github.com/OpenMouse-Project/openmouse) 的 DankMaterialShell（DMS）外设状态与控制插件，目前已实现只读后端，正在接入 DMS 界面。

- 使用 QML 编写 DMS 界面
- 使用 Rust 编写独立后端，直接依赖 OpenMouse Bridge crate，复用其设备控制能力
- QML 与 Rust 后端通过标准输入输出传递 JSON，无需本地 HTTP 服务或 C ABI

部分设备仍需 OpenMouse 的 Node.js helper 和协议库，具体设备与功能支持范围待验证。

## 当前进度

已添加只读 Rust 后端，支持 `list_devices` 和 `get_status`，已添加 DMS 面板电量及状态弹窗，暂未实现设备设置写入。
Bridge 固定到 `30a3290ef88200f83a8083a88a3143d5e12eeaa8`，直接调用公开的 `drivers` API，不启动 Bridge HTTP 服务或托盘。

## 构建与验证

```sh
cargo build --manifest-path backend/Cargo.toml
cargo test --manifest-path backend/Cargo.toml
```

Linux 构建仍会编译上游 crate 的 GUI 依赖，需要 GTK 3、Cairo、AppIndicator、libudev 等开发库及 `pkg-config`。
当前环境已通过默认硬件功能的构建与协议测试。已枚举到 `ATK:373b:1085`；
用户配置 udev 规则并重插接收器后，已成功读取 VXE R1 SE+ 的电量、DPI 和回报率。
QML 通信层已验证能接收后端响应；完整 DMS 界面尚待实际加载与视觉验证。

仅验证通信层（禁用硬件，设备请求明确返回 `hardware_disabled`）：

```sh
cargo test --manifest-path backend/Cargo.toml --no-default-features
cargo clippy --manifest-path backend/Cargo.toml --no-default-features -- -D warnings
```

## 通信协议

后端逐行读取 stdin，每行返回一个 JSON 对象并立即刷新 stdout；EOF 时退出。
`id` 为字符串或非负整数。当前请求示例：

```json
{"id":1,"method":"list_devices"}
{"id":2,"method":"get_status","device_id":"ATK:373b:1085"}
```

`device_id` 应使用枚举返回值。响应为 `{"id":1,"result":...}` 或
`{"id":1,"error":{"code":"...","message":"..."}}`。
状态包含电量、充电状态、DPI、回报率和切换模式；上游未提供的可选字段为 `null`。
Bridge 枚举失败时会返回空列表，因此空列表不能区分无设备与枚举失败。
状态读取目前按品牌选择设备；同品牌存在多个设备时后端拒绝读取，防止误报。

大部分品牌的状态读取需要 Node.js 和上游 `native-hid` helper 的完整依赖。
开发时 Bridge 会寻找其源码目录下的 helper；发布时需把准备好的 `native-hid/`
放在后端可执行文件旁，具体布局见上游 `src/drivers/native_hid.rs`。
仅下载 Rust crate 不会自动安装 helper 的 npm 依赖。
HID 权限问题应按具体 VID/PID 配置，避免授予全部设备访问权限。

## DMS 插件

`plugin/` 是插件目录。横向、纵向面板显示电量，点击打开设备状态弹窗。
每 30 秒刷新第一台识别到的设备，读取失败时保留上次成功读数，并在弹窗显示错误及上次成功时间，后端退出后每 5 秒重试。
当前上游可能返回 CID/MID 探测失败；此时显示错误，等待下次刷新。

部署目录必须包含：

```text
openMouse/
  plugin.json
  Main.qml
  MouseService.qml
  Settings.qml
  bin/
    dms-openmouse
    native-hid/       # 完整 helper，包含 node_modules
```

本工作区已准备 `plugin/bin/` 的开发运行文件，二进制和 npm 依赖不纳入 Git。
重新构建后更新二进制：

```sh
mkdir -p plugin/bin
cp backend/target/debug/dms-openmouse plugin/bin/
```

将插件目录复制到 DMS 用户插件目录后，在插件设置中启用 OpenMouse，再在面板布局中添加它：

```sh
mkdir -p ~/.config/dms/plugins/openMouse
cp -a plugin/. ~/.config/dms/plugins/openMouse/
```

准备 helper 时，应使用上面固定的 Bridge commit，进入其 `native-hid/` 目录运行
`npm ci`（npm 12 需要本次命令添加 `--allow-git=all`），然后将整个目录复制到 `plugin/bin/native-hid/`。

设备权限规则（`/etc/udev/rules.d/70-dms-openmouse.rules`）：

```udev
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="373b", ATTRS{idProduct}=="1085", TAG+="uaccess"
```

执行 `sudo udevadm control --reload-rules` 后重插接收器。此规则仅覆盖该 VID/PID。

## 下一步

1. 在运行中的 DMS 中验证横竖面板、弹窗布局和拔插恢复
2. 读取稳定后加入设备选择及设置写入

## Node.js 运行时

Node.js ≥20 是用户提供的系统依赖，需要在 DMS 进程的 PATH 中可用。
插件通过 `dependencies: ["node"]` 声明依赖，并在启用前使用 `startupCheck`
执行 `node --version` 检查可用性和版本；检查失败时显示安装指引。
插件不下载、复制或自动安装 Node.js，也不加载用户的 shell/nvm 初始化配置。

helper 和其 JS/npm 依赖由发布流程准备并放在插件自己的 `bin/native-hid/` 中，
用户运行插件无需 npm。卸载插件目录会移除这些私有文件，系统 Node.js 保留。
系统 udev 规则位于插件目录外，需要单独管理。

检查启动依赖逻辑：

```sh
python3 tests/check-startup.py
```

设置页可扫描当前连接的设备，添加并选择面板使用的设备，也可移除已保存项。该功能保存设备选择，不执行蓝牙配对；未配置选择时提示在设置中添加设备，不自动选择设备。
