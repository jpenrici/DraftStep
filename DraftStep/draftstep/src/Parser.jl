# =============================================================================
# Parser.jl — DraftStep Syntactic Analyzer
# =============================================================================
#
# Consumes a flat Vector{Token} produced by the Lexer and builds a
# ProgramNode (AST root) containing one CommandNode per valid command.
#
# Pipeline position:
#   Lexer.tokenize → Vector{Token} → Parser.parse → ProgramNode
#
# Grammar (informal):
#   program     := command* EOF
#   command     := COMMAND arg* NEWLINE
#   arg         := NUMBER UNIT?
#              |   STRING
#              |   COLOR
#
# Skipped silently:
#   TK_COMMENT, TK_NEWLINE (blank lines between commands)
#
# Argument rules per command (enforced by Parser):
#   forward / backward          : NUMBER UNIT
#   left / right                : NUMBER UNIT
#   penup / pendown             : (no args)
#   circle                      : NUMBER UNIT
#   rect                        : NUMBER UNIT NUMBER UNIT
#   color                       : COLOR
#   fill                        : COLOR
#   strokewidth                 : NUMBER UNIT
#   layer / group               : STRING
#   canvas                      : NUMBER NUMBER
#
# Usage:
#   include("Types.jl")
#   include("Lexer.jl")
#   include("Parser.jl")
#   tokens  = Lexer.tokenize(source)
#   program = Parser.parse(tokens)
#
# =============================================================================

module Parser

import ..Types

export parse, ParserError


# =============================================================================
# SECTION 1 — Error type
# =============================================================================

"""
ParserError

Raised when the Parser encounters an unexpected token or invalid argument.

# Fields
- `message::String` : human-readable description of the problem
- `line::Int`       : source line where the error occurred
"""
struct ParserError <: Exception
    message::String
    line::Int
end

Base.showerror(io::IO, e::ParserError) =
    print(io, "ParserError at line $(e.line): $(e.message)")


# =============================================================================
# SECTION 2 — Argument grammar table
#
# Maps each command keyword to the expected sequence of argument kinds.
# Each entry is a Vector of Vectors — one inner Vector per argument slot.
# A slot lists the TokenKinds accepted for that position.
#
# Special sentinel :unit_optional means a UNIT token is consumed if present
# but is not required (used for canvas which takes raw numbers).
# =============================================================================

# Shorthand aliases for readability inside the table
const _N = [Types.TK_NUMBER]   # numeric value
const _U = [Types.TK_UNIT]     # unit suffix  (px / deg / rad)
const _S = [Types.TK_STRING]   # quoted string
const _C = [Types.TK_COLOR]    # hex color

"""
ARG_GRAMMAR

Expected argument slot sequences per command keyword.
The Parser validates incoming tokens against this table.

Format:  command => [ slot1_kinds, slot2_kinds, ... ]
"""
const ARG_GRAMMAR = Dict{String,Vector{Vector{Types.TokenKind}}}(
    # --- Movement (distance + unit) ---
    "forward" => [_N, _U],
    "backward" => [_N, _U],

    # --- Rotation (angle + unit) ---
    "left" => [_N, _U],
    "right" => [_N, _U],

    # --- Pen control (no arguments) ---
    "penup" => [],
    "pendown" => [],

    # --- Shapes ---
    "circle" => [_N, _U],         # radius
    "rect" => [_N, _U, _N, _U],   # width height

    # --- Style ---
    "color" => [_C],
    "fill" => [_C],
    "strokewidth" => [_N, _U],

    # --- Organization ---
    "layer" => [_S],
    "group" => [_S],

    # --- Canvas (width height — plain numbers, no unit) ---
    "canvas" => [_N, _N],
)


# =============================================================================
# SECTION 3 — Internal Parser state
# =============================================================================

"""
ParserState

Internal mutable state used while walking the token list.

# Fields
- `tokens::Vector{Types.Token}` : full token list from the Lexer
- `pos::Int`                    : index of the current token (1-based)
"""
mutable struct ParserState
    tokens::Vector{Types.Token}
    pos::Int
end

ParserState(tokens::Vector{Types.Token}) = ParserState(tokens, 1)

# --- Return current token without advancing ---
function peek(ps::ParserState)::Types.Token
    return ps.tokens[ps.pos]
end

# --- Consume and return the current token ---
function advance!(ps::ParserState)::Types.Token
    tok = ps.tokens[ps.pos]
    ps.pos += 1
    return tok
end

# --- Return true when the current token is TK_EOF ---
at_end(ps::ParserState) = peek(ps).kind == Types.TK_EOF

# --- Skip TK_NEWLINE and TK_COMMENT tokens ---
function skip_ignored!(ps::ParserState)
    while !at_end(ps) && peek(ps).kind ∈ (Types.TK_NEWLINE, Types.TK_COMMENT)
        advance!(ps)
    end
end


# =============================================================================
# SECTION 4 — Argument parsers
# =============================================================================

