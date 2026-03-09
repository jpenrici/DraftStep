# =============================================================================
# test_parser.jl — Unit Tests for Parser.jl
# =============================================================================
#
# Covers:
#   1. Single commands — each keyword with correct arguments
#   2. ProgramNode structure — command count, names, arg types
#   3. Multi-command programs
#   4. Comments and blank lines — skipped correctly
#   5. Argument type coercion — NUMBER → Float64, units/strings as String
#   6. Edge cases — empty input, leading/trailing blank lines
#   7. Error handling — wrong args, extra tokens, unknown command
#   8. print_ast — debug output
#
# Run from the project root:
#   julia tests/julia/test_parser.jl
#
# Exit code 0 = all tests passed.
# =============================================================================

using Test

# ---------------------------------------------------------------------------
# Load modules — order matters: Types → Lexer → Parser
# ---------------------------------------------------------------------------
include("../../src/Types.jl")
import .Types

include("../../src/Lexer.jl")
import .Lexer

include("../../src/Parser.jl")
import .Parser


# =============================================================================
# Helper — tokenize + parse in one step
# =============================================================================

"""
compile(source) → ProgramNode

Convenience wrapper: tokenizes and parses a source string in one call.
"""
compile(source::String) = Parser.parse(Lexer.tokenize(source))


# =============================================================================
# TEST SUITE
# =============================================================================

