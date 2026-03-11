# =============================================================================
# test_lexer.jl — Unit Tests for Lexer.jl
# =============================================================================
#
# Covers:
#   1. Individual token kinds (commands, numbers, units, strings, colors,
#      comments, newlines, EOF)
#   2. Multi-line programs
#   3. Real-world command sequences
#   4. Edge cases (empty input, blank lines, negative numbers, whitespace)
#   5. Error handling (unknown tokens, bad colors, unterminated strings)
#
# Run from the project root:
#   julia tests/julia/test_lexer.jl
#
# Exit code 0 = all tests passed.
# =============================================================================

using Test

# ---------------------------------------------------------------------------
# Load modules — Types must be included BEFORE Lexer so that Lexer's
# `import ..Types` resolves to the same module instance used in the tests.
# Both share Main.Types — no double-include, no identity mismatch!
# ---------------------------------------------------------------------------
include("../../src/Types.jl")
import .Types

include("../../src/Lexer.jl")
import .Lexer


# =============================================================================
# Helpers
# =============================================================================

"""
kinds(tokens) → Vector{Types.TokenKind}

Extracts only meaningful token kinds — skips TK_EOF, TK_NEWLINE, TK_COMMENT.
Use `kinds_all` when newlines or comments are part of the assertion.
"""
kinds(tokens) =
    [t.kind for t in tokens if t.kind ∉ (Types.TK_EOF, Types.TK_NEWLINE, Types.TK_COMMENT)]

"""
kinds_all(tokens) → Vector{Types.TokenKind}

Extracts all token kinds including TK_NEWLINE and TK_COMMENT, skips only TK_EOF.
"""
kinds_all(tokens) = [t.kind for t in tokens if t.kind != Types.TK_EOF]

"""
values(tokens) → Vector{String}

Extracts token values — skips TK_EOF, TK_NEWLINE, TK_COMMENT.
"""
values(tokens) =
    [t.value for t in tokens if t.kind ∉ (Types.TK_EOF, Types.TK_NEWLINE, Types.TK_COMMENT)]


# =============================================================================
# TEST SUITE
# =============================================================================

