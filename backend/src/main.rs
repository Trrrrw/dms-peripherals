use serde_json::{Value, json};
use std::io::{self, BufRead, Write};

fn error(id: Value, code: &str, message: &str) -> Value {
    json!({"id": id, "error": {"code": code, "message": message}})
}

fn respond(line: &str) -> Value {
    let Ok(request) = serde_json::from_str::<Value>(line) else {
        return error(Value::Null, "invalid_request", "Expected a JSON object");
    };
    let id = request.get("id").cloned().unwrap_or(Value::Null);
    if !(id.is_string() || id.is_u64()) {
        return error(
            Value::Null,
            "invalid_request",
            "id must be a string or unsigned integer",
        );
    }
    match request.get("method").and_then(Value::as_str) {
        Some("list_devices") => list_devices(id),
        Some("get_details" | "set_setting") => device_control(id, &request),
        Some("get_status") => match request
            .get("device_id")
            .and_then(Value::as_str)
            .filter(|v| !v.is_empty())
        {
            Some(device_id) => get_status(id, device_id),
            None => error(id, "invalid_request", "device_id is required"),
        },
        Some(_) => error(id, "unknown_method", "Unknown method"),
        None => error(id, "invalid_request", "method is required"),
    }
}

#[cfg(feature = "hardware")]
fn device_control(id: Value, request: &Value) -> Value {
    use std::process::{Command, Stdio};
    let Some(device_id) = request
        .get("device_id")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
    else {
        return error(id, "invalid_request", "device_id is required");
    };
    if !openmouse_bridge::drivers::detect_mice()
        .iter()
        .any(|device| device.device_id == device_id)
    {
        return error(
            id,
            "unsupported",
            "Device not connected or not supported by Bridge",
        );
    }
    let result = (|| -> io::Result<Value> {
        let executable = std::env::current_exe()?;
        let helper = executable
            .parent()
            .unwrap()
            .join("native-hid/src/control.mjs");
        let mut child = Command::new("node")
            .arg(helper)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;
        let mut input = child.stdin.take().unwrap();
        serde_json::to_writer(&mut input, request)?;
        drop(input);
        let output = child.wait_with_output()?;
        if !output.status.success() {
            return Err(io::Error::other(
                String::from_utf8_lossy(&output.stderr).to_string(),
            ));
        }
        Ok(serde_json::from_slice(&output.stdout)?)
    })();
    match result {
        Ok(result) => json!({"id": id, "result": result}),
        Err(err) => error(id, "device_operation_failed", &err.to_string()),
    }
}

#[cfg(not(feature = "hardware"))]
fn device_control(id: Value, _: &Value) -> Value {
    list_devices(id)
}

#[cfg(all(feature = "hardware", target_os = "linux"))]
fn usb_ids(uevent: &str) -> Option<(u16, u16)> {
    let id = uevent
        .lines()
        .find_map(|line| line.strip_prefix("HID_ID="))?;
    let parts: Vec<_> = id.split(':').collect();
    if parts.len() != 3 || parts[0] != "0003" {
        return None;
    }
    Some((
        u16::from_str_radix(parts[1], 16).ok()?,
        u16::from_str_radix(parts[2], 16).ok()?,
    ))
}

#[cfg(all(feature = "hardware", target_os = "linux"))]
fn matches_filter(filter: &Value, vid: u16, pid: u16, page: u16, usage: u16) -> bool {
    [
        ("vendorId", vid),
        ("productId", pid),
        ("usagePage", page),
        ("usage", usage),
    ]
    .into_iter()
    .all(|(key, value)| {
        filter
            .get(key)
            .is_none_or(|expected| expected.as_u64() == Some(u64::from(value)))
    })
}

