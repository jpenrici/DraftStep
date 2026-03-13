// =============================================================================
// bezier.cpp — DraftStep Geometry Library: Bézier Curves (Implementation)
// =============================================================================
//
// Implements the four functions declared in bezier.hpp.
// All computations use double precision (64-bit) floating point.
//
// Algorithms:
//   bezier_point            — De Casteljau's algorithm (numerically stable)
//   bezier_flatten          — Uniform sampling via De Casteljau
//   bezier_length           — 16-point Gauss-Legendre quadrature
//   bezier_flatten_adaptive — Recursive midpoint subdivision
//
// No external dependencies — standard C++ only (<cmath>, <cstring>).
//
// Compiled as a shared library by CMakeLists.txt:
//   libgeometry.so    (Linux)
//   libgeometry.dylib (macOS)
//   geometry.dll      (Windows)
//
// =============================================================================

#include "bezier.hpp"
#include <cmath>


// =============================================================================
// Internal helpers
// =============================================================================

/**
 * lerp — linear interpolation between two scalar values.
 */
static inline double lerp(double a, double b, double t) {
    return a + t * (b - a);
}

/**
 * casteljau — evaluates a cubic Bézier at t using De Casteljau's algorithm.
 * Writes results into *out_x and *out_y.
 *
 * De Casteljau is preferred over the expanded polynomial form because it
 * is numerically stable and avoids catastrophic cancellation near t=0 or t=1.
 */
static void casteljau(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y,
    double t,
    double* out_x,
    double* out_y)
{
    // Level 1 — interpolate between adjacent control points
    double q0x = lerp(p0x, p1x, t),  q0y = lerp(p0y, p1y, t);
    double q1x = lerp(p1x, p2x, t),  q1y = lerp(p1y, p2y, t);
    double q2x = lerp(p2x, p3x, t),  q2y = lerp(p2y, p3y, t);

    // Level 2
    double r0x = lerp(q0x, q1x, t),  r0y = lerp(q0y, q1y, t);
    double r1x = lerp(q1x, q2x, t),  r1y = lerp(q1y, q2y, t);

    // Level 3 — final point on curve
    *out_x = lerp(r0x, r1x, t);
    *out_y = lerp(r0y, r1y, t);
}

/**
 * bezier_derivative — computes the first derivative B'(t) of the cubic curve.
 * Used by bezier_length to integrate the speed ||B'(t)||.
 */
static void bezier_derivative(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y,
    double t,
    double* dx,
    double* dy)
{
    // B'(t) = 3[(1-t)²(P1-P0) + 2(1-t)t(P2-P1) + t²(P3-P2)]
    double u  = 1.0 - t;
    double c0 = 3.0 * u * u;
    double c1 = 6.0 * u * t;
    double c2 = 3.0 * t * t;
    *dx = c0 * (p1x - p0x) + c1 * (p2x - p1x) + c2 * (p3x - p2x);
    *dy = c0 * (p1y - p0y) + c1 * (p2y - p1y) + c2 * (p3y - p2y);
}


// =============================================================================
// SECTION 1 — bezier_point
// =============================================================================

void bezier_point(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y,
    double t,
    double* out_x,
    double* out_y)
{
    casteljau(p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y, t, out_x, out_y);
}


// =============================================================================
// SECTION 2 — bezier_flatten (uniform sampling)
// =============================================================================

void bezier_flatten(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y,
    int    n_points,
    double* out_x,
    double* out_y)
{
    if (n_points < 2) return;

    double step = 1.0 / (double)(n_points - 1);
    for (int i = 0; i < n_points; ++i) {
        double t = (i == n_points - 1) ? 1.0 : i * step;
        casteljau(p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y,
                  t, &out_x[i], &out_y[i]);
    }
}


// =============================================================================
// SECTION 3 — bezier_length (Gauss-Legendre quadrature, 16-point)
// =============================================================================

// 16-point Gauss-Legendre nodes and weights on [-1, 1].
// Transformed to [0, 1] inside the integration loop.
// Source: Abramowitz & Stegun, Table 25.4.
static const double GL_NODES[16] = {
    -0.0950125098, 0.0950125098,
    -0.2816035508, 0.2816035508,
    -0.4580167777, 0.4580167777,
    -0.6178762444, 0.6178762444,
    -0.7554044084, 0.7554044084,
    -0.8656312024, 0.8656312024,
    -0.9445750231, 0.9445750231,
    -0.9894009350, 0.9894009350
};

static const double GL_WEIGHTS[16] = {
    0.1894506105, 0.1894506105,
    0.1826034150, 0.1826034150,
    0.1691565194, 0.1691565194,
    0.1495959889, 0.1495959889,
    0.1246289863, 0.1246289863,
    0.0951585117, 0.0951585117,
    0.0622535239, 0.0622535239,
    0.0271524594, 0.0271524594
};

double bezier_length(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y)
{
    // Integrate ||B'(t)|| from 0 to 1 using 16-point Gauss-Legendre.
    // Change of variable: t = (1 + s) / 2, dt = 0.5 ds, s ∈ [-1, 1]
    double sum = 0.0;
    for (int i = 0; i < 16; ++i) {
        double t  = 0.5 * (1.0 + GL_NODES[i]);
        double dx, dy;
        bezier_derivative(p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y,
                          t, &dx, &dy);
        sum += GL_WEIGHTS[i] * std::sqrt(dx * dx + dy * dy);
    }
    return 0.5 * sum;
}


