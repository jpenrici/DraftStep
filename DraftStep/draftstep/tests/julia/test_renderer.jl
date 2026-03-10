# =============================================================================
# test_renderer.jl — Unit Tests for Renderer.jl and SVGRenderer.jl
# =============================================================================
#
# Two independent test suites:
#
# Suite A — Integration (coupled)
#   Uses run(source) which chains Lexer → Parser → Interpreter → SVGRenderer.
#   Validates the full pipeline end-to-end producing real SVG output.
#
# Suite B — Unit (isolated)
#   Builds DrawingState directly — no Lexer, Parser or Interpreter involved.
#   Tests only the Renderer in isolation.
#   A failure here is guaranteed to be a Renderer bug.
#
# Covers:
#   1. SVG document structure    (header, root element, viewBox)
#   2. Shape serialization       (line, circle, rect, path, bezier)
#   3. Layers and groups         (SVG <g> elements, Inkscape attributes)
#   4. Style attributes          (stroke, fill, stroke-width)
#   5. Invisible layers          (skipped in output)
#   6. File output               (render to disk)
#   7. render_to_string          (no disk I/O)
#   8. Edge cases                (empty state, transparent colors)
#
# Run from the project root:
#   julia tests/julia/test_renderer.jl
#
# Exit code 0 = all tests passed.
# =============================================================================

using Test

using Printf

# ---------------------------------------------------------------------------
# Load modules — order: Types → Renderer → SVGRenderer
# For Suite A also load: Lexer → Parser → Interpreter
# ---------------------------------------------------------------------------
include("../../src/Types.jl")
import .Types

include("../../src/Renderer.jl")
import .Renderer

include("../../src/Renderers/SVGRenderer.jl")
import .SVGRenderer

include("../../src/Lexer.jl")
import .Lexer

include("../../src/Parser.jl")
import .Parser

include("../../src/Interpreter.jl")
import .Interpreter


# =============================================================================
# Helpers — Suite A
# =============================================================================

"""
run(source) → String

Full pipeline: tokenize → parse → execute → render to SVG string.
"""
run(source::String) =
    SVGRenderer.render_to_string(Interpreter.execute(Parser.parse(Lexer.tokenize(source))))


# =============================================================================
# Helpers — Suite B (isolated state builders)
# =============================================================================

"""
empty_state() → DrawingState

Returns a fresh default DrawingState (800×600, no shapes).
"""
empty_state() = Types.DrawingState()

"""
state_with_shapes(shapes...) → DrawingState

Builds a DrawingState with the given shapes on the default layer.
"""
function state_with_shapes(shapes...)
    state = Types.DrawingState()
    for shape in shapes
        push!(state.layers[1].shapes, shape)
    end
    return state
end

"""
make_line(x1, y1, x2, y2; stroke=black, fill=transparent, sw=1.0)

Builds a SK_LINE Shape between two points.
"""
function make_line(
    x1,
    y1,
    x2,
    y2;
    stroke = Types.Color(0, 0, 0),
    fill = Types.Color(0, 0, 0, 0),
    sw = 1.0,
)
    Types.Shape(
        Types.SK_LINE,
        [Types.Point(x1, y1), Types.Point(x2, y2)],
        stroke,
        fill,
        sw,
        "default",
        "",
    )
end

"""
make_circle(cx, cy, r; stroke=black, fill=transparent, sw=1.0)

Builds a SK_CIRCLE Shape with center and radius point.
"""
function make_circle(
    cx,
    cy,
    r;
    stroke = Types.Color(0, 0, 0),
    fill = Types.Color(0, 0, 0, 0),
    sw = 1.0,
)
    Types.Shape(
        Types.SK_CIRCLE,
        [Types.Point(cx, cy), Types.Point(cx + r, cy)],
        stroke,
        fill,
        sw,
        "default",
        "",
    )
end

"""
make_rect(x, y, w, h; stroke=black, fill=transparent, sw=1.0)

Builds a SK_RECT Shape from origin, width and height.
"""
function make_rect(
    x,
    y,
    w,
    h;
    stroke = Types.Color(0, 0, 0),
    fill = Types.Color(0, 0, 0, 0),
    sw = 1.0,
)
    Types.Shape(
        Types.SK_RECT,
        [
            Types.Point(x, y),
            Types.Point(x+w, y),
            Types.Point(x+w, y+h),
            Types.Point(x, y+h),
        ],
        stroke,
        fill,
        sw,
        "default",
        "",
    )
