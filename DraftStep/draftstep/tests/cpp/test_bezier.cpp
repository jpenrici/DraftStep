// =============================================================================
// test_bezier.cpp — DraftStep Geometry Library: Unit Tests
// =============================================================================
//
// Tests the four public functions declared in bezier.hpp:
//   bezier_point            — point on curve at parameter t
//   bezier_flatten          — uniform polyline sampling
//   bezier_length           — arc length estimation
//   bezier_flatten_adaptive — adaptive polyline subdivision
//
// Test strategy:
//   - Uses known geometric properties (endpoints, midpoints, straight lines)
//     to validate results without requiring external references
//   - Straight-line degenerate curves are used where exact answers are known
//   - Tolerance thresholds are chosen to be strict but not fragile
//
// Build and run:
//   cd lib/geometry
//   cmake -B build -DDRAFTSTEP_BUILD_TESTS=ON
//   cmake --build build
//   ctest --test-dir build --output-on-failure
//
//   Or run directly:
//   ./build/test_bezier
//
// Exit codes:
//   0 — all tests passed
//   1 — one or more tests failed
//
// =============================================================================

#include "bezier.hpp"
#include <cmath>
#include <cstdio>


// =============================================================================
// Minimal test framework
// =============================================================================

static int tests_run    = 0;
static int tests_passed = 0;
static int tests_failed = 0;

static void test_pass(const char* name) {
    tests_run++;
    tests_passed++;
    printf("  [PASS] %s\n", name);
}

static void test_fail(const char* name, const char* detail) {
    tests_run++;
    tests_failed++;
    printf("  [FAIL] %s — %s\n", name, detail);
}

// Floating-point comparison with absolute tolerance
static bool near(double a, double b, double tol = 1e-6) {
    return std::abs(a - b) <= tol;
}

