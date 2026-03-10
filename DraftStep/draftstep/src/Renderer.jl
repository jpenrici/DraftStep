# =============================================================================
# Renderer.jl — DraftStep Abstract Renderer Interface
# =============================================================================
#
# Defines the abstract type and the required interface that every concrete
# renderer (SVG, Bitmap, etc.) must implement.
#
# Pipeline position:
#   Interpreter.execute → DrawingState → Renderer.render → output file
#
# To implement a new renderer:
#   1. Create a struct that subtypes AbstractRenderer
#   2. Implement render(renderer, state, path) for that struct
#   3. Optionally implement render_to_string(renderer, state) → String
#
# Usage:
#   include("Types.jl")
#   include("Renderer.jl")
#   include("Renderers/SVGRenderer.jl")
#   SVGRenderer.render(state, "output.svg")
#
# =============================================================================

module Renderer

import ..Types

export AbstractRenderer, render, render_to_string, RendererError


# =============================================================================
# SECTION 1 — Error type
# =============================================================================

"""
RendererError

Raised when a renderer cannot produce its output.

# Fields
- `message::String` : human-readable description of the problem
"""
struct RendererError <: Exception
    message::String
end

Base.showerror(io::IO, e::RendererError) = print(io, "RendererError: $(e.message)")


# =============================================================================
# SECTION 2 — Abstract renderer type
# =============================================================================

"""
AbstractRenderer

Base type for all DraftStep renderers.
Every concrete renderer must subtype `AbstractRenderer`.

# Required interface
Subtypes must implement:

    render(r::MyRenderer, state::DrawingState, path::String)

Optionally implement:

    render_to_string(r::MyRenderer, state::DrawingState) → String
"""
abstract type AbstractRenderer end


# =============================================================================
# SECTION 3 — Interface functions
# =============================================================================

"""
render(renderer, state, path)

Renders `state` to a file at `path` using `renderer`.
Must be implemented by every concrete renderer subtype.

# Raises
- `RendererError` if the output cannot be written.
- `MethodError`   if the subtype does not implement this function.
"""
function render(renderer::AbstractRenderer, state::Types.DrawingState, path::String)
    throw(MethodError(render, (renderer, state, path)))
end


"""
render_to_string(renderer, state) → String

Renders `state` to a string and returns it without writing to disk.
Useful for testing and preview.

Default implementation: calls `render` to a temp file and reads it back.
Concrete renderers may override this for efficiency.
"""
function render_to_string(renderer::AbstractRenderer, state::Types.DrawingState)::String
    tmp = tempname() * renderer_extension(renderer)
    render(renderer, state, tmp)
    result = read(tmp, String)
    rm(tmp; force = true)
    return result
end


"""
renderer_extension(renderer) → String

Returns the file extension (including dot) produced by this renderer.
Used by `render_to_string` to create a correctly named temp file.

Default: ".out" — override in concrete renderers.
"""
renderer_extension(::AbstractRenderer) = ".out"


# =============================================================================
# SECTION 4 — Color helpers shared across renderers
# =============================================================================

"""
color_to_hex(color) → String

Converts a `Color` value to a CSS hex string (`#RRGGBB`).

# Example
    color_to_hex(Color(255, 87, 51))  →  "#FF5733"
"""
function color_to_hex(color::Types.Color)::String
    r = lpad(string(color.r, base = 16), 2, '0')
    g = lpad(string(color.g, base = 16), 2, '0')
    b = lpad(string(color.b, base = 16), 2, '0')
    "#$(uppercase(r))$(uppercase(g))$(uppercase(b))"
end

"""
color_to_rgba(color) → String

Converts a `Color` value to a CSS rgba() string.
Alpha is expressed as a Float64 in [0.0, 1.0].

# Example
    color_to_rgba(Color(0, 0, 0, 128))  →  "rgba(0, 0, 0, 0.502)"
"""
function color_to_rgba(color::Types.Color)::String
    a = round(color.a / 255.0; digits = 3)
    "rgba($(color.r), $(color.g), $(color.b), $a)"
end

"""
color_is_transparent(color) → Bool

Returns `true` if the color alpha channel is zero (fully transparent).
"""
color_is_transparent(color::Types.Color) = color.a == 0

end # module Renderer