// =============================================================================
// SECTION 4 — bezier_flatten_adaptive (recursive midpoint subdivision)
// =============================================================================

/**
 * subdivide — splits a cubic Bézier at t=0.5 into two sub-curves.
 * Uses De Casteljau at the midpoint.
 *
 * Output: left curve  → l0..l3
 *         right curve → r0..r3
 */
static void subdivide(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y,
    double* l0x, double* l0y,
    double* l1x, double* l1y,
    double* l2x, double* l2y,
    double* l3x, double* l3y,
    double* r0x, double* r0y,
    double* r1x, double* r1y,
    double* r2x, double* r2y,
    double* r3x, double* r3y)
{
    double q0x = (p0x + p1x) * 0.5,  q0y = (p0y + p1y) * 0.5;
    double q1x = (p1x + p2x) * 0.5,  q1y = (p1y + p2y) * 0.5;
    double q2x = (p2x + p3x) * 0.5,  q2y = (p2y + p3y) * 0.5;

    double r0x_ = (q0x + q1x) * 0.5, r0y_ = (q0y + q1y) * 0.5;
    double r1x_ = (q1x + q2x) * 0.5, r1y_ = (q1y + q2y) * 0.5;

    double mx = (r0x_ + r1x_) * 0.5, my = (r0y_ + r1y_) * 0.5;

    *l0x = p0x;  *l0y = p0y;
    *l1x = q0x;  *l1y = q0y;
    *l2x = r0x_; *l2y = r0y_;
    *l3x = mx;   *l3y = my;

    *r0x = mx;   *r0y = my;
    *r1x = r1x_; *r1y = r1y_;
    *r2x = q2x;  *r2y = q2y;
    *r3x = p3x;  *r3y = p3y;
}

/**
 * is_flat — returns true if the curve is flat enough to approximate as a line.
 * Uses the sum of control-point deviations from the chord P0→P3.
 */
static bool is_flat(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y,
    double tolerance)
{
    // Vector along the chord
    double dx = p3x - p0x, dy = p3y - p0y;
    double len2 = dx * dx + dy * dy;

    if (len2 < 1e-10) {
        // Degenerate chord — check distance from P0 directly
        auto d = [](double ax, double ay, double bx, double by) {
            double ex = ax - bx, ey = ay - by;
            return ex * ex + ey * ey;
        };
        return d(p1x, p1y, p0x, p0y) <= tolerance * tolerance &&
               d(p2x, p2y, p0x, p0y) <= tolerance * tolerance;
    }

    // Perpendicular distance of P1 and P2 from the chord
    double cross1 = std::abs((p1x - p0x) * dy - (p1y - p0y) * dx);
    double cross2 = std::abs((p2x - p0x) * dy - (p2y - p0y) * dx);
    double tol_scaled = tolerance * std::sqrt(len2);

    return cross1 <= tol_scaled && cross2 <= tol_scaled;
}

/**
 * flatten_recursive — internal recursive worker for bezier_flatten_adaptive.
 * Appends points to out_x/out_y, tracking count in *n.
 * Does not append the start point (caller's responsibility) — only appends
 * the end point when the segment is flat enough.
 */
static int flatten_recursive(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y,
    double tolerance,
    double* out_x, double* out_y,
    int* n, int max_points,
    int depth)
{
    // Safety depth limit — prevents infinite recursion on degenerate curves
    if (depth > 32 || is_flat(p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y, tolerance)) {
        if (*n >= max_points) return -1;
        out_x[*n] = p3x;
        out_y[*n] = p3y;
        (*n)++;
        return 0;
    }

    double l0x, l0y, l1x, l1y, l2x, l2y, l3x, l3y;
    double r0x, r0y, r1x, r1y, r2x, r2y, r3x, r3y;

    subdivide(p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y,
              &l0x, &l0y, &l1x, &l1y, &l2x, &l2y, &l3x, &l3y,
              &r0x, &r0y, &r1x, &r1y, &r2x, &r2y, &r3x, &r3y);

    if (flatten_recursive(l0x, l0y, l1x, l1y, l2x, l2y, l3x, l3y,
                          tolerance, out_x, out_y, n, max_points, depth + 1) < 0)
        return -1;

    return flatten_recursive(r0x, r0y, r1x, r1y, r2x, r2y, r3x, r3y,
                             tolerance, out_x, out_y, n, max_points, depth + 1);
}

int bezier_flatten_adaptive(
    double p0x, double p0y,
    double p1x, double p1y,
    double p2x, double p2y,
    double p3x, double p3y,
    double  tolerance,
    double* out_x,
    double* out_y,
    int     max_points)
{
    if (max_points < 2) return -1;

    // Always include the start point
    out_x[0] = p0x;
    out_y[0] = p0y;
    int n = 1;

    int result = flatten_recursive(
        p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y,
        tolerance, out_x, out_y, &n, max_points, 0);

    return (result < 0) ? -1 : n;
}
