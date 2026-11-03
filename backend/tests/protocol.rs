use std::{
    io::Write,
    process::{Command, Stdio},
};

#[test]
fn invalid_requests_do_not_terminate_the_stream() {
    let mut child = Command::new(env!("CARGO_BIN_EXE_dms-openmouse"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(
            b"not json\n{\"id\":7,\"method\":\"unknown\"}\n{\"id\":8,\"method\":\"get_status\"}\n",
        )
        .unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success());
    let replies: Vec<serde_json::Value> = String::from_utf8(output.stdout)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    assert_eq!(replies.len(), 3);
    assert_eq!(replies[0]["error"]["code"], "invalid_request");
    assert_eq!(replies[1]["id"], 7);
    assert_eq!(replies[1]["error"]["code"], "unknown_method");
    assert_eq!(replies[2]["id"], 8);
    assert_eq!(replies[2]["error"]["code"], "invalid_request");
}
