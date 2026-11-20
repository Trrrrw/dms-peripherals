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
    if request["method"] != "list_devices"
        && request
            .get("device_id")
            .and_then(Value::as_str)
            .is_none_or(str::is_empty)
    {
        return error(id, "invalid_request", "device_id is required");
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

#[cfg(feature = "hardware")]
fn list_devices(id: Value) -> Value {
    device_control(id, &json!({"method":"list_devices"}))
}

#[cfg(feature = "hardware")]
fn get_status(id: Value, device_id: &str) -> Value {
    let reply = device_control(
        id.clone(),
        &json!({"method":"get_details","device_id":device_id}),
    );
    let Some(value) = reply.get("result").and_then(|result| result.get("status")) else {
        return reply;
    };
    json!({"id":id,"result":{"device_id":device_id,"reported_name":value["name"],
        "battery_percent":value["batteryPercent"],"charging":value["batteryState"] == "Charging",
        "dpi":value["dpi"],"polling_rate_hz":value["pollingRateHz"]}})
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