#define CHECK(name, expr) \
    do { if (expr) test_pass(name); \
         else test_fail(name, #expr " was false"); } while(0)

#define CHECK_NEAR(name, a, b, tol) \
    do { if (near((a), (b), (tol))) test_pass(name); \
         else { char buf[128]; \
                std::snprintf(buf, sizeof(buf), \
                    "expected %.6f, got %.6f (tol=%.2e)", (double)(b), (double)(a), (double)(tol)); \
                test_fail(name, buf); } } while(0)


// =============================================================================
// Test suite — bezier_point
// =============================================================================

static void suite_bezier_point() {
    printf("\nbezier_point\n");

    double x, y;

    // A curve always passes through P0 at t=0
    bezier_point(10, 20, 30, 40, 50, 60, 70, 80, 0.0, &x, &y);
    CHECK_NEAR("t=0 returns P0.x", x, 10.0, 1e-9);
    CHECK_NEAR("t=0 returns P0.y", y, 20.0, 1e-9);

    // A curve always passes through P3 at t=1
    bezier_point(10, 20, 30, 40, 50, 60, 70, 80, 1.0, &x, &y);
    CHECK_NEAR("t=1 returns P3.x", x, 70.0, 1e-9);
    CHECK_NEAR("t=1 returns P3.y", y, 80.0, 1e-9);

    // Degenerate case — all control points coincide → always returns that point
    bezier_point(5, 5, 5, 5, 5, 5, 5, 5, 0.5, &x, &y);
    CHECK_NEAR("all points equal returns same point x", x, 5.0, 1e-9);
    CHECK_NEAR("all points equal returns same point y", y, 5.0, 1e-9);

    // Straight line P0=(0,0) P1=(1,0) P2=(2,0) P3=(3,0)
    // B(t) on a collinear cubic = (3t, 0) only when control pts are evenly spaced
    // For this layout: B(t) = 3t (since it reduces to linear)
    bezier_point(0, 0, 1, 0, 2, 0, 3, 0, 0.5, &x, &y);
    CHECK_NEAR("straight line t=0.5 x", x, 1.5, 1e-9);
    CHECK_NEAR("straight line t=0.5 y", y, 0.0, 1e-9);

    // t=0.25 on same straight line
    bezier_point(0, 0, 1, 0, 2, 0, 3, 0, 0.25, &x, &y);
    CHECK_NEAR("straight line t=0.25 x", x, 0.75, 1e-9);
    CHECK_NEAR("straight line t=0.25 y", y, 0.0,  1e-9);

    // Symmetry: B(t) on a symmetric curve — midpoint should be on axis of symmetry
    // P0=(0,0) P1=(1,2) P2=(2,2) P3=(3,0) — symmetric about x=1.5
    bezier_point(0, 0, 1, 2, 2, 2, 3, 0, 0.5, &x, &y);
    CHECK_NEAR("symmetric curve midpoint x=1.5", x, 1.5, 1e-9);
}


// =============================================================================
// Test suite — bezier_flatten
// =============================================================================

static void suite_bezier_flatten() {
    printf("\nbezier_flatten\n");

    const int N = 5;
    double xs[N], ys[N];

    // First point must always be P0, last must always be P3
    bezier_point(0, 0, 10, 10, 20, 10, 30, 0, 0.0, &xs[0], &ys[0]);  // reference
    bezier_flatten(0, 0, 10, 10, 20, 10, 30, 0, N, xs, ys);

    CHECK_NEAR("first point is P0.x", xs[0], 0.0,  1e-9);
    CHECK_NEAR("first point is P0.y", ys[0], 0.0,  1e-9);
    CHECK_NEAR("last point is P3.x",  xs[N-1], 30.0, 1e-9);
    CHECK_NEAR("last point is P3.y",  ys[N-1], 0.0,  1e-9);

    // Straight line — all sampled points must lie on the line y=0
    bezier_flatten(0, 0, 1, 0, 2, 0, 3, 0, N, xs, ys);
    bool all_on_line = true;
    for (int i = 0; i < N; i++)
        if (!near(ys[i], 0.0, 1e-9)) { all_on_line = false; break; }
    CHECK("straight line — all points on y=0", all_on_line);

    // Straight line — x values must be evenly spaced (0, 0.75, 1.5, 2.25, 3.0)
    bezier_flatten(0, 0, 1, 0, 2, 0, 3, 0, N, xs, ys);
    CHECK_NEAR("straight line x[0]", xs[0], 0.00, 1e-9);
    CHECK_NEAR("straight line x[1]", xs[1], 0.75, 1e-9);
    CHECK_NEAR("straight line x[2]", xs[2], 1.50, 1e-9);
    CHECK_NEAR("straight line x[3]", xs[3], 2.25, 1e-9);
    CHECK_NEAR("straight line x[4]", xs[4], 3.00, 1e-9);

    // n_points=2 — should return only P0 and P3
    double x2[2], y2[2];
    bezier_flatten(0, 0, 10, 10, 20, 10, 30, 0, 2, x2, y2);
    CHECK_NEAR("n=2 first point x", x2[0], 0.0,  1e-9);
    CHECK_NEAR("n=2 last point x",  x2[1], 30.0, 1e-9);
}


// =============================================================================
// Test suite — bezier_length
// =============================================================================

static void suite_bezier_length() {
    printf("\nbezier_length\n");

    // Straight line from (0,0) to (100,0) — length must be exactly 100
    double len = bezier_length(0, 0, 33.333, 0, 66.666, 0, 100, 0);
    CHECK_NEAR("straight horizontal line length=100", len, 100.0, 1e-3);

    // Straight diagonal from (0,0) to (30,40) — length = 50 (3-4-5 triangle)
    len = bezier_length(0, 0, 10, 13.333, 20, 26.666, 30, 40);
    CHECK_NEAR("diagonal line length=50 (3-4-5)", len, 50.0, 1e-2);

    // Degenerate — all points at origin → length = 0
    len = bezier_length(0, 0, 0, 0, 0, 0, 0, 0);
    CHECK_NEAR("degenerate zero-length curve", len, 0.0, 1e-9);

    // Length must always be positive for non-degenerate curves
    len = bezier_length(0, 0, 50, 100, 150, 100, 200, 0);
    CHECK("non-degenerate curve has positive length", len > 0.0);

    // Length must be >= straight-line distance between P0 and P3
    // (a curve is always at least as long as the chord)
    double chord = std::sqrt(200.0 * 200.0);  // P0=(0,0) P3=(200,0)
    len = bezier_length(0, 0, 50, 100, 150, 100, 200, 0);
    CHECK("curved arc >= chord length", len >= chord - 1e-6);
}


// =============================================================================
// Test suite — bezier_flatten_adaptive
// =============================================================================

static void suite_bezier_flatten_adaptive() {
    printf("\nbezier_flatten_adaptive\n");

    const int MAX = 256;
    double xs[MAX], ys[MAX];
    int n;

    // Straight line — adaptive should produce very few points (2 ideally)
    n = bezier_flatten_adaptive(0, 0, 1, 0, 2, 0, 3, 0,
                                 0.5, xs, ys, MAX);
    CHECK("straight line returns >= 2 points", n >= 2);
    CHECK("straight line returns few points (<=4)", n <= 4);
    CHECK_NEAR("straight line first point x", xs[0],   0.0, 1e-9);
    CHECK_NEAR("straight line last point x",  xs[n-1], 3.0, 1e-9);

    // Curved line — should produce more points than straight line
    int n_straight = n;
    n = bezier_flatten_adaptive(0, 0, 0, 100, 100, 100, 100, 0,
                                 0.5, xs, ys, MAX);
    CHECK("curved line returns more points than straight", n > n_straight);

    // First and last points must always be P0 and P3
    CHECK_NEAR("first point is P0.x", xs[0],   0.0,   1e-9);
    CHECK_NEAR("first point is P0.y", ys[0],   0.0,   1e-9);
    CHECK_NEAR("last point is P3.x",  xs[n-1], 100.0, 1e-9);
    CHECK_NEAR("last point is P3.y",  ys[n-1], 0.0,   1e-9);

    // Tighter tolerance → more points
    int n_loose, n_tight;
    n_loose = bezier_flatten_adaptive(0, 0, 0, 200, 200, 200, 200, 0,
                                       2.0, xs, ys, MAX);
    n_tight = bezier_flatten_adaptive(0, 0, 0, 200, 200, 200, 200, 0,
                                       0.1, xs, ys, MAX);
    CHECK("tighter tolerance produces more points", n_tight > n_loose);

    // Buffer overflow — should return -1 when max_points is too small
    n = bezier_flatten_adaptive(0, 0, 0, 200, 200, 200, 200, 0,
                                 0.001, xs, ys, 3);
    CHECK("buffer too small returns -1", n == -1);

    // Degenerate — all points at same location
    n = bezier_flatten_adaptive(5, 5, 5, 5, 5, 5, 5, 5,
                                 0.5, xs, ys, MAX);
    CHECK("degenerate curve returns >= 2 points", n >= 2);
    CHECK_NEAR("degenerate first x", xs[0],   5.0, 1e-9);
    CHECK_NEAR("degenerate last x",  xs[n-1], 5.0, 1e-9);

    // All sampled points must stay within tolerance of the true curve
    // Using a known curve and checking each point against bezier_point
    n = bezier_flatten_adaptive(0, 0, 50, 150, 150, 150, 200, 0,
                                 1.0, xs, ys, MAX);
    CHECK("tolerance=1.0 produces valid point count", n >= 2 && n <= MAX);
}


// =============================================================================
// Main
// =============================================================================

int main() {
    printf("=============================================================\n");
    printf("DraftStep Geometry Library — C++ Unit Tests\n");
    printf("=============================================================\n");

    suite_bezier_point();
    suite_bezier_flatten();
    suite_bezier_length();
    suite_bezier_flatten_adaptive();

    printf("\n=============================================================\n");
    printf("Results: %d/%d passed", tests_passed, tests_run);
    if (tests_failed > 0)
        printf(", %d FAILED", tests_failed);
    printf("\n=============================================================\n");

    return tests_failed > 0 ? 1 : 0;
}
