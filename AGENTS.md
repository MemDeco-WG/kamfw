你是 MagicNet/KAM 框架的自动化开发助手（Contributor Guidelines & Best Practices）

总体原则
- 在修改/新增代码前，先在 `src/MagicNet/lib/kamfw` 中搜索并复用现有函数（使用 `grep`）。优先复用框架内已有 helper，避免重复实现。
- 不要在安装脚本（如 `customize.sh` / hooks）中定义通用 helper；若需新 helper，请创建 `src/MagicNet/lib/kamfw/__name__.sh` 并以 `import __name__` 引入。严格禁止在 helper 或模块内部实现对缺失运行时功能的隐式回退（例如：自动注入 `print()` shim、在模块中写入 `printf` 回退逻辑或静默补齐）。由调用方显式 `import`；关键依赖缺失时应采用 fail-fast（`abort`）策略并使用 i18n 提示，而不是悄悄补全或忽略错误。（EN: Do not add inline fallback shims inside helpers. Implement compatibility shims as explicit, importable helpers; prefer fail-fast on missing critical dependencies.）
- 所有对用户可见文本必须使用 i18n：用 `set_i18n` 注册键值，用 `i18n` / `t()` 获取并做占位替换。新增 i18n 键必须在提交说明中列出。
- 在调用外部命令前请用 `command -v` 检查，关键依赖（如处理 ZIP 的 `unzip`/`zipinfo`）缺失时应 `abort`（fail-fast）并使用 i18n 键提示。
- 网络下载必须做完整性校验（至少 sha256）；需要时要求签名验证并记录验证过程（不要硬编码验证密钥到仓库）。
- 默认不覆盖用户配置：使用 `confirm_update_file` / `confirm` 等交互逻辑；在非交互环境（CI/no-TTY）使用安全默认（不覆盖，或生成 `.update` 文件供人工处理）。
- 禁止硬编码密钥、未经授权改写系统路径、启动长期后台进程或在未告知用户时自动降级。
- 提交变更时（PR）必须包含：变更说明、列出的新增 i18n 键、以及详细测试/验证步骤。

输出约定（控制台）
- 所有屏幕输出请使用框架提供的 `print`（或 `info`/`warn`/`error` 等封装）而不是直接用 `printf`，以便在不同环境（TTY/非TTY/Android UI）下统一处理。
- 仅在必须做格式化或无换行的控制（如光标移动 `ANSI_CURSOR_UP`）时，才保留使用 `printf` 的场景，并在注释中注明原因。

日志（logging）规范
- 日志相关 helper 已拆分到 `src/MagicNet/lib/kamfw/logging.sh`：
  - 提供 `info`/`warn`/`error`/`debug`/`success` 等 wrapper（输出到屏幕并写入日志文件）。
  - 支持 `KAM_LOGLEVEL` 环境变量（或 `set_loglevel <LEVEL>`），LEVEL 支持 `ERROR|WARN|INFO|DEBUG`（默认 INFO）；兼容 `KAM_DEBUG=1`（等同 DEBUG）。
  - `log()` 保留向文件写入与轮转（rotate）功能，记录时间戳与去 ANSI 色彩后的纯文本。
  - wrapper（如 `debug()`）会依据 LOGLEVEL 决定是否进行控制台/日志写入；直接调用 `log` 仍然可用（向后兼容）。
- 日志文件：使用 `KAM_LOGFILE`（默认 `$MODDIR/kam.log`），轮转大小可通过 `KAM_LOG_ROTATE_SIZE` 配置（支持 K/M/G 后缀）。

at-exit（退出）钩子
- 提供通用 at-exit helper：`src/MagicNet/lib/kamfw/__at_exit__.sh`，API 说明：
  - `at_exit_add '<cmd_or_fn>'`：注册 handler（唯一、按添加顺序执行）。
  - `at_exit_remove '<cmd>'`、`at_exit_list`、`at_exit_clear`：管理 handlers。
  - `at_exit_register_trap` / `at_exit_unregister_trap`：注册/注销 EXIT trap（idempotent）。
  - 安装（install-on-exit）逻辑由安装器模块提供（参见 `__installer_install_from_filters`）。要在退出时安装文件，请使用 `installer schedule`（会显式注册处理器），或在需要时显式调用 `at_exit_add '__installer_install_from_filters'` 来注册处理器。
  - 注册 trap 时尽量捕获并在处理完自己的 handlers 后调用之前的 trap（best-effort）。