end

"""
make_path(pts...; stroke=black, fill=transparent, sw=1.0)

Builds a SK_PATH Shape from a list of (x, y) tuples.
"""
function make_path(
    pts...;
    stroke = Types.Color(0, 0, 0),
    fill = Types.Color(0, 0, 0, 0),
    sw = 1.0,
)
    Types.Shape(
        Types.SK_PATH,
        [Types.Point(x, y) for (x, y) in pts],
        stroke,
        fill,
        sw,
        "default",
        "",
    )
end

"""
make_bezier(p0, p1, p2, p3; stroke=black, fill=transparent, sw=1.0)

Builds a SK_BEZIER Shape from four (x, y) control point tuples.
"""
function make_bezier(
    p0,
    p1,
    p2,
    p3;
    stroke = Types.Color(0, 0, 0),
    fill = Types.Color(0, 0, 0, 0),
    sw = 1.0,
)
    Types.Shape(
        Types.SK_BEZIER,
        [Types.Point(x, y) for (x, y) in (p0, p1, p2, p3)],
        stroke,
        fill,
        sw,
        "default",
        "",
    )
end

# Default renderer instance shared across Suite B tests
const R = SVGRenderer.SVG()


# =============================================================================
# SUITE A — Integration
# =============================================================================

@testset "Suite A — Integration (full pipeline → SVG)" begin

    @testset "1 · SVG document structure" begin

        @testset "output starts with XML declaration" begin
            svg = run("forward 100 px\n")
            @test startswith(svg, "<?xml")
        end

        @testset "output contains SVG root element" begin
            svg = run("forward 100 px\n")
            @test occursin("<svg", svg)
            @test occursin("</svg>", svg)
        end

        @testset "canvas dimensions appear in SVG root" begin
            svg = run("canvas 1024 768\nforward 100 px\n")
            @test occursin("1024", svg)
            @test occursin("768", svg)
        end

        @testset "default canvas is 800×600" begin
            svg = run("forward 100 px\n")
            @test occursin("800", svg)
            @test occursin("600", svg)
        end

        @testset "output contains viewBox attribute" begin
            svg = run("forward 100 px\n")
            @test occursin("viewBox", svg)
        end

    end # document structure


    @testset "2 · Shape elements in SVG output" begin

        @testset "forward produces <line> element" begin
            svg = run("forward 100 px\n")
            @test occursin("<line", svg)
        end

        @testset "circle produces <circle> element" begin
            svg = run("circle 30 px\n")
            @test occursin("<circle", svg)
        end

        @testset "rect produces <rect> element" begin
            svg = run("rect 100 px 50 px\n")
            @test occursin("<rect", svg)
        end

        @testset "penup suppresses shape output" begin
            svg = run("penup\nforward 100 px\n")
            @test !occursin("<line", svg)
        end

    end # shape elements


    @testset "3 · Layers in SVG output" begin

        @testset "default layer produces a <g> element" begin
            svg = run("forward 100 px\n")
            @test occursin("layer-default", svg)
        end

        @testset "named layer appears in output" begin
            svg = run("layer \"background\"\nforward 100 px\n")
            @test occursin("layer-background", svg)
        end

        @testset "named group appears in output" begin
            svg = run("group \"tree\"\nforward 100 px\n")
            @test occursin("group-tree", svg)
        end

    end # layers


    @testset "4 · Style attributes" begin

        @testset "stroke color appears in output" begin
            svg = run("color #FF5733\nforward 100 px\n")
            @test occursin("FF5733", svg)
        end

        @testset "stroke-width appears in output" begin
            svg = run("strokewidth 3 px\nforward 100 px\n")
            @test occursin("stroke-width", svg)
            @test occursin("3", svg)
        end

    end # style

end # Suite A


# =============================================================================
# SUITE B — Unit (SVGRenderer isolated)
# =============================================================================

