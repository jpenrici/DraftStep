# =============================================================================
# Logger.jl — DraftStep Logging Module
# =============================================================================
#
# Lightweight, opt-in logging module for the DraftStep pipeline.
# Disabled by default — zero impact on existing tests and modules.
#
# Design principles:
#   - Silent unless explicitly enabled (ENABLED = false by default)
#   - Four log levels: DEBUG < INFO < WARN < ERROR
#   - Output goes to stderr — keeps stdout clean for pipeline data
#   - No external dependencies
#   - No function signatures in existing modules are affected
#
# Usage in bin/draftstep (activate before pipeline):
#   Logger.enable!(Logger.LOG_INFO)   # INFO and above
#   Logger.enable!(Logger.LOG_DEBUG)  # all messages
#   Logger.disable!()                 # silence (default)
#
# Usage in pipeline modules (opt-in, non-invasive):
#   import ..Logger
#   Logger.warn("position (900, 50) outside canvas bounds")
#   Logger.info("tokenizing complete — $(length(tokens)) tokens")
#
# Log levels and typical usage:
#   DEBUG  low-level tracing — token by token, node by node
#   INFO   pipeline milestones — start/end of each stage
#   WARN   silent risk points — out-of-bounds, skipped shapes, unknowns
#   ERROR  unrecoverable states — logged just before an exception is raised
#
# Output format:
#   [INFO ] tokenizing complete — 405 tokens
#   [WARN ] position (900, 50) outside canvas (500 x 400)
#   [ERROR] unsupported shape kind: SK_BEZIER
#
# =============================================================================

module Logger

export LogLevel, LOG_DEBUG, LOG_INFO, LOG_WARN, LOG_ERROR
export enable!, disable!, enabled, current_level
export log, debug, info, warn, error


# =============================================================================
# SECTION 1 — Log levels
# =============================================================================

"""
LogLevel

Ordered enumeration of log severity levels.
Only messages at or above the active level are emitted.

| Level     | Value | Typical use                                      |
|-----------|-------|--------------------------------------------------|
| LOG_DEBUG | 0     | Low-level tracing — tokens, AST nodes, coords    |
| LOG_INFO  | 1     | Pipeline milestones — stage start/end, counts    |
| LOG_WARN  | 2     | Silent risk points — out-of-bounds, skipped data |
| LOG_ERROR | 3     | Unrecoverable state, logged before raising       |
"""
@enum LogLevel LOG_DEBUG=0 LOG_INFO=1 LOG_WARN=2 LOG_ERROR=3


# =============================================================================
# SECTION 2 — Global state
# =============================================================================

"""
ENABLED :: Ref{Bool}

Controls whether the logger emits any output.
`false` by default — the logger is completely silent until `enable!()` is called.
This ensures zero impact on existing tests and modules.
"""
const ENABLED = Ref{Bool}(false)

"""
LEVEL :: Ref{LogLevel}

The minimum severity level for emitted messages.
    Messages below this level are silently discarded.
    Default: `LOG_INFO` (set when `enable!()` is called without arguments).
    """
const LEVEL = Ref{LogLevel}(LOG_INFO)


# =============================================================================
# SECTION 3 — Configuration
# =============================================================================

"""
enable!(level::LogLevel = LOG_INFO)

Activates the logger at the given minimum level.
Messages at `level` and above will be emitted to stderr.

# Examples
Logger.enable!()                # INFO and above (default)
Logger.enable!(Logger.LOG_DEBUG) # all messages including DEBUG
Logger.enable!(Logger.LOG_WARN)  # only WARN and ERROR
"""
function enable!(level::LogLevel = LOG_INFO)
    ENABLED[] = true
    LEVEL[] = level
end

"""
disable!()

Silences the logger completely.
All log calls become no-ops until `enable!()` is called again.
This is the default state — safe for tests and library use.
    """
function disable!()
    ENABLED[] = false
end

"""
enabled() → Bool

Returns `true` if the logger is currently active.
    """
enabled() = ENABLED[]

"""
current_level() → LogLevel

Returns the active minimum log level.
"""
current_level() = LEVEL[]


# =============================================================================
# SECTION 4 — Core log function
# =============================================================================

"""
log(level::LogLevel, msg::String)

Emits a log message if the logger is enabled and `level >= current_level()`.
Output goes to `stderr` to keep `stdout` clean for pipeline data.

Output format:
[INFO ] message text here
[WARN ] message text here

Note: callers should prefer the shorthand functions `debug`, `info`,
`warn` and `error` over calling this directly.
"""
function log(level::LogLevel, msg::String)
    !ENABLED[] && return
    level < LEVEL[] && return
    prefix =
        level == LOG_DEBUG ? "DEBUG" :
        level == LOG_INFO ? "INFO" :
        level == LOG_WARN ? "WARN" : "ERROR"
    println(stderr, "[$prefix] $msg")
end


# =============================================================================
# SECTION 5 — Shorthand functions
# =============================================================================

"""
debug(msg::String)

Emits a DEBUG-level message.
Use for low-level tracing: individual tokens, AST nodes, coordinate values.
Only visible when logger is enabled at `LOG_DEBUG` level.

# Example
Logger.debug("scanned token TK_NUMBER '100' at line 3")
"""
debug(msg::String) = log(LOG_DEBUG, msg)

"""
info(msg::String)

Emits an INFO-level message.
Use for pipeline milestones: stage transitions, shape counts, layer names.

# Example
Logger.info("tokenizing complete — 405 tokens")
Logger.info("layer 'background' activated")
"""
info(msg::String) = log(LOG_INFO, msg)

"""
warn(msg::String)

Emits a WARN-level message.
Use for silent risk points: positions outside canvas, shapes with no points,
unknown tokens encountered before raising a LexerError.

# Example
Logger.warn("position (900, 50) outside canvas (500 x 400)")
Logger.warn("skipping shape with 0 points in layer 'base'")
"""
warn(msg::String) = log(LOG_WARN, msg)

"""
error(msg::String)

Emits an ERROR-level message.
Use immediately before raising an exception — provides context in the log
that the exception message alone may not capture.

# Example
Logger.error("unsupported shape kind: \$(shape.kind) at line \$(line)")
throw(Renderer.RendererError("unsupported shape kind"))
"""
error(msg::String) = log(LOG_ERROR, msg)


end # module Logger