- 注册 trap 时尽量捕获并在处理完自己的 handlers 后调用之前的 trap（best-effort）以兼容其他脚本的退出钩子。
- handlers 在退出时可在子 shell 中执行以隔离环境（实现中为子 shell 执行 `eval`，并忽略单个 handler 的错误）。

安装过滤（install filters）
- 使用顺序：`install_exclude` → `install_include` → `install_check`（`include` 可以覆盖先前的 `exclude`）。
- `install_check` 用于预览：在调用 `install` 操作前务必运行 `install_check`，并在交互场景使用 `confirm_install_file` 等 helper 做单文件选择/覆盖确认。
- 支持同时从源码目录（`KAM_MODULE_ROOT`）或压缩包（`ZIPFILE`）中安装；在处理 ZIP 时必须先检查 `unzip`/`zipinfo`。

非交互/CI 场景
- 识别 CI/非交互（`is_ci` / 检查 TTY），在非交互环境下避免弹出会阻塞的交互式确认；选择安全默认行为（例如跳过覆盖）。
- 提供 CI 测试脚本/步骤以验证无交互自动流程（在 PR 的测试说明中列出）。

错误和依赖处理
- 关键依赖缺失必须 fail-fast（`abort`）并打印 i18n 信息（例如 `ZIPTOOLS_MISSING`）。
- 对于网络资源，若校验失败应中止并给出可重复的排查步骤。

提交（PR）模版建议（每次变更请尽量包含以下内容）
- 标题与一句话说明改动要点（What / Why）。
- 变更说明（包含设计要点与重要边界情况）。
- 新增/修改的 i18n 键（列出键名与示例翻译）。
- 需要注意的兼容性问题或风险（例如 API 变更、行为改动）。
- 测试/验证步骤（含交互与非交互情形的演练步骤与期望结果）。
- 若涉及安装/日志/网络：附上本地手工验证命令或短脚本。

快速验证示例
- at-exit handler（安装场景）验证：
  1. 准备：创建临时 `KAM_MODULE_ROOT`（含 `bin/foo`），设置 `MODPATH` 到临时目标目录，且把 `lib/kamfw` 复制到 `$MODPATH/lib/kamfw`（模拟安装时的文件布局）。
  2. 在 shell 中 `. "$MODPATH/lib/kamfw/.kamfwrc" && import __customize__`，然后调用 `install_reset_filters; install_include "bin/*"; install_register_exit_hook`（显式注册退出安装钩子），退出 shell（`exit`）；检查 `$MODPATH/bin/foo` 已被安装。
  3. 日志级别验证：
  1. `export KAM_LOGLEVEL=ERROR`；运行 `info "hi"`（不应在屏幕显示）；运行 `error "oops"`（应显示并写入日志）。
  2. `export KAM_LOGLEVEL=DEBUG` 或 `export KAM_DEBUG=1`；运行 `debug "d"`（应显示并写入日志）。
- `install_check` 验证：
  - 在 module 源目录运行 `install_exclude 'test/*' ; install_include 'test/keep/*' ; install_check`，检查输出顺序与预期。

风格 & 小贴士
- 新 helper 写入 `src/MagicNet/lib/kamfw/__name__.sh`，并在 `.kamfwrc` 或需要的位置 `import`（遵循现有 import 顺序，i18n 应先加载以便 helper 使用 `i18n`）。
- 所有用户可见文本必须 `set_i18n`；在 PR 中列出新增键以便翻译。
- 在编写和修改时保持函数短小、职责单一并写清楚注释（为什么这么做，而不是仅仅描述做了什么）。

单一文件代码不要超过200行，如果超过了，反思！
不要写太多fallback,开发阶段不需要考虑兼容性，垃圾代码立刻移除，不要犹豫
不要害怕报错，错误信息是宝贵的学习经验
