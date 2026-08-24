# serve opencode on a port by default
function omos --wraps opencode
    set -l port (jot -r 1 49152 65535)
    env OPENCODE_PORT="$port" opencode --port "$port" $argv
end

