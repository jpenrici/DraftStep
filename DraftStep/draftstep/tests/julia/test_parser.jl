# =============================================================================
# test_parser.jl — Unit Tests for Parser.jl
# =============================================================================
#
# Two independent test suites in this file:
#
# Suite A — Integration (coupled)
#   Uses compile(source) which chains Lexer.tokenize → Parser.parse.
#   Validates the full tokenize+parse pipeline end-to-end.
#   A failure here may originate in the Lexer or the Parser.
#
# Suite B — Unit (isolated)
#   Builds Vector{Token} directly — no Lexer involved.
#   Tests only the Parser in isolation.
#   A failure here is guaranteed to be a Parser bug.
#
# Covers:
#   1. Single commands — each keyword with correct arguments
#   2. ProgramNode structure — types, line numbers, arg coercion
#   3. Multi-command programs — count, order
#   4. Comments and blank lines — skipped correctly
#   5. Edge cases — empty input, float/negative args, EOF termination
#   6. Error handling — wrong args, extra tokens
#   7. print_ast — debug output
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

include("../../src/Logger.jl")
import .Logger

include("../../src/Types.jl")
import .Types

include("../../src/Lexer.jl")
import .Lexer

include("../../src/Parser.jl")
import .Parser


# =============================================================================
# Helpers — Suite A
# =============================================================================

"""
    compile(source) → ProgramNode

Tokenizes and parses a DraftStep source string in one call.
Couples Lexer + Parser — used by Suite A only.
"""
compile(source::String) = Parser.parse(Lexer.tokenize(source))


# =============================================================================
# Helpers — Suite B
# =============================================================================

# Token constructors — shortcuts for the most common kinds
tok_cmd(value, line=1)  = Types.Token(Types.TK_COMMAND, value, line)
tok_num(value, line=1)  = Types.Token(Types.TK_NUMBER,  value, line)
tok_unit(value, line=1) = Types.Token(Types.TK_UNIT,    value, line)
tok_str(value, line=1)  = Types.Token(Types.TK_STRING,  value, line)
tok_col(value, line=1)  = Types.Token(Types.TK_COLOR,   value, line)
tok_nl(line=1)          = Types.Token(Types.TK_NEWLINE,  "",   line)
tok_comment(line=1)     = Types.Token(Types.TK_COMMENT, "# comment", line)
tok_eof(line=1)         = Types.Token(Types.TK_EOF,      "",   line)

"""
    tparse(tokens...) → ProgramNode

Parses a manually constructed token sequence.
Always appends TK_EOF automatically.
"""
tparse(tokens...) = Parser.parse([tokens..., tok_eof()])


# =============================================================================
# SUITE A — Integration (Lexer + Parser coupled)
# =============================================================================

