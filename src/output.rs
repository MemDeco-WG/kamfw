// KAMFW-RUST-STD-0001: std-only JSON/text output helpers

pub enum OutputMode {
    Text,
    Json,
}

pub fn eprintln_err(msg: &str) {
    eprintln!("{}", msg);
}

pub fn print_kv(key: &str, val: &str) {
    // stdout-only machine parseable
    println!("{}={}", key, val);
}

// -----------------------------------------------------------------------------
// Minimal JSON encoder (single-line)
// - Escapes: \ " \n \r \t and control chars as \u00XX
// - No pretty print
// -----------------------------------------------------------------------------

fn hex_nibble(n: u8) -> char {
    match n {
        0..=9 => (b'0' + n) as char,
        10..=15 => (b'a' + (n - 10)) as char,
        _ => '0',
    }
}

pub fn json_escape_str(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 8);
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let b = c as u32 as u8;
                out.push_str("\\u00");
                out.push(hex_nibble(b >> 4));
                out.push(hex_nibble(b & 0x0f));
            }
            _ => out.push(ch),
        }
    }
    out
}

pub fn json_str(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    out.push_str(&json_escape_str(s));
    out.push('"');
    out
}

pub fn json_bool(v: bool) -> &'static str {
    if v { "true" } else { "false" }
}

pub fn json_num_i32(v: i32) -> String {
    v.to_string()
}

pub fn json_arr(items: &[String]) -> String {
    let mut out = String::from("[");
    for (i, it) in items.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str(it);
    }
    out.push(']');
    out
}

pub fn json_obj(fields: &[(&str, String)]) -> String {
    let mut out = String::from("{");
    for (i, (k, v)) in fields.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str(&json_str(k));
        out.push(':');
        out.push_str(v);
    }
    out.push('}');
    out
}

pub fn print_json_line_raw(json: &str) {
    // stdout 单行 JSON
    println!("{}", json);
}
