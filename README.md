# kamfw

kamfw is the shell runtime embedded in Kam module templates. It provides the
common entrypoint, lifecycle dispatcher, logging, i18n, installer helpers, and
small Android/root-manager utilities used by generated modules.

The current implementation is shell-only. The old Rust CLI prototype under
`src/` was intentionally removed; runtime behavior should stay in the shell
modules here unless a new design is introduced deliberately.

## Entrypoint

Module scripts source `.kamfwrc`:

```sh
. "$MODDIR/lib/kamfw/.kamfwrc" || exit 1
```

`.kamfwrc` loads the core modules in this order:

1. `i18n`
2. `base`
3. `logging`
4. `kam`

Use `import <module>` to load additional helpers. `import` calls the internal
loader directly, so runtime command dispatch in `__runtime__.sh` cannot break
module loading.

## Runtime

`kam.sh` imports:

- `__runtime__`: `kamfw run <phase> -- "$@"`, KAM_HOME, PATH, and
  LD_LIBRARY_PATH setup.
- `init_dirs`: creates runtime directories under `$KAM_HOME`.
- root-manager helpers when detected: `magisk`, `ksu`, `ap`.

Supported lifecycle phases are:

- `install`
- `post-fs-data`
- `service`
- `boot-completed`
- `uninstall`
- `action`
- `post-mount`

Default phase handlers are no-ops and can be overridden by module code.

## Installer

`import __installer__` is the complete public installer entrypoint. It loads:

- `__at_exit__`
- `__install_core__`
- `__installer_cmd__`

Public API:

```sh
install_reset_filters
install_exclude "pattern"
install_include "pattern"
install_check [src]
installer check [src]
installer run [src]
installer schedule [src]
```

Install filter order is:

1. list files from a source directory or zip
2. remove excluded files
3. re-add included files

Zip listing prefers `zipinfo`, then `unzip -Z1`, then structured `unzip -l`
parsing. Zip extraction requires `unzip` and fails fast if it is missing.

## Output And i18n

User-visible output should go through `print`, `info`, `warn`, `error`, or
`success`. New user-facing text should be registered with `set_i18n` and read
with `i18n`.

The `t` helper uses `$_1`, `$_2`, ... placeholders:

```sh
set_i18n "EXAMPLE" "en" "Installed: \$_1"
i18n "EXAMPLE" | t "bin/foo"
```

Do not add `|| echo ...` fallback output paths. Use a small helper or an
explicit fallback variable, then send the final message through the logging
wrapper.

`import rich` provides small UI helpers for installer and action screens:

```sh
panel "Module status"
panel_row "Version" "$KAM_MODULE_VERSION"
panel_divider
panel_success "Ready"
panel_warn "Optional config not found"
panel_error "Service failed"
panel_end
```

Available panel helpers are:

- `panel [title]` / `panel_end`
- `panel_line <text>` / `panel_blank` / `panel_divider`
- `panel_row <label> <value>`
- `panel_status <info|success|warn|error> <text>`
- `panel_note`, `panel_success`, `panel_warn`, `panel_error`

Panels use terminal colors only on TTY. Non-TTY and manager UI output stays
plain text with stable borders, so it remains readable in install logs.

## Validation

Useful local checks from the Kam repository root:

```sh
shellcheck -S error -s sh \
  "tmpl/kam_template/src/<module-id>/lib/kamfw/.kamfwrc" \
  "tmpl/kam_template/src/<module-id>/lib/kamfw/__install_core__.sh" \
  "tmpl/kam_template/src/<module-id>/lib/kamfw/__installer__.sh" \
  "tmpl/kam_template/src/<module-id>/lib/kamfw/__installer_cmd__.sh" \
  "tmpl/kam_template/src/<module-id>/lib/kamfw/kam.sh" \
  "tmpl/kam_template/src/<module-id>/lib/kamfw/__termux__.sh"

cargo run -- init /tmp/kam-smoke --tmpl --force
```

Minimal installer smoke test:

```sh
tmp=$(mktemp -d /tmp/kamfw-test.XXXXXX)
mkdir -p "$tmp/out/.config/kamfw" "$tmp/out/lib/kamfw" "$tmp/src/bin"
cp tmpl/kam_template/src/<module-id>/lib/kamfw/.kamfwrc "$tmp/out/lib/kamfw/.kamfwrc"
cp tmpl/kam_template/src/<module-id>/lib/kamfw/*.sh "$tmp/out/lib/kamfw/"
printf 'KAMFW_DIR=%s\nKAM_MODULES=""\nKAM_HOME=%s\n' \
  "$tmp/out/lib/kamfw" "$tmp/home" > "$tmp/out/.config/kamfw/.envrc"
printf '#!/bin/sh\necho ok\n' > "$tmp/src/bin/foo"
chmod +x "$tmp/src/bin/foo"
MODPATH="$tmp/out" KAM_MODULE_ROOT="$tmp/src" sh -c \
  '. "$0"; import __installer__; install_reset_filters; install_include "bin/*"; installer run' \
  "$tmp/out/lib/kamfw/.kamfwrc"
test -x "$tmp/out/bin/foo"
```

Panel helper smoke test:

```sh
tmp=$(mktemp -d /tmp/kamfw-panel.XXXXXX)
mkdir -p "$tmp/out/.config/kamfw" "$tmp/out/lib"
cp -a tmpl/kam_template/src/<module-id>/lib/kamfw "$tmp/out/lib/kamfw"
printf 'KAMFW_DIR=%s\nKAM_MODULES=""\nKAM_HOME=%s\n' \
  "$tmp/out/lib/kamfw" "$tmp/home" > "$tmp/out/.config/kamfw/.envrc"
MODPATH="$tmp/out" sh -c \
  '. "$0"; import rich; PANEL_WIDTH=44 panel "kamfw"; panel_row "Module" "demo"; panel_success "ready"; panel_end' \
  "$tmp/out/lib/kamfw/.kamfwrc"
```

## Thanks

[nga-utils](https://github.com/ShIroRRen/NGA-SDK/tree/nga)