@testset "Suite A — Integration (Lexer + Parser)" begin

    # -------------------------------------------------------------------------
    @testset "1 · Single commands" begin

        @testset "forward" begin
            prog = compile("forward 100 px\n")
            cmd  = prog.commands[1]
            @test cmd.name     == "forward"
            @test cmd.args[1] === 100.0
            @test cmd.args[2]  == "px"
        end

        @testset "backward" begin
            prog = compile("backward 50 px\n")
            cmd  = prog.commands[1]
            @test cmd.name     == "backward"
            @test cmd.args[1] === 50.0
        end

        @testset "left" begin
            prog = compile("left 90 deg\n")
            cmd  = prog.commands[1]
            @test cmd.name    == "left"
            @test cmd.args[2] == "deg"
        end

        @testset "right" begin
            prog = compile("right 45 deg\n")
            cmd  = prog.commands[1]
            @test cmd.name     == "right"
            @test cmd.args[1] === 45.0
        end

        @testset "pendown (no args)" begin
            prog = compile("pendown\n")
            cmd  = prog.commands[1]
            @test cmd.name == "pendown"
            @test isempty(cmd.args)
        end

        @testset "penup (no args)" begin
            prog = compile("penup\n")
            @test prog.commands[1].name == "penup"
        end

        @testset "circle" begin
            prog = compile("circle 30 px\n")
            cmd  = prog.commands[1]
            @test cmd.name     == "circle"
            @test cmd.args[1] === 30.0
        end

        @testset "rect (two dimensions)" begin
            prog = compile("rect 100 px 50 px\n")
            cmd  = prog.commands[1]
            @test cmd.name     == "rect"
            @test cmd.args[1] === 100.0
            @test cmd.args[3] === 50.0
        end

        @testset "color" begin
            prog = compile("color #FF5733\n")
            @test prog.commands[1].args[1] == "#FF5733"
        end

        @testset "fill" begin
            prog = compile("fill #00FF00\n")
            @test prog.commands[1].args[1] == "#00FF00"
        end

        @testset "strokewidth" begin
            prog = compile("strokewidth 2 px\n")
            cmd  = prog.commands[1]
            @test cmd.args[1] === 2.0
            @test cmd.args[2]  == "px"
        end

        @testset "layer" begin
            prog = compile("layer \"background\"\n")
            @test prog.commands[1].args[1] == "background"
        end

        @testset "group" begin
            prog = compile("group \"tree\"\n")
            @test prog.commands[1].args[1] == "tree"
        end

        @testset "canvas" begin
            prog = compile("canvas 800 600\n")
            cmd  = prog.commands[1]
            @test cmd.args[1] === 800.0
            @test cmd.args[2] === 600.0
        end

    end # single commands


    # -------------------------------------------------------------------------
    @testset "2 · ProgramNode structure" begin

        @testset "returns a ProgramNode" begin
            @test compile("forward 100 px\n") isa Types.ProgramNode
        end

        @testset "commands are CommandNodes" begin
            prog = compile("forward 100 px\n")
            @test prog.commands[1] isa Types.CommandNode
        end

        @testset "line numbers are preserved" begin
            prog = compile("forward 100 px\ncircle 30 px\n")
            @test prog.commands[1].line == 1
            @test prog.commands[2].line == 2
        end

        @testset "NUMBER args coerced to Float64" begin
            @test compile("forward 100 px\n").commands[1].args[1] isa Float64
        end

        @testset "UNIT args remain String" begin
            @test compile("forward 100 px\n").commands[1].args[2] isa String
        end

        @testset "COLOR args remain String" begin
            @test compile("color #FF5733\n").commands[1].args[1] isa String
        end

        @testset "STRING args have quotes stripped" begin
            @test compile("layer \"bg\"\n").commands[1].args[1] isa String
        end

    end # ProgramNode structure


    # -------------------------------------------------------------------------
    @testset "3 · Multi-command programs" begin

        @testset "command count matches source" begin
            src = "pendown\nforward 100 px\nleft 90 deg\nforward 100 px\nleft 90 deg\npenup\n"
            @test length(compile(src).commands) == 6
        end

        @testset "command order is preserved" begin
            prog = compile("forward 100 px\nleft 90 deg\ncircle 30 px\n")
            @test prog.commands[1].name == "forward"
            @test prog.commands[2].name == "left"
            @test prog.commands[3].name == "circle"
        end

    end # multi-command


    # -------------------------------------------------------------------------
    @testset "4 · Comments and blank lines" begin

        @testset "leading comment is skipped" begin
            prog = compile("# draw\nforward 100 px\n")
            @test length(prog.commands) == 1
            @test prog.commands[1].name == "forward"
        end

        @testset "inline comment after command is skipped" begin
            prog = compile("forward 100 px # move ahead\n")
            @test length(prog.commands) == 1
        end

        @testset "blank lines between commands are skipped" begin
            prog = compile("forward 100 px\n\n\nleft 90 deg\n")
            @test length(prog.commands) == 2
        end

        @testset "only comments yields zero commands" begin
            prog = compile("# just a comment\n# another\n")
            @test length(prog.commands) == 0
        end

    end # comments


    # -------------------------------------------------------------------------
    @testset "5 · Edge cases" begin

        @testset "empty source yields zero commands" begin
            prog = compile("")
            @test prog isa Types.ProgramNode
            @test length(prog.commands) == 0
        end

        @testset "only newlines yields zero commands" begin
            @test length(compile("\n\n\n").commands) == 0
        end

        @testset "float argument" begin
            @test compile("strokewidth 1.5 px\n").commands[1].args[1] === 1.5
        end

        @testset "negative argument" begin
            @test compile("forward -50 px\n").commands[1].args[1] === -50.0
        end

        @testset "rad unit is accepted" begin
            @test compile("left 1 rad\n").commands[1].args[2] == "rad"
        end

        @testset "EOF without trailing newline" begin
            prog = compile("pendown")
            @test length(prog.commands) == 1
            @test prog.commands[1].name == "pendown"
        end

    end # edge cases


    # -------------------------------------------------------------------------
    @testset "6 · Error handling" begin

        @testset "missing argument raises ParserError" begin
            @test_throws Parser.ParserError compile("forward 100\n")
        end

        @testset "wrong argument type raises ParserError" begin
            @test_throws Parser.ParserError compile("forward \"oops\" px\n")
        end

        @testset "extra token after args raises ParserError" begin
            @test_throws Parser.ParserError compile("pendown 99\n")
        end

        @testset "ParserError carries correct line number" begin
            err = nothing
            try
                compile("forward 100 px\nforward \"bad\"\n")
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
            buf = IOBuffer()
            @test_nowarn Parser.print_ast(compile("forward 100 px\n"); io=buf)
        end

        @testset "output contains command names" begin
            buf = IOBuffer()
            Parser.print_ast(compile("forward 100 px\ncircle 30 px\n"); io=buf)
            out = String(take!(buf))
            @test occursin("forward", out)
            @test occursin("circle",  out)
        end

        @testset "output contains argument values" begin
            buf = IOBuffer()
            Parser.print_ast(compile("forward 100 px\n"); io=buf)
            out = String(take!(buf))
            @test occursin("100.0", out)
            @test occursin("px",    out)
        end

    end # print_ast