@testset "DraftStep Lexer" begin

    # -------------------------------------------------------------------------
    @testset "1 · Single tokens" begin

        @testset "command keyword" begin
            tokens = Lexer.tokenize("forward")
            @test kinds(tokens) == [Types.TK_COMMAND]
            @test values(tokens) == ["forward"]
        end

        @testset "integer number" begin
            tokens = Lexer.tokenize("100")
            @test kinds(tokens) == [Types.TK_NUMBER]
            @test values(tokens) == ["100"]
        end

        @testset "float number" begin
            tokens = Lexer.tokenize("3.14")
            @test kinds(tokens) == [Types.TK_NUMBER]
            @test values(tokens) == ["3.14"]
        end

        @testset "negative number" begin
            tokens = Lexer.tokenize("-42")
            @test kinds(tokens) == [Types.TK_NUMBER]
            @test values(tokens) == ["-42"]
        end

        @testset "unit px" begin
            tokens = Lexer.tokenize("px")
            @test kinds(tokens) == [Types.TK_UNIT]
            @test values(tokens) == ["px"]
        end

        @testset "unit deg" begin
            tokens = Lexer.tokenize("deg")
            @test kinds(tokens) == [Types.TK_UNIT]
        end

        @testset "unit rad" begin
            tokens = Lexer.tokenize("rad")
            @test kinds(tokens) == [Types.TK_UNIT]
        end

        @testset "quoted string" begin
            tokens = Lexer.tokenize("\"background\"")
            @test kinds(tokens) == [Types.TK_STRING]
            @test values(tokens) == ["background"]   # quotes stripped
        end

        @testset "color 8-digit" begin
            tokens = Lexer.tokenize("#FF573380")
            @test kinds(tokens) == [Types.TK_COLOR]
            @test values(tokens) == ["#FF573380"]
        end

        @testset "color 6-digit" begin
            tokens = Lexer.tokenize("#FF5733")
            @test kinds(tokens) == [Types.TK_COLOR]
            @test values(tokens) == ["#FF5733"]
        end

        @testset "color 3-digit shorthand" begin
            tokens = Lexer.tokenize("#F53")
            @test kinds(tokens) == [Types.TK_COLOR]
            @test values(tokens) == ["#F53"]
        end

        @testset "comment line" begin
            tokens = Lexer.tokenize("# this is a comment")
            @test kinds_all(tokens) == [Types.TK_COMMENT]
            @test startswith(tokens[1].value, "#")
        end

        @testset "EOF is always appended" begin
            tokens = Lexer.tokenize("")
            @test tokens[end].kind == Types.TK_EOF
        end

    end # single tokens


    # -------------------------------------------------------------------------
    @testset "2 · Command + arguments" begin

        @testset "forward 100 px" begin
            tokens = Lexer.tokenize("forward 100 px")
            @test kinds(tokens) == [Types.TK_COMMAND, Types.TK_NUMBER, Types.TK_UNIT]
            @test values(tokens) == ["forward", "100", "px"]
        end

        @testset "left 90 deg" begin
            tokens = Lexer.tokenize("left 90 deg")
            @test kinds(tokens) == [Types.TK_COMMAND, Types.TK_NUMBER, Types.TK_UNIT]
            @test values(tokens) == ["left", "90", "deg"]
        end

        @testset "circle 30 px" begin
            tokens = Lexer.tokenize("circle 30 px")
            @test kinds(tokens) == [Types.TK_COMMAND, Types.TK_NUMBER, Types.TK_UNIT]
        end

        @testset "rect 100 px 50 px" begin
            tokens = Lexer.tokenize("rect 100 px 50 px")
            @test kinds(tokens) == [
                Types.TK_COMMAND,
                Types.TK_NUMBER,
                Types.TK_UNIT,
                Types.TK_NUMBER,
                Types.TK_UNIT,
            ]
        end

        @testset "layer string argument" begin
            tokens = Lexer.tokenize("layer \"background\"")
            @test kinds(tokens) == [Types.TK_COMMAND, Types.TK_STRING]
            @test values(tokens) == ["layer", "background"]
        end

        @testset "color hex argument" begin
            tokens = Lexer.tokenize("color #FF5733")
            @test kinds(tokens) == [Types.TK_COMMAND, Types.TK_COLOR]
            @test values(tokens) == ["color", "#FF5733"]
        end

        @testset "color hex argument" begin
            tokens = Lexer.tokenize("color #FF573380")
            @test kinds(tokens) == [Types.TK_COMMAND, Types.TK_COLOR]
            @test values(tokens) == ["color", "#FF573380"]
        end

        @testset "strokewidth float" begin
            tokens = Lexer.tokenize("strokewidth 1.5 px")
            @test kinds(tokens) == [Types.TK_COMMAND, Types.TK_NUMBER, Types.TK_UNIT]
            @test values(tokens) == ["strokewidth", "1.5", "px"]
        end

        @testset "pendown (no arguments)" begin
            tokens = Lexer.tokenize("pendown")
            @test kinds(tokens) == [Types.TK_COMMAND]
            @test values(tokens) == ["pendown"]
        end

    end # command + arguments


    # -------------------------------------------------------------------------
    @testset "3 · Multi-line programs" begin

        @testset "newline tokens are emitted" begin
            src = "forward 100 px\nbackward 50 px\n"
            tokens = Lexer.tokenize(src)
            newlines = filter(t -> t.kind == Types.TK_NEWLINE, tokens)
            @test length(newlines) == 2
        end

        @testset "line numbers are tracked correctly" begin
            src = "forward 100 px\ncircle 30 px\n"
            tokens = Lexer.tokenize(src)

            # "forward" is on line 1
            fwd = findfirst(t -> t.value == "forward", tokens)
            @test tokens[fwd].line == 1

            # "circle" is on line 2
            cir = findfirst(t -> t.value == "circle", tokens)
            @test tokens[cir].line == 2
        end

        @testset "full short program — command count" begin
            src = """
            pendown
            forward 100 px
            left 90 deg
            circle 30 px
            penup
            """
            tokens = Lexer.tokenize(src)
            commands = filter(t -> t.kind == Types.TK_COMMAND, tokens)
            @test length(commands) == 5
        end

    end # multi-line


    # -------------------------------------------------------------------------
    @testset "4 · Comments" begin

        @testset "comment on its own line is tokenized" begin
            src = "# draw a square\nforward 100 px\n"
            tokens = Lexer.tokenize(src)
            @test kinds_all(tokens)[1] == Types.TK_COMMENT
        end

        @testset "comment does not consume the following newline" begin
            src = "# comment\nforward 100 px\n"
            tokens = Lexer.tokenize(src)
            # comment → newline → command (using kinds_all to include all kinds)
            @test kinds_all(tokens)[1] == Types.TK_COMMENT
            @test kinds_all(tokens)[2] == Types.TK_NEWLINE
            @test kinds_all(tokens)[3] == Types.TK_COMMAND
        end

        @testset "hash after command starts a comment token" begin
            src = "forward 100 px # move ahead\n"
            tokens = Lexer.tokenize(src)
            comment_tokens = filter(t -> t.kind == Types.TK_COMMENT, tokens)
            @test length(comment_tokens) == 1
        end

        @testset "comment with no message followed by newline" begin
            src = "#\nforward 100 px\n"
            tokens = Lexer.tokenize(src)
            @test kinds_all(tokens)[1] == Types.TK_COMMENT
            @test kinds_all(tokens)[2] == Types.TK_NEWLINE
            @test kinds_all(tokens)[3] == Types.TK_COMMAND
        end

        @testset "color 6-digit followed by inline comment on same line" begin
            # #FF0000 → TK_COLOR (6 hex digits, valid)
            # # red   → TK_COMMENT (# followed by space, not a hex digit)
            src = "color #FF0000 # red color\n"
            tokens = Lexer.tokenize(src)
            @test kinds(tokens) == [Types.TK_COMMAND, Types.TK_COLOR]
            comment_tokens = filter(t -> t.kind == Types.TK_COMMENT, tokens)
            @test length(comment_tokens) == 1
            @test occursin("red", comment_tokens[1].value)
        end

        @testset "color 8-digit followed by inline comment on same line" begin
            # #FF0000FF → TK_COLOR   (8 hex digits, valid)
            # # red     → TK_COMMENT (# followed by space, not a hex digit)
            src = "color #FF0000FF # red color\n"
            tokens = Lexer.tokenize(src)
            @test kinds(tokens) == [Types.TK_COMMAND, Types.TK_COLOR]
            comment_tokens = filter(t -> t.kind == Types.TK_COMMENT, tokens)
            @test length(comment_tokens) == 1
            @test occursin("red", comment_tokens[1].value)
        end

        @testset "color and comment are distinguished by character after hash" begin
            # standalone color — next char is hex digit
            color_tokens = Lexer.tokenize("#FF5733")
            @test kinds_all(color_tokens) == [Types.TK_COLOR]

            # standalone comment — next char is space
            comment_tokens = Lexer.tokenize("# FF5733")
            @test kinds_all(comment_tokens) == [Types.TK_COMMENT]
        end

    end # comments


    # -------------------------------------------------------------------------
    @testset "5 · Edge cases" begin

        @testset "empty source produces only EOF" begin
            tokens = Lexer.tokenize("")
            @test length(tokens) == 1
            @test tokens[1].kind == Types.TK_EOF
        end

        @testset "whitespace-only source produces only EOF" begin
            tokens = Lexer.tokenize("   \t  ")
            @test length(tokens) == 1
            @test tokens[1].kind == Types.TK_EOF
        end

        @testset "blank lines produce newline tokens" begin
            tokens = Lexer.tokenize("\n\n\n")
            newlines = filter(t -> t.kind == Types.TK_NEWLINE, tokens)
            @test length(newlines) == 3
        end

        @testset "extra spaces between tokens are ignored" begin
            tokens = Lexer.tokenize("forward    100   px")
            @test kinds(tokens) == [Types.TK_COMMAND, Types.TK_NUMBER, Types.TK_UNIT]
        end

        @testset "negative float number" begin
            tokens = Lexer.tokenize("-3.14")
            @test kinds(tokens) == [Types.TK_NUMBER]
            @test values(tokens) == ["-3.14"]
        end

        @testset "lowercase hex color" begin
            tokens = Lexer.tokenize("#ff5733")
            @test kinds(tokens) == [Types.TK_COLOR]
        end

        @testset "uppercase hex color" begin
            tokens = Lexer.tokenize("#FF5733")
            @test kinds(tokens) == [Types.TK_COLOR]
        end

        @testset "canvas command with two numbers" begin
            tokens = Lexer.tokenize("canvas 800 600")
            @test kinds(tokens) == [Types.TK_COMMAND, Types.TK_NUMBER, Types.TK_NUMBER]
        end

    end # edge cases


    # -------------------------------------------------------------------------
    @testset "6 · Error handling" begin

        @testset "unknown bare word raises LexerError" begin
            @test_throws Lexer.LexerError Lexer.tokenize("unknowncommand")
        end

        @testset "invalid color 4-digit raises LexerError" begin
            @test_throws Lexer.LexerError Lexer.tokenize("#ABCD")
        end

        @testset "invalid color 5-digit raises LexerError" begin
            @test_throws Lexer.LexerError Lexer.tokenize("#ABCDE")
        end

        @testset "invalid color 7-digit raises LexerError" begin
            @test_throws Lexer.LexerError Lexer.tokenize("#ABCDEF1")
        end

        @testset "unterminated string raises LexerError" begin
            @test_throws Lexer.LexerError Lexer.tokenize("\"unterminated")
        end

        @testset "unexpected character raises LexerError" begin
            @test_throws Lexer.LexerError Lexer.tokenize("@invalid")
        end

        @testset "LexerError carries correct line number" begin
            src = "forward 100 px\n@bad\n"
            err = nothing
            try
                Lexer.tokenize(src)
            catch e
                err = e
            end
            @test err isa Lexer.LexerError
            @test err.line == 2
        end

    end # error handling

    # -------------------------------------------------------------------------
    @testset "7 · print_tokens" begin

        @testset "prints without error for a normal program" begin
            src = "forward 100 px\ncircle 30 px\n"
            tokens = Lexer.tokenize(src)
            # Should not throw — capture output to avoid polluting test output
            buf = IOBuffer()
            @test_nowarn Lexer.print_tokens(tokens; io = buf)
        end

        @testset "output contains token kind strings" begin
            tokens = Lexer.tokenize("forward 100 px\n")
            buf = IOBuffer()
            Lexer.print_tokens(tokens; io = buf)
            output = String(take!(buf))
            @test occursin("TK_COMMAND", output)
            @test occursin("TK_NUMBER", output)
            @test occursin("TK_UNIT", output)
            @test occursin("TK_NEWLINE", output)
            @test occursin("TK_EOF", output)
        end

        @testset "output contains token values" begin
            tokens = Lexer.tokenize("circle 30 px\n")
            buf = IOBuffer()
            Lexer.print_tokens(tokens; io = buf)
            output = String(take!(buf))
            @test occursin("circle", output)
            @test occursin("30", output)
            @test occursin("px", output)
        end

        @testset "output contains line numbers" begin
            tokens = Lexer.tokenize("forward 100 px\ncircle 30 px\n")
            buf = IOBuffer()
            Lexer.print_tokens(tokens; io = buf)
            output = String(take!(buf))
            @test occursin("1", output)
            @test occursin("2", output)
        end

        @testset "prints empty token list without error" begin
            tokens = Lexer.tokenize("")
            buf = IOBuffer()
            @test_nowarn Lexer.print_tokens(tokens; io = buf)
        end

    end # print_tokens

end # DraftStep Lexer


println("\n✓ All Lexer tests passed.\n")
