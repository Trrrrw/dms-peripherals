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
