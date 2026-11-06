# shellcheck shell=ash
import app

require_termux() { require_app com.termux 'Termux Not Installed!'; }

# Root lifecycles keep module-owned paths; these names remain callable for
# modules that previously requested an app-owned Termux environment.
set_termux_home() { :; }
active_termux_env() { :; }
deactivate_termux_env() { :; }
