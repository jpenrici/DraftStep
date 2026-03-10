# =============================================================================
# Interpreter.jl — DraftStep Command Interpreter
# =============================================================================
#
# Walks a ProgramNode (AST) produced by the Parser and executes each
# CommandNode, updating a DrawingState and emitting Shape values that
# the Renderer will consume.
#
# Pipeline position:
#   Parser.parse → ProgramNode → Interpreter.execute → DrawingState
#
# Responsibilities:
#   - Maintain cursor position, angle, pen state and style
#   - Emit Shape values into the active layer / group
#   - Manage layers and groups (create on first use)
#   - Resize the canvas via the `canvas` command
#
# Coordinate system:
#   Origin (0, 0) is at the top-left corner.
#   Angle 0° points right (+X). Angle increases clockwise (screen space).
#   forward / backward move the cursor along the heading vector.
#
# Usage:
#   include("Types.jl")
#   include("Lexer.jl")
#   include("Parser.jl")
#   include("Interpreter.jl")
#   tokens  = Lexer.tokenize(source)
#   program = Parser.parse(tokens)
#   state   = Interpreter.execute(program)
#
# =============================================================================

module Interpreter

import ..Types

export execute, InterpreterError


# =============================================================================
# SECTION 1 — Error type
# =============================================================================

"""
InterpreterError

Raised when a command cannot be executed due to a semantic problem,
such as referencing a layer that was never created with `layer`.

# Fields
- `message::String` : human-readable description of the problem
- `line::Int`       : source line of the command that caused the error
"""
struct InterpreterError <: Exception
    message::String
    line::Int
end

Base.showerror(io::IO, e::InterpreterError) =
    print(io, "InterpreterError at line $(e.line): $(e.message)")


# =============================================================================
# SECTION 2 — Geometry helpers
# =============================================================================

"""
deg_to_rad(deg) → Float64

Converts degrees to radians.
"""
deg_to_rad(deg::Float64) = deg * π / 180.0

"""
rad_to_deg(rad) → Float64

Converts radians to degrees.
"""
rad_to_deg(rad::Float64) = rad * 180.0 / π

"""
normalize_angle(deg) → Float64

Normalizes an angle in degrees to the range [0, 360).
"""
normalize_angle(deg::Float64) = mod(deg, 360.0)

"""
move_point(origin, angle_deg, distance) → Point

Returns the point reached by moving `distance` pixels from `origin`
along the heading `angle_deg` (clockwise from right, screen coordinates).
"""
function move_point(origin::Types.Point, angle_deg::Float64, distance::Float64)::Types.Point
    rad = deg_to_rad(angle_deg)
    Types.Point(origin.x + distance * cos(rad), origin.y + distance * sin(rad))
end

"""
parse_color(hex, line) → Color

Parses a hex color string (#RGB or #RRGGBB) into a `Color` value.
Raises `InterpreterError` if the format is invalid.
"""
function parse_color(hex::String, line::Int)::Types.Color
    h = lstrip(hex, '#')

    # Expand 3-digit shorthand #RGB → #RRGGBB
    if length(h) == 3
        h = string(h[1], h[1], h[2], h[2], h[3], h[3])
    end

    if length(h) != 6
        throw(InterpreterError("invalid color '$hex'", line))
    end

    r = parse(UInt8, h[1:2], base = 16)
    g = parse(UInt8, h[3:4], base = 16)
    b = parse(UInt8, h[5:6], base = 16)
    return Types.Color(r, g, b)
end

"""
to_px(value, unit, line) → Float64

Converts a measurement value to pixels.
Currently `px` is pass-through; `deg` and `rad` are angle units and
should not be passed to this function (they are handled by rotate commands).
"""
function to_px(value::Float64, unit::String, line::Int)::Float64
    if unit == "px"
        return value
    end
    throw(InterpreterError("unit '$unit' cannot be used as a length measurement", line))
end

"""
to_deg(value, unit, line) → Float64

Converts a rotation value to degrees.
Accepts `deg` (pass-through) and `rad` (converted).
"""
function to_deg(value::Float64, unit::String, line::Int)::Float64
    if unit == "deg"
        return value
    elseif unit == "rad"
        return rad_to_deg(value)
    end
    throw(InterpreterError("unit '$unit' cannot be used as an angle measurement", line))
end


# =============================================================================
# SECTION 3 — Layer and group helpers
# =============================================================================

"""
find_layer(state, name) → Layer or nothing

Returns the layer with the given name, or `nothing` if not found.
"""
function find_layer(state::Types.DrawingState, name::String)::Union{Types.Layer,Nothing}
    idx = findfirst(l -> l.name == name, state.layers)
    return idx === nothing ? nothing : state.layers[idx]
end

"""
ensure_layer!(state, name) → Layer

Returns the layer with `name`, creating it if it does not exist yet.
"""
function ensure_layer!(state::Types.DrawingState, name::String)::Types.Layer
    layer = find_layer(state, name)
    if layer === nothing
        new_layer = Types.Layer(name)
        push!(state.layers, new_layer)
        return new_layer
    end
    return layer
