# =============================================================================
# SVGRenderer.jl — DraftStep SVG Renderer
# =============================================================================
#
# Concrete renderer that converts a DrawingState into a valid SVG 1.1 file.
#
# Pipeline position:
#   DrawingState → SVGRenderer.render → output.svg
#
# SVG structure produced:
#   <svg>
#     <g id="layer-NAME" inkscape:label="NAME">   ← one per Layer
#       <g id="group-NAME">                        ← one per Group
#         <line/> <circle/> <rect/>                ← one per Shape
#       </g>
#       <line/> ...                                ← ungrouped shapes
#     </g>
#   </svg>
#
# Shape mapping:
#   SK_LINE    → <line x1 y1 x2 y2>
#   SK_CIRCLE  → <circle cx cy r>        (points[1]=center, points[2]=radius point)
#   SK_RECT    → <rect x y width height> (points[1]=top-left, points[3]=bottom-right)
#   SK_PATH    → <polyline points="...">
#   SK_BEZIER  → <path d="M C">          (cubic bezier: 4 control points)
#
# Usage:
#   include("src/Types.jl")
#   include("src/Renderer.jl")
#   include("src/Renderers/SVGRenderer.jl")
#   renderer = SVGRenderer.SVG()
#   SVGRenderer.render(renderer, state, "output.svg")
#   # or shorthand:
#   SVGRenderer.render(state, "output.svg")
#
# =============================================================================

module SVGRenderer

import ..Types
import ..Renderer

export SVG, render, render_to_string


# =============================================================================
# SECTION 1 — Renderer struct
# =============================================================================

"""
SVG <: AbstractRenderer

Concrete renderer that produces SVG 1.1 output.

# Fields
- `indent::Int`  : number of spaces per indentation level (default: 2)
- `precision::Int` : decimal places for coordinate values (default: 4)
"""
struct SVG <: Renderer.AbstractRenderer
    indent::Int
    precision::Int
end

SVG() = SVG(2, 4)

Renderer.renderer_extension(::SVG) = ".svg"


# =============================================================================
# SECTION 2 — Color helpers
# =============================================================================

"""
stroke_attr(shape) → String

Returns the SVG stroke attribute string for a shape.
Uses "none" when stroke alpha is zero.
"""
function stroke_attr(shape::Types.Shape)::String
    if Renderer.color_is_transparent(shape.stroke)
        return "none"
    end
    return Renderer.color_to_hex(shape.stroke)
end

"""
fill_attr(shape) → String

Returns the SVG fill attribute string for a shape.
Uses "none" when fill alpha is zero.
"""
function fill_attr(shape::Types.Shape)::String
    if Renderer.color_is_transparent(shape.fill)
        return "none"
    end
    return Renderer.color_to_hex(shape.fill)
end

"""
fmt(r, v) → String

Formats a Float64 coordinate value for SVG output.
Rounds to `r.precision` decimal places and strips trailing zeros
so that 100.0 → "100" and 33.5 → "33.5".
"""
function fmt(r::SVG, v::Real)::String
    v64 = Float64(v)
    rounded = round(v64; digits = r.precision)
    if rounded == floor(rounded)
        return string(Int(floor(rounded)))
    end
    return string(rounded)
end


# =============================================================================
# SECTION 3 — Shape serializers
# Each function returns a single SVG element string (no newline).
# =============================================================================

"""
svg_line(r, shape) → String

Serializes a `SK_LINE` shape to an SVG `<line>` element.
Requires exactly 2 points: start and end.
"""
function svg_line(r::SVG, shape::Types.Shape)::String
    p1, p2 = shape.points[1], shape.points[2]
    stroke = stroke_attr(shape)
    "<line x1=\"$(fmt(r,p1.x))\" y1=\"$(fmt(r,p1.y))\" " *
    "x2=\"$(fmt(r,p2.x))\" y2=\"$(fmt(r,p2.y))\" " *
    "stroke=\"$stroke\" stroke-width=\"$(fmt(r,shape.stroke_width))\" fill=\"none\"/>"
end

"""
svg_circle(r, shape) → String

Serializes a `SK_CIRCLE` shape to an SVG `<circle>` element.
Requires 2 points: center (points[1]) and a radius point (points[2]).
Radius = Euclidean distance between the two points.
"""
function svg_circle(r::SVG, shape::Types.Shape)::String
    center = shape.points[1]
    rpt = shape.points[2]
    radius = sqrt((rpt.x - center.x)^2 + (rpt.y - center.y)^2)
    stroke = stroke_attr(shape)
    fill = fill_attr(shape)
    "<circle cx=\"$(fmt(r,center.x))\" cy=\"$(fmt(r,center.y))\" " *
    "r=\"$(fmt(r,radius))\" " *
    "stroke=\"$stroke\" stroke-width=\"$(fmt(r,shape.stroke_width))\" fill=\"$fill\"/>"
end

"""
svg_rect(r, shape) → String

Serializes a `SK_RECT` shape to an SVG `<rect>` element.
Requires 4 points: top-left, top-right, bottom-right, bottom-left.
Width  = points[2].x - points[1].x
Height = points[4].y - points[1].y
"""
function svg_rect(r::SVG, shape::Types.Shape)::String
    tl = shape.points[1]
    tr = shape.points[2]
    bl = shape.points[4]
    width = tr.x - tl.x
    height = bl.y - tl.y
    stroke = stroke_attr(shape)
    fill = fill_attr(shape)
    "<rect x=\"$(fmt(r,tl.x))\" y=\"$(fmt(r,tl.y))\" " *
    "width=\"$(fmt(r,width))\" height=\"$(fmt(r,height))\" " *
    "stroke=\"$stroke\" stroke-width=\"$(fmt(r,shape.stroke_width))\" fill=\"$fill\"/>"
