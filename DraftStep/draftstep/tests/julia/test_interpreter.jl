# =============================================================================
# test_interpreter.jl — Unit Tests for Interpreter.jl
# =============================================================================
#
# Two independent test suites in this file:
#
# Suite A — Integration (coupled)
#   Uses run(source) which chains Lexer → Parser → Interpreter.
#   Validates the full pipeline end-to-end.
#   A failure here may originate in any of the three modules.
#
# Suite B — Unit (isolated)
#   Builds CommandNode / ProgramNode directly — no Lexer or Parser involved.
#   Tests only the Interpreter in isolation.
#   A failure here is guaranteed to be an Interpreter bug.
#
# Covers:
#   1. Cursor movement        6. Layers and groups
#   2. Rotation               7. Canvas
#   3. Pen control            8. Multi-command programs
#   4. Shapes                 9. Edge cases
#   5. Style                 10. Error handling
#                            11. print_state
#
# Run from the project root:
#   julia tests/julia/test_interpreter.jl
#
# Exit code 0 = all tests passed.
# =============================================================================

using Test

# ---------------------------------------------------------------------------
# Load modules — order matters: Types → Lexer → Parser → Interpreter
# ---------------------------------------------------------------------------
include("../../src/Types.jl")
import .Types

include("../../src/Lexer.jl")
import .Lexer

include("../../src/Parser.jl")
import .Parser

include("../../src/Interpreter.jl")
import .Interpreter


# =============================================================================
# Helpers
# =============================================================================

"""
run(source) → DrawingState

Tokenizes, parses and executes a DraftStep source string in one call.
"""
run(source::String) = Interpreter.execute(Parser.parse(Lexer.tokenize(source)))

"""
all_shapes(state) → Vector{Shape}

Collects every shape from all layers and groups into a flat list.
"""
function all_shapes(state::Types.DrawingState)::Vector{Types.Shape}
    shapes = Types.Shape[]
    for layer in state.layers
        append!(shapes, layer.shapes)
        for group in layer.groups
            append!(shapes, group.shapes)
        end
    end
    return shapes
end

# Floating point tolerance for position comparisons
# ε (Epsilon) - In mathematics, often represents a very small decimal number
# or one close to zero.
const ε = 1e-9


# =============================================================================
# TEST SUITE
# =============================================================================