end

"""
ensure_group!(layer, name) → Group

Returns the group with `name` inside `layer`, creating it if needed.
"""
function ensure_group!(layer::Types.Layer, name::String)::Types.Group
    idx = findfirst(g -> g.name == name, layer.groups)
    if idx === nothing
        new_group = Types.Group(name)
        push!(layer.groups, new_group)
        return new_group
    end
    return layer.groups[idx]
end

"""
emit_shape!(state, shape)

Adds `shape` to the active group (if any) or directly to the active layer.
"""
function emit_shape!(state::Types.DrawingState, shape::Types.Shape)
    layer = ensure_layer!(state, state.active_layer)

    if state.active_group != ""
        group = ensure_group!(layer, state.active_group)
        push!(group.shapes, shape)
    else
        push!(layer.shapes, shape)
    end
end


# =============================================================================
# SECTION 4 — Command executors
# One function per command keyword, dispatched from execute_command.
# Each function receives the DrawingState and the CommandNode args.
# =============================================================================

# --- Movement ---

function exec_forward!(state::Types.DrawingState, args::Vector{Any}, line::Int)
    dist = to_px(args[1], args[2], line)
    from = state.cursor.position
    to = move_point(from, state.cursor.angle, dist)

    if state.cursor.pen_down
        shape = Types.Shape(
            Types.SK_LINE,
            [from, to],
            state.cursor.stroke_color,
            state.cursor.fill_color,
            state.cursor.stroke_width,
            state.active_layer,
            state.active_group,
        )
        emit_shape!(state, shape)
    end

    state.cursor.position = to
end

function exec_backward!(state::Types.DrawingState, args::Vector{Any}, line::Int)
    dist = to_px(args[1], args[2], line)
    from = state.cursor.position
    # Backward = move in the opposite direction (angle + 180°)
    to = move_point(from, state.cursor.angle + 180.0, dist)

    if state.cursor.pen_down
        shape = Types.Shape(
            Types.SK_LINE,
            [from, to],
            state.cursor.stroke_color,
            state.cursor.fill_color,
            state.cursor.stroke_width,
            state.active_layer,
            state.active_group,
        )
        emit_shape!(state, shape)
    end

    state.cursor.position = to
end

# --- Rotation ---

function exec_left!(state::Types.DrawingState, args::Vector{Any}, line::Int)
    angle = to_deg(args[1], args[2], line)
    state.cursor.angle = normalize_angle(state.cursor.angle - angle)
end

function exec_right!(state::Types.DrawingState, args::Vector{Any}, line::Int)
    angle = to_deg(args[1], args[2], line)
    state.cursor.angle = normalize_angle(state.cursor.angle + angle)
end

# --- Pen control ---

exec_pendown!(state::Types.DrawingState, args::Vector{Any}, line::Int) =
    (state.cursor.pen_down = true)

exec_penup!(state::Types.DrawingState, args::Vector{Any}, line::Int) =
    (state.cursor.pen_down = false)

# --- Shapes ---

function exec_circle!(state::Types.DrawingState, args::Vector{Any}, line::Int)
    radius = to_px(args[1], args[2], line)
    center = state.cursor.position

    if state.cursor.pen_down
        shape = Types.Shape(
            Types.SK_CIRCLE,
            [center, Types.Point(center.x + radius, center.y)],
            state.cursor.stroke_color,
            state.cursor.fill_color,
            state.cursor.stroke_width,
            state.active_layer,
            state.active_group,
        )
        emit_shape!(state, shape)
    end
end

function exec_rect!(state::Types.DrawingState, args::Vector{Any}, line::Int)
    width = to_px(args[1], args[2], line)
    height = to_px(args[3], args[4], line)
    origin = state.cursor.position

    if state.cursor.pen_down
        # points: top-left, top-right, bottom-right, bottom-left
        tl = origin
        tr = Types.Point(origin.x + width, origin.y)
        br = Types.Point(origin.x + width, origin.y + height)
        bl = Types.Point(origin.x, origin.y + height)

        shape = Types.Shape(
            Types.SK_RECT,
            [tl, tr, br, bl],
            state.cursor.stroke_color,
            state.cursor.fill_color,
            state.cursor.stroke_width,
            state.active_layer,
            state.active_group,
        )
        emit_shape!(state, shape)
    end
end

# --- Style ---

function exec_color!(state::Types.DrawingState, args::Vector{Any}, line::Int)
    state.cursor.stroke_color = parse_color(args[1], line)
end

function exec_fill!(state::Types.DrawingState, args::Vector{Any}, line::Int)
    state.cursor.fill_color = parse_color(args[1], line)
end

function exec_strokewidth!(state::Types.DrawingState, args::Vector{Any}, line::Int)
    state.cursor.stroke_width = to_px(args[1], args[2], line)
end

# --- Organization ---