end # Suite A


# =============================================================================
# SUITE B — Unit (Parser isolated, tokens built directly)
# =============================================================================

@testset "Suite B — Unit (Parser isolated)" begin

    # -------------------------------------------------------------------------
    @testset "1 · Single commands" begin

        @testset "forward — tokens → CommandNode" begin
            prog = tparse(
                tok_cmd("forward"), tok_num("100"), tok_unit("px"), tok_nl())
            cmd = prog.commands[1]
            @test cmd.name     == "forward"
            @test cmd.args[1] === 100.0
            @test cmd.args[2]  == "px"
        end

        @testset "backward" begin
            prog = tparse(
                tok_cmd("backward"), tok_num("50"), tok_unit("px"), tok_nl())
            @test prog.commands[1].args[1] === 50.0
        end

        @testset "left with deg unit" begin
            prog = tparse(
                tok_cmd("left"), tok_num("90"), tok_unit("deg"), tok_nl())
            cmd = prog.commands[1]
            @test cmd.args[1] === 90.0
            @test cmd.args[2]  == "deg"
        end

        @testset "right with rad unit" begin
            prog = tparse(
                tok_cmd("right"), tok_num("1"), tok_unit("rad"), tok_nl())
            @test prog.commands[1].args[2] == "rad"
        end

        @testset "pendown (no args)" begin
            prog = tparse(tok_cmd("pendown"), tok_nl())
            @test isempty(prog.commands[1].args)
        end

        @testset "penup (no args)" begin
            prog = tparse(tok_cmd("penup"), tok_nl())
            @test isempty(prog.commands[1].args)
        end

        @testset "circle" begin
            prog = tparse(
                tok_cmd("circle"), tok_num("30"), tok_unit("px"), tok_nl())
            @test prog.commands[1].args[1] === 30.0
        end

        @testset "rect (two dimensions)" begin
            prog = tparse(
                tok_cmd("rect"),
                tok_num("100"), tok_unit("px"),
                tok_num("50"),  tok_unit("px"),
                tok_nl())
            cmd = prog.commands[1]
            @test cmd.args[1] === 100.0
            @test cmd.args[3] === 50.0
        end

        @testset "color" begin
            prog = tparse(tok_cmd("color"), tok_col("#FF5733"), tok_nl())
            @test prog.commands[1].args[1] == "#FF5733"
        end

        @testset "fill" begin
            prog = tparse(tok_cmd("fill"), tok_col("#00FF00"), tok_nl())
            @test prog.commands[1].args[1] == "#00FF00"
        end

        @testset "strokewidth" begin
            prog = tparse(
                tok_cmd("strokewidth"), tok_num("2"), tok_unit("px"), tok_nl())
            @test prog.commands[1].args[1] === 2.0
        end

        @testset "layer" begin
            prog = tparse(tok_cmd("layer"), tok_str("background"), tok_nl())
            @test prog.commands[1].args[1] == "background"
        end

        @testset "group" begin
            prog = tparse(tok_cmd("group"), tok_str("tree"), tok_nl())
            @test prog.commands[1].args[1] == "tree"
        end

        @testset "canvas (two numbers, no units)" begin
            prog = tparse(
                tok_cmd("canvas"), tok_num("800"), tok_num("600"), tok_nl())
            cmd = prog.commands[1]
            @test cmd.args[1] === 800.0
            @test cmd.args[2] === 600.0
        end

    end # single commands


    # -------------------------------------------------------------------------
    @testset "2 · ProgramNode structure" begin

        @testset "returns ProgramNode" begin
            @test tparse(tok_eof()) isa Types.ProgramNode
        end

        @testset "commands are CommandNodes" begin
            prog = tparse(tok_cmd("pendown"), tok_nl())
            @test prog.commands[1] isa Types.CommandNode
        end

        @testset "line number comes from the command token" begin
            prog = tparse(
                tok_cmd("forward", 7),
                tok_num("100"), tok_unit("px"), tok_nl(7))
            @test prog.commands[1].line == 7
        end

        @testset "NUMBER token coerced to Float64" begin
            prog = tparse(
                tok_cmd("forward"), tok_num("42"), tok_unit("px"), tok_nl())
            @test prog.commands[1].args[1] isa Float64
            @test prog.commands[1].args[1] === 42.0
        end

        @testset "float string in NUMBER token" begin
            prog = tparse(
                tok_cmd("strokewidth"), tok_num("1.5"), tok_unit("px"), tok_nl())
            @test prog.commands[1].args[1] === 1.5
        end

        @testset "negative number string in NUMBER token" begin
            prog = tparse(
                tok_cmd("forward"), tok_num("-50"), tok_unit("px"), tok_nl())
            @test prog.commands[1].args[1] === -50.0
        end

    end # ProgramNode structure


    # -------------------------------------------------------------------------
    @testset "3 · Blank lines and comments between commands" begin

        @testset "TK_NEWLINE between commands is skipped" begin
            prog = tparse(
                tok_cmd("pendown"), tok_nl(),
                tok_nl(),                          # blank line
                tok_cmd("penup"), tok_nl())
            @test length(prog.commands) == 2
        end

        @testset "TK_COMMENT between commands is skipped" begin
            prog = tparse(
                tok_cmd("pendown"), tok_nl(),
                tok_comment(), tok_nl(),            # comment line
                tok_cmd("penup"), tok_nl())
            @test length(prog.commands) == 2
        end

        @testset "inline TK_COMMENT after args is skipped" begin
            prog = tparse(
                tok_cmd("forward"), tok_num("100"), tok_unit("px"),
                tok_comment(),                      # inline comment
                tok_nl())
            @test length(prog.commands) == 1
            @test prog.commands[1].name == "forward"
        end

    end # blank lines and comments


    # -------------------------------------------------------------------------
    @testset "4 · Multi-command token sequences" begin

        @testset "two commands produce two CommandNodes" begin
            prog = tparse(
                tok_cmd("pendown"), tok_nl(),
                tok_cmd("forward"), tok_num("100"), tok_unit("px"), tok_nl())
            @test length(prog.commands) == 2
            @test prog.commands[1].name == "pendown"
            @test prog.commands[2].name == "forward"
        end

        @testset "command order is preserved" begin
            prog = tparse(
                tok_cmd("forward"), tok_num("100"), tok_unit("px"), tok_nl(),
                tok_cmd("left"),    tok_num("90"),  tok_unit("deg"), tok_nl(),
                tok_cmd("circle"),  tok_num("30"),  tok_unit("px"),  tok_nl())
            names = [c.name for c in prog.commands]
            @test names == ["forward", "left", "circle"]
        end

    end # multi-command


    # -------------------------------------------------------------------------
    @testset "5 · Error handling" begin

        @testset "missing UNIT after NUMBER raises ParserError" begin
            @test_throws Parser.ParserError tparse(
                tok_cmd("forward"), tok_num("100"), tok_nl())
        end

        @testset "wrong token kind for NUMBER slot raises ParserError" begin
            @test_throws Parser.ParserError tparse(
                tok_cmd("forward"), tok_str("oops"), tok_unit("px"), tok_nl())
        end

        @testset "extra token after zero-arg command raises ParserError" begin
            @test_throws Parser.ParserError tparse(
                tok_cmd("pendown"), tok_num("99"), tok_nl())
        end

        @testset "ParserError line number matches command token line" begin
            err = nothing
            try
                tparse(
                    tok_cmd("pendown", 1), tok_nl(1),
                    tok_cmd("forward", 3),
                    tok_str("bad", 3), tok_unit("px", 3), tok_nl(3))
            catch e
                err = e
            end
            @test err isa Parser.ParserError
            @test err.line == 3
        end

    end # error handling

end # Suite B — Unit


println("\n✓ All Parser tests passed.\n")