@testset "Suite A — Integration (Lexer + Parser + Interpreter)" begin

    # -------------------------------------------------------------------------
    @testset "1 · Cursor movement" begin

        @testset "forward moves cursor along angle 0 (right)" begin
            state = run("forward 100 px\n")
            @test abs(state.cursor.position.x - 100.0) < ε
            @test abs(state.cursor.position.y - 0.0) < ε
        end

        @testset "forward 0 px does not move cursor" begin
            state = run("forward 0 px\n")
            @test state.cursor.position.x == 0.0
            @test state.cursor.position.y == 0.0
        end

        @testset "backward moves cursor in opposite direction" begin
            state = run("backward 50 px\n")
            @test abs(state.cursor.position.x - (-50.0)) < ε
            @test abs(state.cursor.position.y - 0.0) < ε
        end

        @testset "forward after right 90 moves cursor downward" begin
            state = run("right 90 deg\nforward 100 px\n")
            @test abs(state.cursor.position.x - 0.0) < ε
            @test abs(state.cursor.position.y - 100.0) < ε
        end

        @testset "two forward steps accumulate position" begin
            state = run("forward 40 px\nforward 60 px\n")
            @test abs(state.cursor.position.x - 100.0) < ε
        end

        @testset "home reset position and angle" begin
            state = run("forward 100 px\nright 90 deg\nhome\n")
            @test state.cursor.position.x == 0.0
            @test state.cursor.position.y == 0.0
            @test state.cursor.angle      == 0.0
        end

        @testset "moveto positions the cursor in absolute coordinates" begin
            state = run("moveto 200 150\n")
            @test state.cursor.position.x == 200.0
            @test state.cursor.position.y == 150.0
        end

        @testset "face defines absolute angle" begin
            state = run("right 45 deg\nface 90 deg\n")
            @test state.cursor.angle == 90.0
        end

        @testset "face with rad is converted" begin
            state = run("face 1 rad\n")
            @test abs(state.cursor.angle - (180.0 / π)) < 1e-9
        end

    end # cursor movement


    # -------------------------------------------------------------------------
    @testset "2 · Rotation" begin

        @testset "right increases angle" begin
            state = run("right 90 deg\n")
            @test state.cursor.angle == 90.0
        end

        @testset "left decreases angle" begin
            state = run("left 45 deg\n")
            @test state.cursor.angle == 315.0   # 0 - 45 = -45 → normalized 315
        end

        @testset "angle normalizes above 360" begin
            state = run("right 370 deg\n")
            @test state.cursor.angle == 10.0
        end

        @testset "angle normalizes to 0 on full rotation" begin
            state = run("right 360 deg\n")
            @test state.cursor.angle == 0.0
        end

        @testset "rad unit is converted to degrees" begin
            state = run("right 1 rad\n")
            expected = 1.0 * 180.0 / π
            @test abs(state.cursor.angle - expected) < ε
        end

        @testset "chained rotations accumulate correctly" begin
            state = run("right 90 deg\nright 90 deg\nright 90 deg\n")
            @test state.cursor.angle == 270.0
        end

    end # rotation


    # -------------------------------------------------------------------------
    @testset "3 · Pen control" begin

        @testset "default pen is down" begin
            state = run("")
            @test state.cursor.pen_down == true
        end

        @testset "penup lifts pen" begin
            state = run("penup\n")
            @test state.cursor.pen_down == false
        end

        @testset "pendown lowers pen" begin
            state = run("penup\npendown\n")
            @test state.cursor.pen_down == true
        end

        @testset "forward with pen down emits a line shape" begin
            state = run("forward 100 px\n")
            shapes = all_shapes(state)
            @test length(shapes) == 1
            @test shapes[1].kind == Types.SK_LINE
        end

        @testset "forward with pen up emits no shape" begin
            state = run("penup\nforward 100 px\n")
            @test isempty(all_shapes(state))
        end

        @testset "backward with pen down emits a line shape" begin
            state = run("backward 50 px\n")
            shapes = all_shapes(state)
            @test length(shapes) == 1
            @test shapes[1].kind == Types.SK_LINE
        end

        @testset "backward with pen up emits no shape" begin
            state = run("penup\nbackward 50 px\n")
            @test isempty(all_shapes(state))
        end

    end # pen control


    # -------------------------------------------------------------------------
    @testset "4 · Shapes" begin

        @testset "circle emits SK_CIRCLE with 2 points (center + radius point)" begin
            state = run("circle 30 px\n")
            shapes = all_shapes(state)
            @test length(shapes) == 1
            @test shapes[1].kind == Types.SK_CIRCLE
            @test length(shapes[1].points) == 2
        end

        @testset "circle center matches cursor position" begin
            state = run("forward 50 px\ncircle 30 px\n")
            shapes = all_shapes(state)
            circle = shapes[end]
            @test abs(circle.points[1].x - 50.0) < ε
        end

        @testset "circle with pen up emits no shape" begin
            state = run("penup\ncircle 30 px\n")
            @test isempty(all_shapes(state))
        end

        @testset "rect emits SK_RECT with 4 corner points" begin
            state = run("rect 100 px 50 px\n")
            shapes = all_shapes(state)
            @test length(shapes) == 1
            @test shapes[1].kind == Types.SK_RECT
            @test length(shapes[1].points) == 4
        end

        @testset "rect corner points are correct" begin
            state = run("rect 100 px 50 px\n")
            pts = all_shapes(state)[1].points
            # top-left at origin
            @test abs(pts[1].x - 0.0) < ε
            @test abs(pts[1].y - 0.0) < ε
            # top-right
            @test abs(pts[2].x - 100.0) < ε
            @test abs(pts[2].y - 0.0) < ε
            # bottom-right
            @test abs(pts[3].x - 100.0) < ε
            @test abs(pts[3].y - 50.0) < ε
            # bottom-left
            @test abs(pts[4].x - 0.0) < ε
            @test abs(pts[4].y - 50.0) < ε
        end

        @testset "rect with pen up emits no shape" begin
            state = run("penup\nrect 100 px 50 px\n")
            @test isempty(all_shapes(state))
        end

    end # shapes


    # -------------------------------------------------------------------------
    @testset "5 · Style" begin

        @testset "color sets stroke_color with 8 hex digits" begin
            state = run("color #FF573380\n")
            c = state.cursor.stroke_color
            @test c.r == 0xFF
            @test c.g == 0x57
            @test c.b == 0x33
            @test c.a == 0x80
        end

        @testset "color sets stroke_color" begin
            state = run("color #FF5733\n")
            c = state.cursor.stroke_color
            @test c.r == 0xFF
            @test c.g == 0x57
            @test c.b == 0x33
            @test c.a == 0xFF
        end

        @testset "fill sets fill_color with 8 hex digits" begin
            state = run("fill #00FF0080\n")
            c = state.cursor.fill_color
            @test c.r == 0x00
            @test c.g == 0xFF
            @test c.b == 0x00
            @test c.a == 0x80
        end

        @testset "fill sets fill_color" begin
            state = run("fill #00FF00\n")
            c = state.cursor.fill_color
            @test c.r == 0x00
            @test c.g == 0xFF
            @test c.b == 0x00
            @test c.a == 0xFF
        end

        @testset "3-digit color shorthand is expanded" begin
            state = run("color #F53\n")
            c = state.cursor.stroke_color
            @test c.r == 0xFF
            @test c.g == 0x55
            @test c.b == 0x33
            @test c.a == 0xFF
        end

        @testset "strokewidth sets stroke_width" begin
            state = run("strokewidth 3 px\n")
            @test state.cursor.stroke_width == 3.0
        end

        @testset "shape inherits stroke color at time of drawing" begin
            state = run("color #FF0000\nforward 100 px\n")
            shape = all_shapes(state)[1]
            @test shape.stroke.r == 0xFF
            @test shape.stroke.g == 0x00
            @test shape.stroke.b == 0x00
            @test shape.stroke.a == 0xFF
        end

        @testset "shape inherits stroke width at time of drawing" begin
            state = run("strokewidth 5 px\nforward 100 px\n")
            shape = all_shapes(state)[1]
            @test shape.stroke_width == 5.0
        end

    end # style


    # -------------------------------------------------------------------------
    @testset "6 · Layers and groups" begin

        @testset "default layer exists after empty program" begin
            state = run("")
            @test length(state.layers) == 1
            @test state.layers[1].name == "default"
        end

        @testset "layer command creates a new layer" begin
            state = run("layer \"background\"\n")
            names = [l.name for l in state.layers]
            @test "background" in names
        end

        @testset "layer command switches active layer" begin
            state = run("layer \"background\"\n")
            @test state.active_layer == "background"
        end

        @testset "shapes go to the active layer" begin
            state = run("layer \"background\"\nforward 100 px\n")
            bg = findfirst(l -> l.name == "background", state.layers)
            @test length(state.layers[bg].shapes) == 1
        end

        @testset "group command sets active group" begin
            state = run("group \"tree\"\n")
            @test state.active_group == "tree"
        end

        @testset "shapes go to active group when set" begin
            state = run("group \"tree\"\nforward 100 px\n")
            layer = state.layers[1]
            grp = findfirst(g -> g.name == "tree", layer.groups)
            @test length(layer.groups[grp].shapes) == 1
        end

        @testset "switching layer resets active group" begin
            state = run("group \"tree\"\nlayer \"background\"\n")
            @test state.active_group == ""
        end

        @testset "shape records its layer name" begin
            state = run("layer \"fg\"\nforward 100 px\n")
            shape = all_shapes(state)[1]
            @test shape.layer == "fg"
        end

        @testset "shape records its group name" begin
            state = run("group \"tree\"\nforward 100 px\n")
            shape = all_shapes(state)[1]
            @test shape.group == "tree"
        end

        @testset "ungrouped shape has empty group name" begin
            state = run("forward 100 px\n")
            shape = all_shapes(state)[1]
            @test shape.group == ""
        end

    end # layers and groups


    # -------------------------------------------------------------------------
    @testset "7 · Canvas" begin

        @testset "default canvas is 800 × 600" begin
            state = run("")
            @test state.canvas_width == 800.0
            @test state.canvas_height == 600.0
        end

        @testset "canvas command resizes" begin
            state = run("canvas 1920 1080\n")
            @test state.canvas_width == 1920.0
            @test state.canvas_height == 1080.0
        end

    end # canvas


    # -------------------------------------------------------------------------
    @testset "8 · Multi-command programs" begin

        @testset "square draws 4 line shapes" begin
            src = """
            pendown
            forward 100 px
            right 90 deg
            forward 100 px
            right 90 deg
            forward 100 px
            right 90 deg
            forward 100 px
            """
            state = run(src)
            shapes = all_shapes(state)
            lines = filter(s -> s.kind == Types.SK_LINE, shapes)
            @test length(lines) == 4
        end

        @testset "cursor returns near origin after full square" begin
            src = """
            forward 100 px
            right 90 deg
            forward 100 px
            right 90 deg
            forward 100 px
            right 90 deg
            forward 100 px
            right 90 deg
            """
            state = run(src)
            @test abs(state.cursor.position.x) < ε
            @test abs(state.cursor.position.y) < ε
            @test state.cursor.angle == 0.0
        end

        @testset "mixed shapes in one program" begin
            src = """
            forward 100 px
            circle 30 px
            rect 50 px 25 px
            """
            state = run(src)
            shapes = all_shapes(state)
            @test length(shapes) == 3
            @test shapes[1].kind == Types.SK_LINE
            @test shapes[2].kind == Types.SK_CIRCLE
            @test shapes[3].kind == Types.SK_RECT
        end

    end # multi-command


    # -------------------------------------------------------------------------
    @testset "9 · Edge cases" begin

        @testset "empty program returns default DrawingState" begin
            state = run("")
            @test state isa Types.DrawingState
            @test isempty(all_shapes(state))
        end

        @testset "execute accepts external DrawingState" begin
            custom = Types.DrawingState()
            custom.canvas_width = 1024.0
            prog = Parser.parse(Lexer.tokenize("forward 100 px\n"))
            state = Interpreter.execute(prog; state = custom)
            @test state.canvas_width == 1024.0
            @test length(all_shapes(state)) == 1
        end

        @testset "pen up movement does not emit shapes" begin
            state = run("penup\nforward 100 px\nleft 90 deg\nforward 50 px\n")
            @test isempty(all_shapes(state))
        end

        @testset "creating same layer twice does not duplicate it" begin
            state = run("layer \"bg\"\nlayer \"bg\"\n")
            bg_count = count(l -> l.name == "bg", state.layers)
            @test bg_count == 1
        end

    end # edge cases


    # -------------------------------------------------------------------------
    @testset "10 · Error handling" begin

        @testset "length unit used as angle raises InterpreterError" begin
            # to_deg rejects 'px' as an angle unit
            prog = Parser.parse(Lexer.tokenize("right 90 px\n"))
            @test_throws Interpreter.InterpreterError Interpreter.execute(prog)
        end

        @testset "angle unit used as length raises InterpreterError" begin
            # to_px rejects 'deg' as a length unit
            prog = Parser.parse(Lexer.tokenize("forward 100 deg\n"))
            @test_throws Interpreter.InterpreterError Interpreter.execute(prog)
        end

        @testset "InterpreterError carries correct line number" begin
            prog = Parser.parse(Lexer.tokenize("forward 100 px\nright 45 px\n"))
            err = nothing
            try
                Interpreter.execute(prog)
            catch e
                err = e
            end
            @test err isa Interpreter.InterpreterError
            @test err.line == 2
        end

    end # error handling


    # -------------------------------------------------------------------------
    @testset "11 · print_state" begin

        @testset "prints without error" begin
            state = run("forward 100 px\ncircle 30 px\n")
            buf = IOBuffer()
            @test_nowarn Interpreter.print_state(state; io = buf)
        end

        @testset "output contains canvas dimensions" begin
            state = run("canvas 1920 1080\n")
            buf = IOBuffer()
            Interpreter.print_state(state; io = buf)
            output = String(take!(buf))
            @test occursin("1920", output)
            @test occursin("1080", output)
        end

        @testset "output contains cursor position" begin
            state = run("forward 100 px\n")
            buf = IOBuffer()
            Interpreter.print_state(state; io = buf)
            output = String(take!(buf))
            @test occursin("100", output)
        end

        @testset "output contains layer name" begin
            state = run("layer \"background\"\n")
            buf = IOBuffer()
            Interpreter.print_state(state; io = buf)
            output = String(take!(buf))
            @test occursin("background", output)
        end

        @testset "output contains total shapes count" begin
            state = run("forward 100 px\ncircle 30 px\n")
            buf = IOBuffer()
            Interpreter.print_state(state; io = buf)
            output = String(take!(buf))
            @test occursin("Total shapes", output)
            @test occursin("2", output)
        end

    end # print_state

