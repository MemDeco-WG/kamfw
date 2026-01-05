mod cli;
mod doctor;
mod env;
mod exit_codes;
mod output;
mod util_fs;

use crate::cli::{Command, Cli};
use crate::output::{
    eprintln_err, json_arr, json_bool, json_num_i32, json_obj, json_str, print_json_line_raw, print_kv,
    OutputMode,
};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let cli = match cli::parse_args(args) {
        Ok(c) => c,
        Err((code, msg)) => {
            eprintln_err(&msg);
            cli::print_usage_stderr();
            std::process::exit(code);
        }
    };

    let code = dispatch(cli);
    std::process::exit(code);
}

fn dispatch(cli: Cli) -> i32 {
    match cli.cmd {
        Command::Help => {
            cli::print_usage_stderr();
            exit_codes::OK
        }
        Command::Version => match cli.mode {
            OutputMode::Text => {
                // 人类提示 -> stderr
                eprintln!("kamfw {}", env!("CARGO_PKG_VERSION"));
                exit_codes::OK
            }
            OutputMode::Json => {
                let line = json_obj(&[
                    ("ok", json_bool(true).to_string()),
                    ("version", json_str(env!("CARGO_PKG_VERSION"))),
                ]);
                print_json_line_raw(&line);
                exit_codes::OK
            }
        },
        Command::Env => cmd_env(cli.mode),
        Command::Doctor => cmd_doctor(cli.mode),
        Command::Run { phase, args } => cmd_run(cli.mode, &phase, &args),
    }
}

fn cmd_env(mode: OutputMode) -> i32 {
    let e = match env::load() {
        Ok(v) => v,
        Err(err) => {
            match mode {
                OutputMode::Text => {
                    // 只允许 KEY=VALUE 上 stdout，所以错误走 stderr
                    eprintln_err(&format!("ERROR: {}", err.message));
                }
                OutputMode::Json => {
                    let line = json_obj(&[
                        ("ok", json_bool(false).to_string()),
                        ("error", json_str(&err.message)),
                        ("exit_code", json_num_i32(err.code)),
                    ]);
                    print_json_line_raw(&line);
                }
            }
            return err.code;
        }
    };

    match mode {
        OutputMode::Text => {
            // stdout 只 KEY=VALUE
            print_kv("KAM_HOME", &e.kam_home.to_string_lossy());
            print_kv("MODDIR", &e.moddir.to_string_lossy());
            print_kv("KAMFW_MANAGER", &e.manager);
            print_kv("KAM_HOME_EQ_MODDIR", "1");

            print_kv("KAM_LOCAL_BIN", &e.local_bin.to_string_lossy());
            print_kv("KAM_CONFIG_DIR", &e.config_dir.to_string_lossy());
            print_kv("KAM_STATE_DIR", &e.state_dir.to_string_lossy());
            print_kv("KAM_CACHE_DIR", &e.cache_dir.to_string_lossy());
            print_kv("KAM_LOG_DIR", &e.log_dir.to_string_lossy());
            print_kv("KAM_TMP_DIR", &e.tmp_dir.to_string_lossy());
        }
        OutputMode::Json => {
            // stdout 单行 JSON
            let line = json_obj(&[
                ("ok", json_bool(true).to_string()),
                ("kam_home", json_str(&e.kam_home.to_string_lossy())),
                ("moddir", json_str(&e.moddir.to_string_lossy())),
                ("manager", json_str(&e.manager)),
                ("kam_home_eq_moddir", json_bool(true).to_string()),
                ("local_bin", json_str(&e.local_bin.to_string_lossy())),
                ("config_dir", json_str(&e.config_dir.to_string_lossy())),
                ("state_dir", json_str(&e.state_dir.to_string_lossy())),
                ("cache_dir", json_str(&e.cache_dir.to_string_lossy())),
                ("log_dir", json_str(&e.log_dir.to_string_lossy())),
                ("tmp_dir", json_str(&e.tmp_dir.to_string_lossy())),
            ]);
            print_json_line_raw(&line);
        }
    }

    exit_codes::OK
}

fn cmd_doctor(mode: OutputMode) -> i32 {
    let (code, checks) = doctor::run_doctor(env::load());

    match mode {
        OutputMode::Text => {
            for c in &checks {
                if c.ok {
                    eprintln!("OK {}: {}", c.name, c.detail);
                } else {
                    eprintln!("FAIL {}: {}", c.name, c.detail);
                }
            }
        }
        OutputMode::Json => {
            let mut items: Vec<String> = Vec::with_capacity(checks.len());
            for c in &checks {
                let obj = json_obj(&[
                    ("name", json_str(c.name)),
                    ("ok", json_bool(c.ok).to_string()),
                    ("detail", json_str(&c.detail)),
                ]);
                items.push(obj);
            }
            let checks_json = json_arr(&items);
            let line = json_obj(&[
                ("ok", json_bool(code == exit_codes::OK).to_string()),
                ("exit_code", json_num_i32(code)),
                ("checks", checks_json),
            ]);
            print_json_line_raw(&line);
        }
    }

    code
}

fn cmd_run(mode: OutputMode, phase: &str, args: &[String]) -> i32 {
    let e = match env::load() {
        Ok(v) => v,
        Err(err) => {
            match mode {
                OutputMode::Text => eprintln_err(&format!("ERROR: {}", err.message)),
                OutputMode::Json => {
                    let line = json_obj(&[
                        ("ok", json_bool(false).to_string()),
                        ("error", json_str(&err.message)),
                        ("exit_code", json_num_i32(err.code)),
                    ]);
                    print_json_line_raw(&line);
                }
            }
            return err.code;
        }
    };

    match mode {
        OutputMode::Text => {
            // stdout 只 KEY=VALUE；其余提示走 stderr
            print_kv("KAMFW_PHASE", phase);
            // args 用单行 repr：用空格 join（保持可解析简单性）；更复杂需求走 --json
            let joined = args.join(" ");
            print_kv("KAMFW_ARGS", &joined);

            // 人类提示/调试走 stderr
            eprintln!("planned phase={}", phase);
        }
        OutputMode::Json => {
            let mut arg_items: Vec<String> = Vec::with_capacity(args.len());
            for a in args {
                arg_items.push(json_str(a));
            }
            let args_json = json_arr(&arg_items);

            let line = json_obj(&[
                ("ok", json_bool(true).to_string()),
                ("phase", json_str(phase)),
                ("args", args_json),
                ("status", json_str("planned")),
                ("kam_home", json_str(&e.kam_home.to_string_lossy())),
                ("moddir", json_str(&e.moddir.to_string_lossy())),
            ]);
            print_json_line_raw(&line);
        }
    }

    exit_codes::OK
}