function exec_layer!(state::Types.DrawingState, args::Vector{Any}, line::Int)
    name = args[1]
    ensure_layer!(state, name)
    state.active_layer = name
    state.active_group = ""   # reset group when switching layers
end

function exec_group!(state::Types.DrawingState, args::Vector{Any}, line::Int)
    state.active_group = args[1]
end

# --- Canvas ---

function exec_canvas!(state::Types.DrawingState, args::Vector{Any}, line::Int)
    state.canvas_width = args[1]
    state.canvas_height = args[2]
end


# =============================================================================
# SECTION 5 — Command dispatch table
# Maps command names to their executor functions.
# =============================================================================

"""
EXECUTORS

Dispatch table mapping each command keyword to its executor function.
Signature of every executor:
    (state::DrawingState, args::Vector{Any}, line::Int) → nothing
"""
const EXECUTORS = Dict{String, Function}(
    "forward" => exec_forward!,
    "backward" => exec_backward!,
    "left" => exec_left!,
    "right" => exec_right!,
    "penup" => exec_penup!,
    "pendown" => exec_pendown!,
    "circle" => exec_circle!,
    "rect" => exec_rect!,
    "color" => exec_color!,
    "fill" => exec_fill!,
    "strokewidth" => exec_strokewidth!,
    "layer" => exec_layer!,
    "group" => exec_group!,
    "canvas" => exec_canvas!,
)


# =============================================================================
# SECTION 6 — Main entry point
# =============================================================================

"""
execute_command!(state, cmd)

Dispatches a single `CommandNode` to its executor.
Raises `InterpreterError` if the command has no registered executor.
"""
function execute_command!(state::Types.DrawingState, cmd::Types.CommandNode)
    executor = get(EXECUTORS, cmd.name, nothing)
    if executor === nothing
        throw(InterpreterError("unknown command '$(cmd.name)'", cmd.line))
    end
    executor(state, cmd.args, cmd.line)
end


"""
execute(program; state=nothing) → DrawingState

Executes all commands in `program` against `state`.
If `state` is `nothing`, a fresh `DrawingState` is created automatically.

Returns the final `DrawingState` after all commands have run.

# Example
```julia
tokens  = Lexer.tokenize("forward 100 px\\ncircle 30 px\\n")
program = Parser.parse(tokens)
state   = Interpreter.execute(program)
# state.layers[1].shapes contains the emitted shapes
```
"""
function execute(
    program::Types.ProgramNode;
    state::Union{Types.DrawingState,Nothing} = nothing,
)::Types.DrawingState

    if state === nothing
        state = Types.DrawingState()
    end

    for cmd in program.commands
        execute_command!(state, cmd)
    end

    return state
end


# =============================================================================
# SECTION 7 — Debug utilities
# =============================================================================

"""
print_state(state; io=stdout)

Pretty-prints the current `DrawingState` to `io`.
Shows canvas dimensions, cursor state, and all layers with their shapes.
"""
function print_state(state::Types.DrawingState; io::IO = stdout)
    c = state.cursor

    println(io, "─────────────────────────────────────────")
    println(io, "  DraftStep Interpreter — state dump")
    println(io, "─────────────────────────────────────────")
    println(io, "  Canvas   : $(state.canvas_width) × $(state.canvas_height) px")
    println(io, "  Cursor")
    println(io, "    position     : ($(c.position.x), $(c.position.y))")
    println(io, "    angle        : $(c.angle)°")
    println(io, "    pen_down     : $(c.pen_down)")
    println(
        io,
        "    stroke_color : rgb($(c.stroke_color.r), $(c.stroke_color.g), $(c.stroke_color.b))",
    )
    println(
        io,
        "    fill_color   : rgba($(c.fill_color.r), $(c.fill_color.g), $(c.fill_color.b), $(c.fill_color.a))",
    )
    println(io, "    stroke_width : $(c.stroke_width) px")
    println(io, "  Active layer : $(state.active_layer)")
    println(
        io,
        "  Active group : $(state.active_group == "" ? "(none)" : state.active_group)",
    )
    println(io, "─────────────────────────────────────────")

    total_shapes = 0
    for layer in state.layers
        n_ungrouped = length(layer.shapes)
        n_grouped = sum(length(g.shapes) for g in layer.groups; init = 0)
        println(
            io,
            "  Layer '$(layer.name)'  " *
            "($(n_ungrouped) ungrouped + $(n_grouped) grouped shapes)",
        )

        for shape in layer.shapes
            println(
                io,
                "    $(rpad(string(shape.kind), 12))  " * "points=$(length(shape.points))",
            )
            total_shapes += 1
        end

        for group in layer.groups
            println(io, "    Group '$(group.name)'")
            for shape in group.shapes
                println(
                    io,
                    "      $(rpad(string(shape.kind), 12))  " *
                    "points=$(length(shape.points))",
                )
                total_shapes += 1
            end
        end
    end

    println(io, "─────────────────────────────────────────")
    println(io, "  Total shapes : $total_shapes")
    println(io, "─────────────────────────────────────────")
end

end # module Interpreter
