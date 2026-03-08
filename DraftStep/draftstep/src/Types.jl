# =============================================================================
# Types.jl — DraftStep Core Type Definitions
# =============================================================================
#
# This module defines all shared data structures used across the DraftStep
# pipeline: tokens, AST nodes, cursor state, layers, and rendering output.
#
# Pipeline position:
#   Types.jl is a dependency of ALL other modules — it has no dependencies
#   of its own. Import it first in every module.
#
# Usage:
#   include("Types.jl")
#   using .Types
#
# =============================================================================

module Types

export
    # Token types
    TokenKind,
    Token,

    # AST node types
    ASTNode,
    CommandNode,
    ProgramNode,

    # Cursor and drawing state
    CursorState,
    DrawingState,

    # Geometry primitives
    Point,
    Color,

    # Rendering output
    Shape,
    ShapeKind,

    # Layers and groups
    Layer,
    Group


# =============================================================================
# SECTION 1 — Tokens
# Produced by the Lexer, consumed by the Parser.
# =============================================================================

"""
TokenKind

Enum of all valid token categories in the DraftStep language.

- `TK_COMMAND`   : a keyword that maps to a drawing action (e.g. `forward`, `circle`)
- `TK_NUMBER`    : a numeric literal (integer or float)
- `TK_UNIT`      : a measurement unit (`px`, `deg`, `rad`)
- `TK_STRING`    : a quoted string literal (e.g. `"background"`)
- `TK_COLOR`     : a hex color literal (e.g. `#FF5733`)
- `TK_COMMENT`   : a `#`-prefixed comment line (ignored by the Parser)
- `TK_NEWLINE`   : end of a command line
- `TK_EOF`       : end of the input file
- `TK_UNKNOWN`   : unrecognized token (triggers a Lexer error)
"""
@enum TokenKind begin
    TK_COMMAND
    TK_NUMBER
    TK_UNIT
    TK_STRING
    TK_COLOR
    TK_COMMENT
    TK_NEWLINE
    TK_EOF
    TK_UNKNOWN
end


"""
Token

A single lexical unit produced by the Lexer.

# Fields
- `kind::TokenKind`  : category of this token
- `value::String`    : raw text extracted from the source file
- `line::Int`        : source line number (1-based, used for error reporting)
"""
struct Token
    kind::TokenKind
    value::String
    line::Int
end


# =============================================================================
# SECTION 2 — AST Nodes
# Produced by the Parser, consumed by the Interpreter.
# =============================================================================

"""
ASTNode

Abstract base type for all nodes in the Abstract Syntax Tree.
Every concrete node type must subtype `ASTNode`.
"""
abstract type ASTNode end


"""
CommandNode <: ASTNode

Represents a single parsed command with its arguments.

# Fields
- `name::String`         : command keyword (e.g. `"forward"`, `"circle"`)
- `args::Vector{Any}`    : ordered list of parsed arguments (numbers, strings, colors)
- `line::Int`            : source line number (for error reporting)

# Examples
forward 100 px   →  CommandNode("forward", [100.0, "px"], 1)
circle  30 px    →  CommandNode("circle",  [30.0,  "px"], 2)
layer "bg"       →  CommandNode("layer",   ["bg"],        3)
"""
struct CommandNode <: ASTNode
    name::String
    args::Vector{Any}
    line::Int
end


"""
ProgramNode <: ASTNode

Root node of the AST. Holds the full ordered list of parsed commands.

# Fields
- `commands::Vector{CommandNode}` : all commands in source order
"""
struct ProgramNode <: ASTNode
    commands::Vector{CommandNode}
end


# =============================================================================
# SECTION 3 — Geometry Primitives
# =============================================================================

"""
Point

A 2D coordinate in the drawing canvas.

# Fields
- `x::Float64` : horizontal position (pixels, origin at top-left)
- `y::Float64` : vertical position (pixels, origin at top-left)
"""
struct Point
    x::Float64
    y::Float64
end


"""
Color

An RGBA color value.

# Fields
- `r::UInt8` : red   channel (0–255)
- `g::UInt8` : green channel (0–255)
- `b::UInt8` : blue  channel (0–255)
- `a::UInt8` : alpha channel (0–255, default 255 = fully opaque)

# Examples
Color(255, 87, 51)       # #FF5733, fully opaque
Color(0, 0, 0, 128)      # black at 50% opacity
"""
struct Color
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8

    # Inner constructor: alpha defaults to fully opaque
    Color(r, g, b) = new(r, g, b, 255)
    Color(r, g, b, a) = new(r, g, b, a)
end


# =============================================================================
# SECTION 4 — Cursor State
# Maintained by the Interpreter throughout command execution.
# =============================================================================