end

"""
svg_path(r, shape) → String

Serializes a `SK_PATH` shape to an SVG `<polyline>` element.
Accepts any number of points.
"""
function svg_path(r::SVG, shape::Types.Shape)::String
    pts = join(["$(fmt(r,p.x)),$(fmt(r,p.y))" for p in shape.points], " ")
    stroke = stroke_attr(shape)
    fill = fill_attr(shape)
    "<polyline points=\"$pts\" stroke=\"$stroke\" " *
    "stroke-width=\"$(fmt(r,shape.stroke_width))\" fill=\"$fill\"/>"
end

"""
svg_bezier(r, shape) → String

Serializes a `SK_BEZIER` shape to an SVG `<path>` cubic bezier element.
Requires exactly 4 control points: P0 P1 P2 P3.
"""
function svg_bezier(r::SVG, shape::Types.Shape)::String
    p = shape.points
    stroke = stroke_attr(shape)
    fill = fill_attr(shape)
    d =
        "M $(fmt(r,p[1].x)) $(fmt(r,p[1].y)) " *
        "C $(fmt(r,p[2].x)) $(fmt(r,p[2].y)), " *
        "$(fmt(r,p[3].x)) $(fmt(r,p[3].y)), " *
        "$(fmt(r,p[4].x)) $(fmt(r,p[4].y))"
    "<path d=\"$d\" stroke=\"$stroke\" " *
    "stroke-width=\"$(fmt(r,shape.stroke_width))\" fill=\"$fill\"/>"
end

"""
svg_shape(r, shape) → String

Dispatches a `Shape` to the correct serializer based on its `kind`.
Raises `Renderer.RendererError` for unsupported shape kinds.
"""
function svg_shape(r::SVG, shape::Types.Shape)::String
    if shape.kind == Types.SK_LINE
        return svg_line(r, shape)
    elseif shape.kind == Types.SK_CIRCLE
        return svg_circle(r, shape)
    elseif shape.kind == Types.SK_RECT
        return svg_rect(r, shape)
    elseif shape.kind == Types.SK_PATH
        return svg_path(r, shape)
    elseif shape.kind == Types.SK_BEZIER
        return svg_bezier(r, shape)
    else
        throw(Renderer.RendererError("unsupported shape kind: $(shape.kind)"))
    end
end


# =============================================================================
# SECTION 4 — Document builder
# =============================================================================

"""
build_svg(r, state) → String

Builds the complete SVG document string from a `DrawingState`.
"""
function build_svg(r::SVG, state::Types.DrawingState)::String
    pad = " " ^ r.indent
    pad2 = pad ^ 2
    pad3 = pad ^ 3

    lines = String[]

    # --- XML declaration and SVG root ---
    push!(lines, """<?xml version="1.0" encoding="UTF-8"?>""")
    push!(
        lines,
        """<svg xmlns="http://www.w3.org/2000/svg" """ *
        """xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" """ *
        """width="$(fmt(r, state.canvas_width))" """ *
        """height="$(fmt(r, state.canvas_height))" """ *
        """viewBox="0 0 $(fmt(r, state.canvas_width)) $(fmt(r, state.canvas_height))">""",
    )

    # --- Layers (bottom to top) ---
    for layer in state.layers

        # Skip invisible layers
        if !layer.visible
            continue
        end

        # Layer group — Inkscape-compatible attributes
        push!(
            lines,
            """$(pad)<g id="layer-$(layer.name)" """ *
            """inkscape:label="$(layer.name)" """ *
            """inkscape:groupmode="layer">""",
        )

        # Ungrouped shapes directly on the layer
        for shape in layer.shapes
            push!(lines, pad2 * svg_shape(r, shape))
        end

        # Named groups within the layer
        for group in layer.groups
            push!(lines, """$(pad2)<g id="group-$(group.name)">""")
            for shape in group.shapes
                push!(lines, pad3 * svg_shape(r, shape))
            end
            push!(lines, "$(pad2)</g>")
        end

        push!(lines, "$(pad)</g>")
    end

    push!(lines, "</svg>")
    return join(lines, "\n") * "\n"
end


# =============================================================================
# SECTION 5 — Public render interface
# =============================================================================

"""
render(renderer::SVG, state, path)

Renders `state` to an SVG file at `path`.
Creates or overwrites the file.

# Raises
- `Renderer.RendererError` if the file cannot be written.
"""
function Renderer.render(renderer::SVG, state::Types.DrawingState, path::String)
    svg = build_svg(renderer, state)
    try
        open(path, "w") do io
            write(io, svg)
        end
    catch e
        throw(Renderer.RendererError("cannot write to '$path': $e"))
    end
end

"""
render(state, path; renderer=SVG())

Shorthand: renders `state` to `path` using a default `SVG()` renderer.
"""
render(state::Types.DrawingState, path::String; renderer::SVG = SVG()) =
    Renderer.render(renderer, state, path)

"""
render_to_string(renderer::SVG, state) → String

Renders `state` to an SVG string without writing to disk.
Overrides the default temp-file implementation in Renderer.jl.
"""
function Renderer.render_to_string(renderer::SVG, state::Types.DrawingState)::String
    return build_svg(renderer, state)
end

"""
render_to_string(state; renderer=SVG()) → String

Shorthand: renders `state` to an SVG string using a default `SVG()` renderer.
"""
render_to_string(state::Types.DrawingState; renderer::SVG = SVG()) =
    Renderer.render_to_string(renderer, state)

end # module SVGRenderer