@testset "DraftStep Parser" begin

    # -------------------------------------------------------------------------
    @testset "1 · Single commands" begin

        @testset "forward" begin
            prog = compile("forward 100 px\n")
            @test length(prog.commands) == 1
            cmd = prog.commands[1]
            @test cmd.name == "forward"
            @test cmd.args[1] === 100.0
            @test cmd.args[2] == "px"
        end

        @testset "backward" begin
            prog = compile("backward 50 px\n")
            cmd = prog.commands[1]
            @test cmd.name == "backward"
            @test cmd.args[1] === 50.0
            @test cmd.args[2] == "px"
        end

        @testset "left" begin
            prog = compile("left 90 deg\n")
            cmd = prog.commands[1]
            @test cmd.name == "left"
            @test cmd.args[1] === 90.0
            @test cmd.args[2] == "deg"
        end

        @testset "right" begin
            prog = compile("right 45 deg\n")
            cmd = prog.commands[1]
            @test cmd.name == "right"
            @test cmd.args[1] === 45.0
            @test cmd.args[2] == "deg"
        end

        @testset "pendown (no args)" begin
            prog = compile("pendown\n")
            cmd = prog.commands[1]
            @test cmd.name == "pendown"
            @test isempty(cmd.args)
        end

        @testset "penup (no args)" begin
            prog = compile("penup\n")
            cmd = prog.commands[1]
            @test cmd.name == "penup"
            @test isempty(cmd.args)
        end

        @testset "circle" begin
            prog = compile("circle 30 px\n")
            cmd = prog.commands[1]
            @test cmd.name == "circle"
            @test cmd.args[1] === 30.0
            @test cmd.args[2] == "px"
        end

        @testset "rect (two dimensions)" begin
            prog = compile("rect 100 px 50 px\n")
            cmd = prog.commands[1]
            @test cmd.name == "rect"
            @test cmd.args[1] === 100.0
            @test cmd.args[2] == "px"
            @test cmd.args[3] === 50.0
            @test cmd.args[4] == "px"
        end

        @testset "color" begin
            prog = compile("color #FF5733\n")
            cmd = prog.commands[1]
            @test cmd.name == "color"
            @test cmd.args[1] == "#FF5733"
        end

        @testset "fill" begin
            prog = compile("fill #00FF00\n")
            cmd = prog.commands[1]
            @test cmd.name == "fill"
            @test cmd.args[1] == "#00FF00"
        end

        @testset "strokewidth" begin
            prog = compile("strokewidth 2 px\n")
            cmd = prog.commands[1]
            @test cmd.name == "strokewidth"
            @test cmd.args[1] === 2.0
            @test cmd.args[2] == "px"
        end

        @testset "layer" begin
            prog = compile("layer \"background\"\n")
            cmd = prog.commands[1]
            @test cmd.name == "layer"
            @test cmd.args[1] == "background"
        end

        @testset "group" begin
            prog = compile("group \"tree\"\n")
            cmd = prog.commands[1]
            @test cmd.name == "group"
            @test cmd.args[1] == "tree"
        end

        @testset "canvas" begin
            prog = compile("canvas 800 600\n")
            cmd = prog.commands[1]
            @test cmd.name == "canvas"
            @test cmd.args[1] === 800.0
            @test cmd.args[2] === 600.0
        end

    end # single commands


    # -------------------------------------------------------------------------
    @testset "2 · ProgramNode structure" begin

        @testset "returns a ProgramNode" begin
            prog = compile("forward 100 px\n")
            @test prog isa Types.ProgramNode
        end

        @testset "commands are CommandNodes" begin
            prog = compile("forward 100 px\n")
            @test prog.commands[1] isa Types.CommandNode
        end

        @testset "line number is preserved from source" begin
            prog = compile("forward 100 px\ncircle 30 px\n")
            @test prog.commands[1].line == 1
            @test prog.commands[2].line == 2
        end

        @testset "arg types: NUMBER → Float64, UNIT → String" begin
            prog = compile("forward 100 px\n")
            @test prog.commands[1].args[1] isa Float64
            @test prog.commands[1].args[2] isa String
        end

        @testset "arg types: COLOR → String" begin
            prog = compile("color #FF5733\n")
            @test prog.commands[1].args[1] isa String
        end

        @testset "arg types: STRING → String" begin
            prog = compile("layer \"background\"\n")
            @test prog.commands[1].args[1] isa String
        end

    end # ProgramNode structure


    # -------------------------------------------------------------------------
    @testset "3 · Multi-command programs" begin

        @testset "command count matches source" begin
            src = """
            pendown
            forward 100 px
            left 90 deg
            forward 100 px
            left 90 deg
            penup
            """
            prog = compile(src)
            @test length(prog.commands) == 6
        end

        @testset "command order is preserved" begin
            src = "forward 100 px\nleft 90 deg\ncircle 30 px\n"
            prog = compile(src)
            @test prog.commands[1].name == "forward"
            @test prog.commands[2].name == "left"
            @test prog.commands[3].name == "circle"
        end

        @testset "full square program" begin
            src = """
            pendown
            forward 100 px
            right 90 deg
            forward 100 px
            right 90 deg
            forward 100 px
            right 90 deg
            forward 100 px
            penup
            """
            prog = compile(src)
            @test length(prog.commands) == 9
            @test prog.commands[1].name == "pendown"
            @test prog.commands[end].name == "penup"
        end

    end # multi-command


    # -------------------------------------------------------------------------
    @testset "4 · Comments and blank lines" begin

        @testset "leading comment is skipped" begin
            src = "# draw a square\nforward 100 px\n"
            prog = compile(src)
            @test length(prog.commands) == 1
            @test prog.commands[1].name == "forward"
        end

        @testset "inline comment after command is skipped" begin
            src = "forward 100 px # move ahead\n"
            prog = compile(src)
            @test length(prog.commands) == 1
        end

        @testset "blank lines between commands are skipped" begin
            src = "forward 100 px\n\n\nleft 90 deg\n"
            prog = compile(src)
            @test length(prog.commands) == 2
        end

        @testset "comment between commands is skipped" begin
            src = "forward 100 px\n# turn\nleft 90 deg\n"
            prog = compile(src)
            @test length(prog.commands) == 2
            @test prog.commands[2].name == "left"
        end

        @testset "program with only comments yields zero commands" begin
            src = "# just a comment\n# another comment\n"
            prog = compile(src)
            @test length(prog.commands) == 0
        end

    end # comments and blank lines


    # -------------------------------------------------------------------------
    @testset "5 · Edge cases" begin

        @testset "empty source yields ProgramNode with zero commands" begin
            prog = compile("")
            @test prog isa Types.ProgramNode
            @test length(prog.commands) == 0
        end

        @testset "source with only newlines yields zero commands" begin
            prog = compile("\n\n\n")
            @test length(prog.commands) == 0
        end

        @testset "float number argument is parsed correctly" begin
            prog = compile("strokewidth 1.5 px\n")
            @test prog.commands[1].args[1] === 1.5
        end

        @testset "negative number argument is parsed correctly" begin
            prog = compile("forward -50 px\n")
            @test prog.commands[1].args[1] === -50.0
        end

        @testset "rad unit is accepted" begin
            prog = compile("left 1 rad\n")
            @test prog.commands[1].args[2] == "rad"
        end

        @testset "command without trailing newline (EOF termination)" begin
            # No \n at end — Parser should accept EOF as command terminator
            prog = compile("pendown")
            @test length(prog.commands) == 1
            @test prog.commands[1].name == "pendown"
        end

    end # edge cases


    # -------------------------------------------------------------------------
    @testset "6 · Error handling" begin

        @testset "missing argument raises ParserError" begin
            # forward expects NUMBER UNIT — providing only NUMBER
            @test_throws Parser.ParserError compile("forward 100\n")
        end

        @testset "wrong argument type raises ParserError" begin
            # forward expects NUMBER — providing a STRING
            @test_throws Parser.ParserError compile("forward \"oops\" px\n")
        end

        @testset "extra token after arguments raises ParserError" begin
            # pendown takes no args — extra token should fail
            @test_throws Parser.ParserError compile("pendown 99\n")
        end

        @testset "ParserError carries correct line number" begin
            src = "forward 100 px\nforward \"bad\"\n"
            err = nothing
            try
                compile(src)
            catch e
                err = e
            end
            @test err isa Parser.ParserError
            @test err.line == 2
        end

    end # error handling


    # -------------------------------------------------------------------------
    @testset "7 · print_ast" begin

        @testset "prints without error" begin
            prog = compile("forward 100 px\ncircle 30 px\n")
            buf = IOBuffer()
            @test_nowarn Parser.print_ast(prog; io = buf)
        end

        @testset "output contains command names" begin
            prog = compile("forward 100 px\ncircle 30 px\n")
            buf = IOBuffer()
            Parser.print_ast(prog; io = buf)
            output = String(take!(buf))
            @test occursin("forward", output)
            @test occursin("circle", output)
        end

        @testset "output contains argument values" begin
            prog = compile("forward 100 px\n")
            buf = IOBuffer()
            Parser.print_ast(prog; io = buf)
            output = String(take!(buf))
            @test occursin("100.0", output)
            @test occursin("px", output)
        end

        @testset "output contains line numbers" begin
            prog = compile("forward 100 px\ncircle 30 px\n")
            buf = IOBuffer()
            Parser.print_ast(prog; io = buf)
            output = String(take!(buf))
            @test occursin("1", output)
            @test occursin("2", output)
        end

        @testset "prints empty program without error" begin
            prog = compile("")
            buf = IOBuffer()
            @test_nowarn Parser.print_ast(prog; io = buf)
        end

    end # print_ast

end # DraftStep Parser


println("\n✓ All Parser tests passed.\n")
