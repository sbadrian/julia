# This file is a part of Julia. License is MIT: https://julialang.org/license

"""
    ConsoleLogger(stream=STDERR, min_level=Info; min_level_prefix=Logging.Warn, show_limited=true)

Logger with formatting optimized for readability in a text console, for example
interactive work with the Julia REPL.

Log levels less than `min_level` are filtered out.

Message formatting can be controlled by setting keyword arguments.
`min_level_prefix` controls whether the name of the log level will prefix the
message (for example `@warn "blah"` being formatted as "Warning: blah").  The
printing of large data structures in key value pairs is limited to what can be
reasonably shown on the display when `show_limited=true`, by setting the
`:limit` `IOContext` key during formatting.
"""
struct ConsoleLogger <: AbstractLogger
    stream::IO
    min_level::LogLevel
    min_level_prefix::LogLevel
    show_limited::Bool
    message_limits::Dict{Any,Int}
end
function ConsoleLogger(stream::IO=STDERR, min_level=Info;
                       min_level_prefix=Logging.Warn, show_limited=true)
    ConsoleLogger(stream, min_level, min_level_prefix, show_limited, Dict{Any,Int}())
end

shouldlog(logger::ConsoleLogger, level, _module, group, id) =
    get(logger.message_limits, id, 1) > 0

min_enabled_level(logger::ConsoleLogger) = logger.min_level

# Formatting of values in key value pairs
showvalue(io, msg) = show(io, "text/plain", msg)
function showvalue(io, e::Tuple{Exception,Any})
    ex,bt = e
    showerror(io, ex, bt; backtrace = bt!=nothing)
end
showvalue(io, ex::Exception) = showvalue(io, (ex,catch_backtrace()))

function handle_message(logger::ConsoleLogger, level, message, _module, group, id,
                        filepath, line; maxlog=nothing, kwargs...)
    if maxlog != nothing && maxlog isa Integer
        remaining = get!(logger.message_limits, id, maxlog)
        logger.message_limits[id] = remaining - 1
        remaining > 0 || return
    end
    levelstr = string(level)
    level != Warn || (levelstr = "Warning")
    color = level < Info  ? Base.debug_color() :
            level < Warn  ? Base.info_color() :
            level < Error ? Base.warn_color() :
                            Base.error_color()
    buf = IOBuffer()
    iob = IOContext(buf, logger.stream)
    if logger.show_limited
        iob = IOContext(iob, :limit=>true)
    end
    msglines = split(chomp(string(message)), '\n')
    prefixwithlevel = level >= logger.min_level_prefix
    dsize = displaysize(logger.stream)
    width = dsize[2]
    locationstr = string(levelstr, " @ ", _module, " ", basename(filepath), ":", line)
    singlelinewidth = 2 + length(msglines[1]) +
                      (prefixwithlevel ? length(levelstr) + 2 : 0) +
                      length(locationstr)
    if length(msglines) + length(kwargs) == 1 && singlelinewidth <= width
        print_with_color(color, iob, "[ ", bold=true)
        if prefixwithlevel
            print_with_color(color, iob, levelstr, ": ", bold=true)
        end
        print(iob, msglines[1])
        print(iob, " "^(width - singlelinewidth))
    else
        print_with_color(color, iob, "┌ ", bold=true)
        if prefixwithlevel
            print_with_color(color, iob, levelstr, ": ", bold=true)
        end
        println(iob, msglines[1])
        for i in 2:length(msglines)
            print_with_color(color, iob, "│ ", bold=true)
            println(iob, msglines[i])
        end
        valbuf = IOBuffer()
        valio = IOContext(IOContext(valbuf, iob),
                          :displaysize=>(1 + dsize[1]÷(length(kwargs)+1),dsize[2]-5))
        for (key,val) in pairs(kwargs)
            print_with_color(color, iob, "│ ", bold=true)
            print(iob, "  ", key, " =")
            showvalue(valio, val)
            vallines = split(String(take!(valbuf)), '\n')
            if length(vallines) == 1
                println(iob, " ", vallines[1])
            else
                println(iob)
                for line in vallines
                    print_with_color(color, iob, "│    ", bold=true)
                    println(iob, line)
                end
            end
        end
        print_with_color(color, iob, "└ ", bold=true)
        print(iob, " "^(max(1, width - 1 - 1 - length(locationstr))))
    end
    print_with_color(:light_black, iob, locationstr, bold=false)
    print(iob, "\n")
    write(logger.stream, take!(buf))
    nothing
end