#[cfg(all(feature = "hardware", target_os = "linux"))]
fn list_devices(id: Value) -> Value {
    let supported = openmouse_bridge::drivers::detect_mice();
    let api = match hidapi::HidApi::new() {
        Ok(api) => api,
        Err(err) => return error(id, "enumeration_failed", &err.to_string()),
    };
    let filters: Vec<Value> = serde_json::from_str(include_str!("../data/hid-filters.json"))
        .expect("embedded HID filters");
    let entries = match std::fs::read_dir("/sys/class/hidraw") {
        Ok(entries) => entries,
        Err(err) => return error(id, "enumeration_failed", &err.to_string()),
    };
    let mut devices: Vec<Value> = Vec::new();
    for entry in entries.flatten() {
        let Ok(info) = std::fs::read_to_string(entry.path().join("device/uevent")) else {
            continue;
        };
        let Some((vid, pid)) = usb_ids(&info) else {
            continue;
        };
        let name = info
            .lines()
            .find_map(|line| line.strip_prefix("HID_NAME="))
            .unwrap_or("HID device");
        let serial = info
            .lines()
            .find_map(|line| line.strip_prefix("HID_UNIQ="))
            .unwrap_or("");
        let tail = if serial.is_empty() {
            format!("{vid:04x}:{pid:04x}")
        } else {
            serial.to_owned()
        };
        let visible = api.device_list().any(|device| {
            device.vendor_id() == vid
                && device.product_id() == pid
                && device.serial_number().unwrap_or_default() == serial
                && filters.iter().any(|filter| {
                    matches_filter(
                        filter,
                        device.vendor_id(),
                        device.product_id(),
                        device.usage_page(),
                        device.usage(),
                    )
                })
        });
        if !visible {
            continue;
        }
        let matched = supported.iter().find(|device| {
            device
                .device_id
                .split_once(':')
                .is_some_and(|(_, value)| value == tail)
        });
        let device_id = matched
            .map(|device| device.device_id.clone())
            .unwrap_or_else(|| format!("hid:{vid:04x}:{pid:04x}:{serial}"));
        let path = format!("/dev/{}", entry.file_name().to_string_lossy());
        // Open only to check access; never send reports while scanning.
        let denied = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(&path)
            .err()
            .is_some_and(|err| err.kind() == std::io::ErrorKind::PermissionDenied);
        if let Some(device) = devices
            .iter_mut()
            .find(|device| device["device_id"] == device_id)
        {
            if denied {
                device["permission_required"] = json!(true);
            }
            continue;
        }
        devices.push(
            json!({"device_id": device_id, "name": name, "vendor_id": format!("{vid:04x}"),
            "product_id": format!("{pid:04x}"), "supported": true, "permission_required": denied}),
        );
    }
    devices.sort_by(|a, b| a["device_id"].as_str().cmp(&b["device_id"].as_str()));
    json!({"id": id, "result": devices})
}

#[cfg(all(feature = "hardware", not(target_os = "linux")))]
fn list_devices(id: Value) -> Value {
    let devices: Vec<Value> = openmouse_bridge::drivers::detect_mice()
        .into_iter()
        .map(|device| json!({"device_id": device.device_id, "name": device.name}))
        .collect();
    json!({"id": id, "result": devices})
}

#[cfg(feature = "hardware")]
fn get_status(id: Value, device_id: &str) -> Value {
    let devices = openmouse_bridge::drivers::detect_mice();
    if !devices.iter().any(|device| device.device_id == device_id) {
        return error(id, "device_not_found", "Device is not connected");
    }
    // Bridge selects by brand, so refuse ambiguous same-brand devices.
    let brand = device_id.split(':').next();
    if devices
        .iter()
        .filter(|device| device.device_id.split(':').next() == brand)
        .count()
        > 1
    {
        return error(
            id,
            "ambiguous_device",
            "Bridge cannot target one of multiple same-brand devices",
        );
    }
    match openmouse_bridge::drivers::read_status(device_id) {
        Ok(Some(status)) => json!({"id": id, "result": {
            "device_id": device_id, "battery_percent": status.battery.percent,
            "charging": status.battery.charging, "reported_name": status.battery.reported_name,
            "dpi": status.dpi, "polling_rate_hz": status.polling_rate_hz,
            "switch_mode": status.switch_mode
        }}),
        Ok(None) => error(id, "unsupported", "Bridge returned no readable status"),
        Err(err) => error(id, "read_failed", &format!("{err:#}")),
    }
}

#[cfg(not(feature = "hardware"))]
fn list_devices(id: Value) -> Value {
    error(
        id,
        "hardware_disabled",
        "Build with the hardware feature to access devices",
    )
}

#[cfg(not(feature = "hardware"))]
fn get_status(id: Value, _: &str) -> Value {
    list_devices(id)
}

fn main() -> io::Result<()> {
    let stdout = io::stdout();
    let mut output = stdout.lock();
    for line in io::stdin().lock().lines() {
        let response = respond(&line?);
        serde_json::to_writer(&mut output, &response)?;
        writeln!(output)?;
        output.flush()?;
    }
    Ok(())
}

#[cfg(all(test, feature = "hardware", target_os = "linux"))]
mod tests {
    #[test]
    fn filters_use_protocol_identity_and_usage_not_permissions() {
        let filter = serde_json::json!({"vendorId": 0x373b, "usagePage": 0xff02, "usage": 2});
        assert!(super::matches_filter(&filter, 0x373b, 0x1085, 0xff02, 2));
        assert!(!super::matches_filter(&filter, 0x3837, 0x3033, 0xff02, 2));
        assert!(!super::matches_filter(&filter, 0x373b, 0x1085, 1, 2));
    }
    #[test]
    fn parses_usb_ids_without_requiring_device_access() {
        assert_eq!(
            super::usb_ids("HID_ID=0003:0000373B:00001085\nHID_NAME=Mouse\n"),
            Some((0x373b, 0x1085))
        );
        assert_eq!(super::usb_ids("HID_ID=invalid\n"), None);
    }
}