"""
parse_arg(ps, expected_kinds, cmd_name) → Any

Consumes the next token and validates it against `expected_kinds`.
Returns the typed argument value:
  - TK_NUMBER  → Float64
  - TK_UNIT    → String  (e.g. "px", "deg")
  - TK_STRING  → String  (quote-stripped, as delivered by the Lexer)
  - TK_COLOR   → String  (e.g. "#FF5733")

Raises `ParserError` if the token kind does not match.
"""
function parse_arg(
    ps::ParserState,
    expected_kinds::Vector{Types.TokenKind},
    cmd_name::String,
)::Any
    tok = peek(ps)

    if tok.kind ∉ expected_kinds
        expected = join(string.(expected_kinds), " or ")
        throw(
            ParserError(
                "command '$cmd_name': expected $expected but got $(tok.kind) " *
                "(\"$(tok.value)\")",
                tok.line,
            ),
        )
    end

    advance!(ps)

    # Convert NUMBER tokens to Float64 for the Interpreter
    if tok.kind == Types.TK_NUMBER
        val = tryparse(Float64, tok.value)
        if val === nothing
            throw(
                ParserError(
                    "command '$cmd_name': cannot parse \"$(tok.value)\" as a number",
                    tok.line,
                ),
            )
        end
        return val
    end

    # All other kinds (UNIT, STRING, COLOR) are returned as raw strings
    return tok.value
end


# =============================================================================
# SECTION 5 — Command parser
# =============================================================================

"""
parse_command(ps) → CommandNode

Parses a single command starting at the current TK_COMMAND token.
Consumes the command keyword, all expected arguments, and the trailing
TK_NEWLINE (or TK_EOF).

Raises `ParserError` for:
  - unknown command keyword (not in ARG_GRAMMAR)
  - wrong argument kinds
  - missing trailing newline or EOF
"""
function parse_command(ps::ParserState)::Types.CommandNode
    cmd_tok = advance!(ps)   # consume TK_COMMAND
    name = cmd_tok.value
    line = cmd_tok.line

    # Look up expected argument slots
    if !haskey(ARG_GRAMMAR, name)
        throw(ParserError("unknown command '$name'", line))
    end

    slots = ARG_GRAMMAR[name]
    args = Any[]

    for slot_kinds in slots
        push!(args, parse_arg(ps, slot_kinds, name))
    end

    # Skip any trailing comment on the same line before checking terminator
    if !at_end(ps) && peek(ps).kind == Types.TK_COMMENT
        advance!(ps)
    end

    # After all arguments, expect NEWLINE or EOF
    if !at_end(ps) && peek(ps).kind ∉ (Types.TK_NEWLINE, Types.TK_EOF)
        tok = peek(ps)
        throw(
            ParserError(
                "command '$name': unexpected token $(tok.kind) " *
                "(\"$(tok.value)\") after arguments",
                tok.line,
            ),
        )
    end

    # Consume trailing newline if present (leave EOF for the main loop)
    if !at_end(ps) && peek(ps).kind == Types.TK_NEWLINE
        advance!(ps)
    end

    return Types.CommandNode(name, args, line)
end


# =============================================================================
# SECTION 6 — Main parser entry point
# =============================================================================

"""
parse(tokens::Vector{Types.Token}) → Types.ProgramNode

Parses a full token list into a `ProgramNode` (AST root).

Skips comments and blank lines. Processes commands in source order.
Always returns a `ProgramNode` — an empty source yields a node with zero
commands.

# Raises
- `ParserError` if any command has wrong or missing arguments.

# Example
```julia
tokens  = Lexer.tokenize("forward 100 px\\ncircle 30 px\\n")
program = Parser.parse(tokens)
# → ProgramNode([
#       CommandNode("forward", [100.0, "px"], 1),
#       CommandNode("circle",  [30.0,  "px"], 2),
#   ])
```
"""
function parse(tokens::Vector{Types.Token})::Types.ProgramNode
    ps = ParserState(tokens)
    commands = Types.CommandNode[]

    skip_ignored!(ps)   # skip leading comments / blank lines

    while !at_end(ps)
        if peek(ps).kind == Types.TK_COMMAND
            push!(commands, parse_command(ps))
        else
            # Unexpected token at statement level
            tok = peek(ps)
            throw(
                ParserError(
                    "unexpected token $(tok.kind) (\"$(tok.value)\") " *
                    "at start of statement",
                    tok.line,
                ),
            )
        end

        skip_ignored!(ps)   # skip comments / blank lines between commands
    end

    return Types.ProgramNode(commands)
end


# =============================================================================
# SECTION 7 — Debug utilities
# =============================================================================

"""
print_ast(program; io=stdout)

Pretty-prints a `ProgramNode` to `io` (defaults to stdout).
Useful for inspecting the Parser output during development.

# Example output
    ─────────────────────────────────────
    DraftStep Parser — AST dump
    total: 2 command(s)
    ─────────────────────────────────────
    [ 1]  forward        args: [100.0, "px"]
    [ 2]  circle         args: [30.0, "px"]
    ─────────────────────────────────────
"""
function print_ast(program::Types.ProgramNode; io::IO = stdout)
    n = length(program.commands)
    println(io, "─────────────────────────────────────────")
    println(io, "  DraftStep Parser — AST dump")
    println(io, "  total: $n command(s)")
    println(io, "─────────────────────────────────────────")

    for cmd in program.commands
        name_str = rpad(cmd.name, 14)
        args_str = join([a isa Float64 ? string(a) : "\"$a\"" for a in cmd.args], ", ")
        line_str = lpad(string(cmd.line), 3)
        println(io, "  [$(line_str)]  $(name_str)  args: [$(args_str)]")
    end

    println(io, "─────────────────────────────────────────")
end

end # module Parser
