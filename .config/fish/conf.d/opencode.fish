if not status is-interactive
    exit
end

set -gx OPENCODE_ENABLE_EXA true
set -gx OPENCODE_ENABLE_PARALLEL true
set -gx OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS true
set -gx OPENCODE_EXPERIMENTAL_LSP_TOOL true

function omos
    set -l port (jot -r 1 49152 65535)
    env OPENCODE_PORT="$port" opencode --port "$port" $argv
end
