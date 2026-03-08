# =============================================================================
# Lexer.jl — DraftStep Lexical Analyzer
# =============================================================================
#
# Reads a .draftstep source file (or raw string) and produces a flat list
# of Token values for the Parser to consume.
#
# Pipeline position:
#   [source file] → Lexer.tokenize → Vector{Token} → Parser
#
# Supported token kinds (defined in Types.jl):
#   TK_COMMAND   keywords : forward, backward, left, right, penup, pendown,
#                           circle, rect, layer, group, color, strokewidth,
#                           canvas
#   TK_NUMBER    numeric literals  : 100, 3.14
#   TK_UNIT      unit suffixes     : px, deg, rad
#   TK_STRING    quoted strings    : "background"
#   TK_COLOR     hex colors        : #FF5733
#   TK_COMMENT   comment lines     : # this is a comment
#   TK_NEWLINE   end of line
#   TK_EOF       end of file
#   TK_UNKNOWN   unrecognized token (produces a LexerError)
#
# Usage:
#   include("Types.jl");  import .Types
#   include("Lexer.jl");  import .Lexer
#   tokens = Lexer.tokenize("forward 100 px\ncircle 30 px\n")
#
# =============================================================================

module Lexer

# Types must be loaded once by the caller before including this file:
#   include("Types.jl")
#   include("Lexer.jl")
# Lexer references Types from the enclosing (caller) module scope.
import ..Types

export tokenize, LexerError


# =============================================================================
# SECTION 1 — Error type
# =============================================================================

"""
LexerError

Raised when the Lexer encounters a token it cannot classify.

# Fields
- `message::String` : human-readable description of the problem
- `line::Int`       : source line where the error occurred
"""
struct LexerError <: Exception
    message::String
    line::Int
end

Base.showerror(io::IO, e::LexerError) =
    print(io, "LexerError at line $(e.line): $(e.message)")


# =============================================================================
# SECTION 2 — Keyword table
# All recognized command keywords in the DraftStep language.
# =============================================================================

"""
KEYWORDS

Set of all valid command keywords. Used by the Lexer to distinguish a
`TK_COMMAND` token from an unknown bare word.
"""
const KEYWORDS = Set{String}([
    # --- Movement ---
    "forward",
    "backward",
    "left",
    "right",

    # --- Pen control ---
    "penup",
    "pendown",

    # --- Shapes ---
    "circle",
    "rect",

    # --- Style ---
    "color",
    "strokewidth",
    "fill",

    # --- Organization ---
    "layer",
    "group",

    # --- Canvas ---
    "canvas",
])

"""
UNITS

Set of all recognized unit suffixes.
"""
const UNITS = Set{String}(["px", "deg", "rad"])


# =============================================================================
# SECTION 3 — Character helpers
# =============================================================================

"""
is_digit(c)

Returns `true` if `c` is an ASCII digit (0–9).
"""
is_digit(c::Char) = c >= '0' && c <= '9'

"""
is_alpha(c)

Returns `true` if `c` is an ASCII letter (a–z, A–Z) or underscore.
"""
is_alpha(c::Char) = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'

"""
is_alnum(c)

Returns `true` if `c` is an ASCII letter, digit, or underscore.
"""
is_alnum(c::Char) = is_alpha(c) || is_digit(c)