@testset "Suite B — Unit (SVGRenderer isolated)" begin

    # -------------------------------------------------------------------------
    @testset "1 · SVG document structure" begin

        @testset "XML declaration is present" begin
            svg = SVGRenderer.render_to_string(empty_state())
            @test startswith(svg, "<?xml version=\"1.0\"")
        end

        @testset "SVG root element has correct namespace" begin
            svg = SVGRenderer.render_to_string(empty_state())
            @test occursin("xmlns=\"http://www.w3.org/2000/svg\"", svg)
        end

        @testset "SVG root has Inkscape namespace" begin
            svg = SVGRenderer.render_to_string(empty_state())
            @test occursin("xmlns:inkscape=", svg)
        end

        @testset "canvas width and height in root element" begin
            state = empty_state()
            state.canvas_width = 1280.0
            state.canvas_height = 720.0
            svg = SVGRenderer.render_to_string(state)
            @test occursin("width=\"1280\"", svg)
            @test occursin("height=\"720\"", svg)
        end

        @testset "viewBox matches canvas dimensions" begin
            state = empty_state()
            state.canvas_width = 400.0
            state.canvas_height = 300.0
            svg = SVGRenderer.render_to_string(state)
            @test occursin("viewBox=\"0 0 400 300\"", svg)
        end

        @testset "SVG is closed with </svg>" begin
            svg = SVGRenderer.render_to_string(empty_state())
            @test endswith(strip(svg), "</svg>")
        end

    end # document structure


    # -------------------------------------------------------------------------
    @testset "2 · Shape serialization" begin

        @testset "SK_LINE produces <line> with correct coordinates" begin
            state = state_with_shapes(make_line(0, 0, 100, 0))
            svg = SVGRenderer.render_to_string(state)
            @test occursin("<line", svg)
            @test occursin("x1=\"0\"", svg)
            @test occursin("y1=\"0\"", svg)
            @test occursin("x2=\"100\"", svg)
            @test occursin("y2=\"0\"", svg)
        end

        @testset "SK_CIRCLE produces <circle> with correct cx cy r" begin
            state = state_with_shapes(make_circle(50, 50, 30))
            svg = SVGRenderer.render_to_string(state)
            @test occursin("<circle", svg)
            @test occursin("cx=\"50\"", svg)
            @test occursin("cy=\"50\"", svg)
            @test occursin("r=\"30\"", svg)
        end

        @testset "SK_RECT produces <rect> with correct x y width height" begin
            state = state_with_shapes(make_rect(10, 20, 100, 50))
            svg = SVGRenderer.render_to_string(state)
            @test occursin("<rect", svg)
            @test occursin("x=\"10\"", svg)
            @test occursin("y=\"20\"", svg)
            @test occursin("width=\"100\"", svg)
            @test occursin("height=\"50\"", svg)
        end

        @testset "SK_PATH produces <polyline> with points attribute" begin
            state = state_with_shapes(make_path((0, 0), (50, 50), (100, 0)))
            svg = SVGRenderer.render_to_string(state)
            @test occursin("<polyline", svg)
            @test occursin("points=", svg)
        end

        @testset "SK_BEZIER produces <path> with cubic bezier d attribute" begin
            state = state_with_shapes(make_bezier((0, 0), (25, 50), (75, 50), (100, 0)))
            svg = SVGRenderer.render_to_string(state)
            @test occursin("<path", svg)
            @test occursin(" C ", svg)   # cubic bezier command
        end

        @testset "multiple shapes all appear in output" begin
            state = state_with_shapes(
                make_line(0, 0, 100, 0),
                make_circle(50, 50, 20),
                make_rect(10, 10, 80, 40),
            )
            svg = SVGRenderer.render_to_string(state)
            @test occursin("<line", svg)
            @test occursin("<circle", svg)
            @test occursin("<rect", svg)
        end

    end # shape serialization


    # -------------------------------------------------------------------------
    @testset "3 · Layers and groups" begin

        @testset "default layer produces inkscape layer group" begin
            state = state_with_shapes(make_line(0, 0, 10, 10))
            svg = SVGRenderer.render_to_string(state)
            @test occursin("id=\"layer-default\"", svg)
            @test occursin("inkscape:groupmode=\"layer\"", svg)
        end

        @testset "named layer produces correct id" begin
            state = empty_state()
            layer = Types.Layer("background")
            push!(layer.shapes, make_line(0, 0, 50, 50))
            push!(state.layers, layer)
            svg = SVGRenderer.render_to_string(state)
            @test occursin("id=\"layer-background\"", svg)
        end

        @testset "named group produces <g id='group-NAME'>" begin
            state = empty_state()
            group = Types.Group("tree")
            push!(group.shapes, make_circle(50, 50, 20))
            push!(state.layers[1].groups, group)
            svg = SVGRenderer.render_to_string(state)
            @test occursin("id=\"group-tree\"", svg)
        end

        @testset "invisible layer is skipped" begin
            state = empty_state()
            hidden = Types.Layer("hidden")
            hidden.visible = false
            push!(hidden.shapes, make_line(0, 0, 100, 100))
            push!(state.layers, hidden)
            svg = SVGRenderer.render_to_string(state)
            @test !occursin("layer-hidden", svg)
        end

    end # layers and groups


    # -------------------------------------------------------------------------
    @testset "4 · Style attributes" begin

        @testset "stroke color appears as hex in output" begin
            shape = make_line(0, 0, 100, 0; stroke = Types.Color(255, 0, 0))
            svg = SVGRenderer.render_to_string(state_with_shapes(shape))
            @test occursin("stroke=\"#FF0000\"", svg)
        end

        @testset "transparent stroke renders as none" begin
            shape = make_line(0, 0, 100, 0; stroke = Types.Color(0, 0, 0, 0))
            svg = SVGRenderer.render_to_string(state_with_shapes(shape))
            @test occursin("stroke=\"none\"", svg)
        end

        @testset "fill color appears as hex in output" begin
            shape = make_circle(50, 50, 30; fill = Types.Color(0, 128, 0))
            svg = SVGRenderer.render_to_string(state_with_shapes(shape))
            @test occursin("fill=\"#008000\"", svg)
        end

        @testset "transparent fill renders as none" begin
            shape = make_circle(50, 50, 30; fill = Types.Color(0, 0, 0, 0))
            svg = SVGRenderer.render_to_string(state_with_shapes(shape))
            @test occursin("fill=\"none\"", svg)
        end

        @testset "stroke-width appears in output" begin
            shape = make_line(0, 0, 100, 0; sw = 3.0)
            svg = SVGRenderer.render_to_string(state_with_shapes(shape))
            @test occursin("stroke-width=\"3\"", svg)
        end

    end # style attributes


    # -------------------------------------------------------------------------
    @testset "5 · File output" begin

        @testset "render writes a file to disk" begin
            state = state_with_shapes(make_line(0, 0, 100, 0))
            path = tempname() * ".svg"
            SVGRenderer.render(state, path)
            @test isfile(path)
            rm(path; force = true)
        end

        @testset "file content matches render_to_string" begin
            state = state_with_shapes(make_line(0, 0, 100, 0))
            path = tempname() * ".svg"
            expected = SVGRenderer.render_to_string(state)
            SVGRenderer.render(state, path)
            actual = read(path, String)
            @test actual == expected
            rm(path; force = true)
        end

        @testset "output file is valid UTF-8 text" begin
            state = state_with_shapes(make_circle(50, 50, 20))
            path = tempname() * ".svg"
            SVGRenderer.render(state, path)
            content = read(path, String)
            @test !isempty(content)
            rm(path; force = true)
        end

    end # file output


    # -------------------------------------------------------------------------
    @testset "6 · Edge cases" begin

        @testset "empty state produces valid minimal SVG" begin
            svg = SVGRenderer.render_to_string(empty_state())
            @test occursin("<?xml", svg)
            @test occursin("<svg", svg)
            @test occursin("</svg>", svg)
        end

        @testset "coordinate precision strips trailing zeros" begin
            shape = make_line(0.0, 0.0, 100.0, 0.0)
            svg = SVGRenderer.render_to_string(state_with_shapes(shape))
            # Should be x2="100" not x2="100.0000"
            @test occursin("x2=\"100\"", svg)
            @test !occursin("100.0000", svg)
        end

        @testset "fractional coordinates are rendered with decimals" begin
            shape = make_line(0.0, 0.0, 33.5, 0.0)
            svg = SVGRenderer.render_to_string(state_with_shapes(shape))
            @test occursin("33.5", svg)
        end

    end # edge cases

end # Suite B — Unit


println("\n✓ All Renderer tests passed.\n")
