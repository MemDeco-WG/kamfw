// KAMFW-RUST-STD-0001: std-only CLI parser (no clap)

use crate::exit_codes;
use crate::output::OutputMode;

#[derive(Debug, Clone)]
pub struct Cli {
    pub mode: OutputMode,
    pub cmd: Command,
}

#[derive(Debug, Clone)]
pub enum Command {
    Env,
    Doctor,
    Version,
    Run { phase: String, args: Vec<String> },
    Help,
}

pub fn parse_args(args: Vec<String>) -> Result<Cli, (i32, String)> {
    // args[0] is program name
    let mut i = 1;
    let mut mode = OutputMode::Text;

    // global flags
    while i < args.len() {
        match args[i].as_str() {
            "--json" => {
                mode = OutputMode::Json;
                i += 1;
            }
            "-h" | "--help" => {
                return Ok(Cli { mode, cmd: Command::Help });
            }
            "--" => {
                i += 1;
                break;
            }
            s if s.starts_with('-') => {
                return Err((exit_codes::USAGE, format!("unknown flag: {s}")));
            }
            _ => break,
        }
    }

    if i >= args.len() {
        return Ok(Cli { mode, cmd: Command::Help });
    }

    let cmd = args[i].clone();
    i += 1;

    match cmd.as_str() {
        "env" => Ok(Cli { mode, cmd: Command::Env }),
        "doctor" => Ok(Cli { mode, cmd: Command::Doctor }),
        "version" | "--version" | "-V" => Ok(Cli { mode, cmd: Command::Version }),
        "run" => {
            if i >= args.len() {
                return Err((exit_codes::USAGE, "run requires <phase>".to_string()));
            }
            let phase = args[i].clone();
            i += 1;

            // pass-through args: accept optional "--" then rest
            if i < args.len() && args[i] == "--" {
                i += 1;
            }
            let passthrough = if i < args.len() { args[i..].to_vec() } else { Vec::new() };

            Ok(Cli {
                mode,
                cmd: Command::Run {
                    phase,
                    args: passthrough,
                },
            })
        }
        "help" => Ok(Cli { mode, cmd: Command::Help }),
        _ => Err((exit_codes::USAGE, format!("unknown command: {cmd}"))),
    }
}

pub fn print_usage_stderr() {
    eprintln!("kamfw device runtime\n\nUSAGE:\n  kamfw [--json] <command> [args...]\n\nCOMMANDS:\n  env\n  doctor\n  run <phase> -- [args...]\n  version\n\nFLAGS:\n  --json     output machine JSON to stdout\n  -h,--help  show help\n");
}