"""
is_hex_digit(c)

Returns `true` if `c` is a valid hexadecimal digit (0–9, a–f, A–F).
"""
is_hex_digit(c::Char) =
    (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')


# =============================================================================
# SECTION 4 — Internal Lexer state
# =============================================================================

"""
LexerState

Internal mutable state used while scanning a source string.

# Fields
- `source::String`   : full source text being scanned
- `chars::Vector{Char}` : source split into individual characters
- `pos::Int`         : current character index (1-based)
- `line::Int`        : current line number (1-based)
"""
mutable struct LexerState
    source::String
    chars::Vector{Char}
    pos::Int
    line::Int
end

LexerState(source::String) = LexerState(source, collect(source), 1, 1)

# --- Peek at the current character without advancing ---
peek(ls::LexerState) = ls.pos <= length(ls.chars) ? ls.chars[ls.pos] : '\0'

# --- Peek one character ahead ---
peek_next(ls::LexerState) = ls.pos + 1 <= length(ls.chars) ? ls.chars[ls.pos+1] : '\0'

# --- Consume and return the current character ---
function advance!(ls::LexerState)::Char
    c = ls.chars[ls.pos]
    ls.pos += 1
    return c
end

# --- Returns true if the scanner has reached the end of the source ---
at_end(ls::LexerState) = ls.pos > length(ls.chars)


# =============================================================================
# SECTION 5 — Token scanners
# Each function assumes `ls.pos` is positioned at the first character
# of the construct being scanned, and leaves `ls.pos` just past the last.
# =============================================================================

"""
scan_number!(ls, line) → Token

Scans an integer or floating-point literal.
Accepts an optional leading minus sign for negative values.
"""
function scan_number!(ls::LexerState, line::Int)::Types.Token
    buf = Char[]

    # Optional leading minus
    if peek(ls) == '-'
        push!(buf, advance!(ls))
    end

    # Integer part
    while !at_end(ls) && is_digit(peek(ls))
        push!(buf, advance!(ls))
    end

    # Optional fractional part
    if !at_end(ls) && peek(ls) == '.' && is_digit(peek_next(ls))
        push!(buf, advance!(ls))         # consume '.'
        while !at_end(ls) && is_digit(peek(ls))
            push!(buf, advance!(ls))
        end
    end

    return Types.Token(Types.TK_NUMBER, String(buf), line)
end


"""
scan_word!(ls, line) → Token

Scans a bare word (letters, digits, underscores) and classifies it as
`TK_COMMAND` if it is a known keyword, `TK_UNIT` if it is a known unit,
or `TK_UNKNOWN` otherwise.
"""
function scan_word!(ls::LexerState, line::Int)::Types.Token
    buf = Char[]
    while !at_end(ls) && is_alnum(peek(ls))
        push!(buf, advance!(ls))
    end
    word = String(buf)

    if word in KEYWORDS
        return Types.Token(Types.TK_COMMAND, word, line)
    elseif word in UNITS
        return Types.Token(Types.TK_UNIT, word, line)
    else
        throw(LexerError("unknown keyword '$word'", line))
    end
end


"""
scan_string!(ls, line) → Token

Scans a double-quoted string literal.
The returned token value does NOT include the surrounding quotes.
Raises `LexerError` if the string is unterminated.
"""
function scan_string!(ls::LexerState, line::Int)::Types.Token
    advance!(ls)   # consume opening '"'
    buf = Char[]

    while !at_end(ls) && peek(ls) != '"'
        c = advance!(ls)
        if c == '\n'
            throw(LexerError("unterminated string literal", line))
        end
        push!(buf, c)
    end

    if at_end(ls)
        throw(LexerError("unterminated string literal (missing closing '\"')", line))
    end

    advance!(ls)   # consume closing '"'
    return Types.Token(Types.TK_STRING, String(buf), line)
end


"""
scan_color!(ls, line) → Token

Scans a hex color literal starting with `#`.
Accepts 3-digit shorthand (`#RGB`) and 6-digit full form (`#RRGGBB`).
Raises `LexerError` for invalid formats.
"""
function scan_color!(ls::LexerState, line::Int)::Types.Token
    advance!(ls)   # consume '#'
    buf = Char[]

    while !at_end(ls) && is_hex_digit(peek(ls))
        push!(buf, advance!(ls))
    end

    hex = String(buf)
    if length(hex) != 3 && length(hex) != 6
        throw(LexerError("invalid color literal '#$hex' — expected #RGB or #RRGGBB", line))
    end

    return Types.Token(Types.TK_COLOR, "#" * hex, line)
end


"""
scan_comment!(ls, line) → Token

Scans from `#` to the end of the line. The `#` must NOT be followed by
a hex digit (those are handled by `scan_color!`).
Returns a `TK_COMMENT` token containing the full comment text (including `#`).
"""
function scan_comment!(ls::LexerState, line::Int)::Types.Token
    buf = Char[]
    while !at_end(ls) && peek(ls) != '\n'
        push!(buf, advance!(ls))
    end
    return Types.Token(Types.TK_COMMENT, String(buf), line)
end


# =============================================================================
# SECTION 6 — Main tokenizer
# =============================================================================

"""
tokenize(source::String) → Vector{Token}

Converts a DraftStep source string into a flat list of tokens.

Comments (`TK_COMMENT`) are included in the output so that tooling can
preserve them, but the Parser is expected to skip them.
A single `TK_EOF` token is always appended at the end.

# Raises
- `LexerError` if an unrecognized or malformed token is encountered.

# Example
```julia
tokens = tokenize("forward 100 px\\ncircle 30 px\\n")
# → [Token(TK_COMMAND,"forward",1), Token(TK_NUMBER,"100",1),
#    Token(TK_UNIT,"px",1),         Token(TK_NEWLINE,"\\n",1),
#    Token(TK_COMMAND,"circle",2),  Token(TK_NUMBER,"30",2),
#    Token(TK_UNIT,"px",2),         Token(TK_NEWLINE,"\\n",2),
#    Token(TK_EOF,"",2)]
```
"""
function tokenize(source::String)::Vector{Types.Token}
    ls = LexerState(source)
    tokens = Types.Token[]

    while !at_end(ls)
        c = peek(ls)
        line = ls.line

        # --- Whitespace (spaces and tabs — NOT newlines) ---
        if c == ' ' || c == '\t'
            advance!(ls)

            # --- Newline ---
        elseif c == '\n'
            push!(tokens, Types.Token(Types.TK_NEWLINE, "\\n", line))
            advance!(ls)
            ls.line += 1

            # --- Windows-style line ending (CR+LF) ---
        elseif c == '\r'
            advance!(ls)   # discard CR; LF will be handled next iteration

        # --- Number literal (digit or negative sign followed by digit) ---
        elseif is_digit(c) || (c == '-' && is_digit(peek_next(ls)))
            push!(tokens, scan_number!(ls, line))

            # --- Bare word: command keyword or unit ---
        elseif is_alpha(c)
            push!(tokens, scan_word!(ls, line))

            # --- Quoted string ---
        elseif c == '"'
            push!(tokens, scan_string!(ls, line))

            # --- Color literal (#RRGGBB) or comment (# text) ---
        elseif c == '#'
            if is_hex_digit(peek_next(ls))
                push!(tokens, scan_color!(ls, line))
            else
                push!(tokens, scan_comment!(ls, line))
            end

            # --- Unknown character ---
        else
            throw(LexerError("unexpected character '$(c)'", line))
        end
    end

    push!(tokens, Types.Token(Types.TK_EOF, "", ls.line))
    return tokens
end


"""
tokenize_file(path::String) → Vector{Token}

Convenience wrapper: reads a `.draftstep` file from disk and tokenizes it.

# Raises
- `SystemError` if the file cannot be opened.
- `LexerError`  if the file content contains invalid tokens.
"""
function tokenize_file(path::String)::Vector{Types.Token}
    source = read(path, String)
    return tokenize(source)
end

end # module Lexer
