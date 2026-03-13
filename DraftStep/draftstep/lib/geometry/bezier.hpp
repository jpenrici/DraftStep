// =============================================================================
// bezier.hpp — DraftStep Geometry Library: Bézier Curves
// =============================================================================
//
// Public interface for the DraftStep C++ geometry module.
// Provides cubic Bézier curve evaluation, flattening, and arc-length
// utilities used by the DraftStep rendering pipeline.
//
// This header is the only file Julia needs to know about.
// The implementation lives in bezier.cpp and is compiled into a shared
// library (libgeometry.so / libgeometry.dylib / geometry.dll) via CMake.
//
// Integration with Julia:
//   The functions exported here are called from BezierBridge.jl via ccall:
//
//   ccall((:bezier_point, "libgeometry"), Cvoid,
//         (Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Float64),
//         p0, p1, p2, t)
//
// Naming conventions:
//   - All exported functions use a "bezier_" prefix for namespacing
//   - Coordinates are always passed as separate x/y pairs or as pointer pairs
//   - All floating-point values use double precision (Float64 / double)
//   - Functions returning arrays write into caller-provided output buffers
//     (no heap allocation inside the library — safe for ccall)
//
// Coordinate system:
//   Screen-space: origin at top-left, x grows right, y grows down.
//   Matches the DraftStep canvas convention throughout.
//
// Build:
//   cd lib/geometry && cmake -B build && cmake --build build
//   Output: lib/geometry/build/libgeometry.{so,dylib,dll}
//
// =============================================================================

#pragma once

#ifdef __cplusplus
extern "C" {
#endif


// =============================================================================
// SECTION 1 — Point on curve
// =============================================================================

/**
 * bezier_point
 *
 * Evaluates a cubic Bézier curve at parameter t ∈ [0.0, 1.0].
 * Writes the resulting (x, y) coordinates into the out_x / out_y pointers.
 *
 * The curve is defined by four control points P0, P1, P2, P3:
 *   B(t) = (1-t)³·P0 + 3(1-t)²t·P1 + 3(1-t)t²·P2 + t³·P3
 *
 * Parameters:
 *   p0x, p0y   — anchor start point
 *   p1x, p1y   — control point 1  (influences tangent at P0)
 *   p2x, p2y   — control point 2  (influences tangent at P3)
 *   p3x, p3y   — anchor end point
 *   t          — curve parameter [0.0, 1.0]
 *   out_x      — output: x coordinate of B(t)
 *   out_y      — output: y coordinate of B(t)
 */
void bezier_point(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y,
    double t,
    double* out_x,
    double* out_y
);


// =============================================================================
// SECTION 2 — Curve flattening
// =============================================================================

/**
 * bezier_flatten
 *
 * Approximates a cubic Bézier curve as a polyline by sampling it at
 * `n_points` evenly spaced values of t ∈ [0.0, 1.0].
 *
 * The output is written into two caller-provided arrays:
 *   out_x[i] = x coordinate of sample i
 *   out_y[i] = y coordinate of sample i
 *
 * Both arrays must have capacity for at least `n_points` doubles.
 * The first sample (i=0) corresponds to t=0.0 (P0).
 * The last  sample (i=n_points-1) corresponds to t=1.0 (P3).
 *
 * Parameters:
 *   p0x..p3y   — four control points (same layout as bezier_point)
 *   n_points   — number of samples to generate (minimum: 2)
 *   out_x      — output buffer for x coordinates (size >= n_points)
 *   out_y      — output buffer for y coordinates (size >= n_points)
 *
 * Usage from Julia (BezierBridge.jl):
 *   n = 32
 *   xs = Vector{Float64}(undef, n)
 *   ys = Vector{Float64}(undef, n)
 *   ccall((:bezier_flatten, "libgeometry"), Cvoid,
 *         (Float64, Float64, Float64, Float64,
 *          Float64, Float64, Float64, Float64,
 *          Cint, Ptr{Float64}, Ptr{Float64}),
 *         p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y,
 *         n, xs, ys)
 */
void bezier_flatten(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y,
    int    n_points,
    double* out_x,
    double* out_y
);


// =============================================================================
// SECTION 3 — Arc length
// =============================================================================

/**
 * bezier_length
 *
 * Estimates the arc length of a cubic Bézier curve using adaptive
 * Gauss-Legendre quadrature (16-point rule).
 *
 * Returns the approximate length of the curve from t=0 to t=1.
 * Accuracy is typically better than 0.01% for smooth curves.
 *
 * Parameters:
 *   p0x..p3y   — four control points (same layout as bezier_point)
 *
 * Returns:
 *   Estimated arc length in the same units as the control points (pixels).
 *
 * Usage from Julia:
 *   len = ccall((:bezier_length, "libgeometry"), Float64,
 *               (Float64, Float64, Float64, Float64,
 *                Float64, Float64, Float64, Float64),
 *               p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y)
 */
double bezier_length(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y
);


// =============================================================================
// SECTION 4 — Adaptive flattening
// =============================================================================

/**
 * bezier_flatten_adaptive
 *
 * Flattens a cubic Bézier curve into a polyline using adaptive subdivision.
 * Unlike bezier_flatten (uniform sampling), this function places more samples
 * where the curve has high curvature and fewer where it is nearly straight.
 *
 * The result is a more accurate approximation with fewer points.
 *
 * Parameters:
 *   p0x..p3y    — four control points
 *   tolerance   — maximum allowed deviation from the true curve (in pixels)
 *                 typical values: 0.1 (high quality) to 1.0 (fast/draft)
 *   out_x       — output buffer for x coordinates
 *   out_y       — output buffer for y coordinates
 *   max_points  — capacity of out_x / out_y buffers
 *
 * Returns:
 *   Number of points actually written into out_x / out_y.
 *   Returns -1 if the buffer was too small (increase max_points).
 *
 * Recommended max_points: 256 for tolerance=0.5, canvas up to 2000px wide.
 */
int bezier_flatten_adaptive(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y,
    double  tolerance,
    double* out_x,
    double* out_y,
    int     max_points
);


#ifdef __cplusplus
} // extern "C"
#endif