end # Suite A — Integration


# =============================================================================
# SUITE B — Unit tests (Interpreter isolated)
# CommandNode and ProgramNode are built directly — no Lexer or Parser.
# =============================================================================

"""
make_prog(cmds...) → ProgramNode

Builds a ProgramNode from a list of (name, args, line) tuples.
"""
make_prog(cmds...) = Types.ProgramNode([
    Types.CommandNode(name, collect(Any, args), line) for (name, args, line) in cmds
])

"""
exec(cmds...) → DrawingState

Builds and executes a ProgramNode directly from (name, args, line) tuples.
"""
exec(cmds...) = Interpreter.execute(make_prog(cmds...))


@testset "Suite B — Unit (Interpreter isolated)" begin

    # -------------------------------------------------------------------------
    @testset "1 · Cursor movement" begin

        @testset "forward moves along angle 0" begin
            state = exec(("forward", [100.0, "px"], 1))
            @test abs(state.cursor.position.x - 100.0) < ε
            @test abs(state.cursor.position.y - 0.0) < ε
        end

        @testset "backward moves in opposite direction" begin
            state = exec(("backward", [50.0, "px"], 1))
            @test abs(state.cursor.position.x - (-50.0)) < ε
        end

        @testset "forward after right 90 moves downward" begin
            state = exec(("right", [90.0, "deg"], 1), ("forward", [100.0, "px"], 2))
            @test abs(state.cursor.position.x - 0.0) < ε
            @test abs(state.cursor.position.y - 100.0) < ε
        end

    end # movement


    # -------------------------------------------------------------------------
    @testset "2 · Rotation" begin

        @testset "right increases angle" begin
            state = exec(("right", [90.0, "deg"], 1))
            @test state.cursor.angle == 90.0
        end

        @testset "left decreases and normalizes angle" begin
            state = exec(("left", [45.0, "deg"], 1))
            @test state.cursor.angle == 315.0
        end

        @testset "rad unit converts to degrees" begin
            state = exec(("right", [1.0, "rad"], 1))
            @test abs(state.cursor.angle - (180.0 / π)) < ε
        end

        @testset "full rotation normalizes to 0" begin
            state = exec(("right", [360.0, "deg"], 1))
            @test state.cursor.angle == 0.0
        end

    end # rotation


    # -------------------------------------------------------------------------
    @testset "3 · Pen control" begin

        @testset "penup lifts pen" begin
            state = exec(("penup", [], 1))
            @test state.cursor.pen_down == false
        end

        @testset "pendown lowers pen" begin
            state = exec(("penup", [], 1), ("pendown", [], 2))
            @test state.cursor.pen_down == true
        end

        @testset "forward pen down emits SK_LINE" begin
            state = exec(("forward", [100.0, "px"], 1))
            shapes = all_shapes(state)
            @test length(shapes) == 1
            @test shapes[1].kind == Types.SK_LINE
        end

        @testset "forward pen up emits nothing" begin
            state = exec(("penup", [], 1), ("forward", [100.0, "px"], 2))
            @test isempty(all_shapes(state))
        end

    end # pen control


    # -------------------------------------------------------------------------
    @testset "4 · Shapes" begin

        @testset "circle emits SK_CIRCLE" begin
            state = exec(("circle", [30.0, "px"], 1))
            shapes = all_shapes(state)
            @test length(shapes) == 1
            @test shapes[1].kind == Types.SK_CIRCLE
            @test length(shapes[1].points) == 2
        end

        @testset "rect emits SK_RECT with 4 points" begin
            state = exec(("rect", [100.0, "px", 50.0, "px"], 1))
            shapes = all_shapes(state)
            @test length(shapes) == 1
            @test shapes[1].kind == Types.SK_RECT
            @test length(shapes[1].points) == 4
        end

        @testset "line start point matches cursor before move" begin
            state = exec(("forward", [100.0, "px"], 1))
            shape = all_shapes(state)[1]
            @test abs(shape.points[1].x - 0.0) < ε   # started at origin
            @test abs(shape.points[2].x - 100.0) < ε  # ended at 100
        end

    end # shapes


    # -------------------------------------------------------------------------
    @testset "5 · Style" begin

        @testset "color sets stroke_color" begin
            state = exec(("color", ["#FF0000"], 1))
            @test state.cursor.stroke_color.r == 0xFF
            @test state.cursor.stroke_color.g == 0x00
            @test state.cursor.stroke_color.b == 0x00
        end

        @testset "fill sets fill_color" begin
            state = exec(("fill", ["#0000FF"], 1))
            @test state.cursor.fill_color.b == 0xFF
        end

        @testset "strokewidth sets stroke_width" begin
            state = exec(("strokewidth", [4.0, "px"], 1))
            @test state.cursor.stroke_width == 4.0
        end

        @testset "shape inherits style snapshot at draw time" begin
            state = exec(
                ("color", ["#AABBCC"], 1),
                ("strokewidth", [3.0, "px"], 2),
                ("forward", [100.0, "px"], 3),
            )
            shape = all_shapes(state)[1]
            @test shape.stroke.r == 0xAA
            @test shape.stroke_width == 3.0
        end

    end # style


    # -------------------------------------------------------------------------
    @testset "6 · Layers and groups" begin

        @testset "layer creates and activates layer" begin
            state = exec(("layer", ["bg"], 1))
            @test state.active_layer == "bg"
            @test any(l -> l.name == "bg", state.layers)
        end

        @testset "same layer twice does not duplicate" begin
            state = exec(("layer", ["bg"], 1), ("layer", ["bg"], 2))
            @test count(l -> l.name == "bg", state.layers) == 1
        end

        @testset "group sets active group" begin
            state = exec(("group", ["tree"], 1))
            @test state.active_group == "tree"
        end

        @testset "switching layer resets group" begin
            state = exec(("group", ["tree"], 1), ("layer", ["fg"], 2))
            @test state.active_group == ""
        end

        @testset "shape placed in correct layer and group" begin
            state = exec(
                ("layer", ["fg"], 1),
                ("group", ["tree"], 2),
                ("forward", [100.0, "px"], 3),
            )
            shape = all_shapes(state)[1]
            @test shape.layer == "fg"
            @test shape.group == "tree"
        end

    end # layers and groups


    # -------------------------------------------------------------------------
    @testset "7 · Canvas" begin

        @testset "canvas resizes width and height" begin
            state = exec(("canvas", [1280.0, 720.0], 1))
            @test state.canvas_width == 1280.0
            @test state.canvas_height == 720.0
        end

    end # canvas


    # -------------------------------------------------------------------------
    @testset "8 · Error handling" begin

        @testset "px used as angle raises InterpreterError" begin
            prog = make_prog(("right", [90.0, "px"], 1))
            @test_throws Interpreter.InterpreterError Interpreter.execute(prog)
        end

        @testset "deg used as length raises InterpreterError" begin
            prog = make_prog(("forward", [100.0, "deg"], 1))
            @test_throws Interpreter.InterpreterError Interpreter.execute(prog)
        end

        @testset "error line number is correct" begin
            prog = make_prog(
                ("forward", [100.0, "px"], 1),
                ("right", [45.0, "px"], 2),   # wrong unit
            )
            err = nothing
            try
                Interpreter.execute(prog)
            catch e
                err = e
            end
            @test err isa Interpreter.InterpreterError
            @test err.line == 2
        end

    end # error handling

end # Suite B — Unit


println("\n✓ All Interpreter tests passed.\n")