"""
CursorState

The current state of the drawing cursor (inspired by Turtle graphics).

# Fields
- `position::Point`       : current (x, y) position on the canvas
- `angle::Float64`        : heading in degrees (0 = right, 90 = down)
- `pen_down::Bool`        : whether the pen is drawing (`true`) or lifted (`false`)
- `stroke_color::Color`   : current stroke (outline) color
- `fill_color::Color`     : current fill color
- `stroke_width::Float64` : stroke thickness in pixels
"""
mutable struct CursorState
    position::Point
    angle::Float64
    pen_down::Bool
    stroke_color::Color
    fill_color::Color
    stroke_width::Float64
end

"""
CursorState()

Default constructor — cursor starts at the canvas origin, pointing right,
pen down, black stroke (1px), transparent fill.
"""
CursorState() = CursorState(
    Point(0.0, 0.0),    # position: canvas origin
    0.0,                # angle: pointing right
    true,               # pen_down: drawing by default
    Color(0, 0, 0),     # stroke_color: black
    Color(0, 0, 0, 0),  # fill_color: transparent
    1.0,                # stroke_width: 1px
)


# =============================================================================
# SECTION 5 — Shapes
# Emitted by the Interpreter, consumed by the Renderer.
# =============================================================================

"""
ShapeKind

Enum of all drawable shape types supported by DraftStep.

- `SK_LINE`      : straight line segment between two points
- `SK_CIRCLE`    : circle defined by center and radius
- `SK_RECT`      : axis-aligned rectangle
- `SK_PATH`      : free-form polyline / open path
- `SK_BEZIER`    : cubic Bézier curve (computed by the C++ geometry module)
"""
@enum ShapeKind begin
    SK_LINE
    SK_CIRCLE
    SK_RECT
    SK_PATH
    SK_BEZIER
end


"""
Shape

A resolved geometric shape ready to be passed to the Renderer.

# Fields
- `kind::ShapeKind`       : type of shape
- `points::Vector{Point}` : control points (meaning depends on `kind`)
- `stroke::Color`         : outline color at the time the shape was drawn
- `fill::Color`           : fill color at the time the shape was drawn
- `stroke_width::Float64` : stroke thickness in pixels
- `layer::String`         : name of the layer this shape belongs to
- `group::String`         : name of the group this shape belongs to (empty = none)
"""
struct Shape
    kind::ShapeKind
    points::Vector{Point}
    stroke::Color
    fill::Color
    stroke_width::Float64
    layer::String
    group::String
end


# =============================================================================
# SECTION 6 — Layers and Groups
# Used by the Interpreter to organize shapes; consumed by the Renderer.
# =============================================================================

"""
Group

A named collection of shapes within a layer.
Maps to an SVG `<g>` element with an `id` attribute.

# Fields
- `name::String`          : group identifier
- `shapes::Vector{Shape}` : shapes belonging to this group
"""
mutable struct Group
    name::String
    shapes::Vector{Shape}
end

Group(name::String) = Group(name, Shape[])


"""
Layer

A named drawing layer containing groups and ungrouped shapes.
Maps to an SVG `<g>` element used as a layer (e.g. in Inkscape conventions).

# Fields
- `name::String`           : layer identifier
- `groups::Vector{Group}`  : named groups within this layer
- `shapes::Vector{Shape}`  : ungrouped shapes directly on this layer
- `visible::Bool`          : whether the layer should be rendered
"""
mutable struct Layer
    name::String
    groups::Vector{Group}
    shapes::Vector{Shape}
    visible::Bool
end

Layer(name::String) = Layer(name, Group[], Shape[], true)


# =============================================================================
# SECTION 7 — Drawing State
# Top-level state object passed through the full Interpreter execution.
# =============================================================================

"""
DrawingState

The complete mutable state of a DraftStep drawing session.
Holds the cursor, all layers, and canvas dimensions.

# Fields
- `cursor::CursorState`    : current cursor position and style
- `layers::Vector{Layer}`  : all layers in order (bottom to top)
- `active_layer::String`   : name of the currently active layer
- `active_group::String`   : name of the active group (empty = none)
- `canvas_width::Float64`  : canvas width in pixels
- `canvas_height::Float64` : canvas height in pixels
"""
mutable struct DrawingState
    cursor::CursorState
    layers::Vector{Layer}
    active_layer::String
    active_group::String
    canvas_width::Float64
    canvas_height::Float64
end

"""
DrawingState()

Default constructor — 800×600 canvas with a single default layer,
no active group, and a fresh cursor at the origin.
"""
function DrawingState()
    default_layer = Layer("default")
    DrawingState(
        CursorState(),       # fresh cursor at origin
        [default_layer],     # one default layer
        "default",           # active layer name
        "",                  # no active group
        800.0,               # canvas width  (px)
        600.0,                # canvas height (px)
    )
end

end # module Types
