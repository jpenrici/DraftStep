# DraftStep

> A step-by-step command interpreter for generating vector and bitmap drawings from the CLI.

---

## What is DraftStep?

DraftStep is a CLI tool inspired by Python's Turtle library. It reads plain-text command files (`.draftstep`) and renders them as drawings — currently in SVG, with bitmap support planned for the future.

Each command represents a single drawing step, making it easy to compose complex illustrations from simple, readable instructions.

```
forward 100 px
right 90 deg
circle 30 px
layer "background"
color #FF5733
```

---

## How It Works

```
file.draftstep → [Lexer] → [Parser] → AST → [Interpreter] → [Renderer] → output.svg
```

1. **Lexer** — tokenizes the command file
2. **Parser** — builds an AST from the tokens
3. **Interpreter** — executes the AST, tracking cursor state, layers and groups
4. **Renderer** — emits the final SVG (or bitmap in the future)

---

## Project Structure

```
draftstep/
├── bin/                        # CLI entrypoint
├── src/                        # Julia source modules
│   ├── Types.jl
│   ├── Lexer.jl
│   ├── Parser.jl
│   ├── Interpreter.jl
│   ├── Renderer.jl
│   └── Renderers/
│       ├── SVGRenderer.jl
│       └── BitmapRenderer.jl
├── lib/
│   └── geometry/               # C++ high-performance module (phase 2)
│       ├── bezier.hpp
│       ├── bezier.cpp
│       └── CMakeLists.txt
├── examples/
│   └── hello.draftstep
├── tests/
│   ├── julia/                  # Julia unit tests
│   └── cpp/                    # C++ unit tests
├── tmp/                        # Intermediate files and logs
├── CMakeLists.txt
└── README.md
```

---

## Tech Stack

| Layer | Technology | Role |
|---|---|---|
| Interpreter / Parser | Julia | Core DSL engine |
| High-performance geometry | C++ | Optional module via `ccall` |
| Build system | CMake | Compiles C++ libs, orchestrates build |
| GUI *(planned)* | PySide6 | Desktop interface |

---

## Roadmap

- **Phase 1** — Julia interpreter + SVG renderer *(in progress)*
- **Phase 2** — C++ geometry module (Bézier curves) integrated via `ccall`
- **Phase 3** — Bitmap renderer (PNG output)
- **Phase 4** — PySide6 GUI with live preview

---

## Status

🚧 Early development — architecture defined, implementation in progress.

---

*DraftStep — draft means sketch, step means one command at a time.*