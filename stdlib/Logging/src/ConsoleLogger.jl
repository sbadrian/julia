"""
    ConsoleLogger(stream=STDERR, min_level=Info)

Logger with formatting optimized for readability in a text console, for example
interactive work with the Julia REPL.

Log levels less than `min_level` are filtered out.
"""
struct ConsoleLogger <: AbstractLogger
    stream::IO
    min_level::LogLevel
    message_limits::Dict{Any,Int}
end
ConsoleLogger(stream::IO=STDERR, min_level=Info) = ConsoleLogger(stream, min_level, Dict{Any,Int}())

shouldlog(logger::ConsoleLogger, level, _module, group, id) =
    get(logger.message_limits, id, 1) > 0

min_enabled_level(logger::ConsoleLogger) = logger.min_level

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
    msglines = split(chomp(string(message)), '\n')
    prefixlevel = level >= Warn
    width = displaysize(logger.stream)[2]
    locationstr = string(levelstr, " @ ", _module, " ", basename(filepath), ":", line)
    singlelinewidth = 2 + length(msglines[1]) +
                      (prefixlevel ? length(levelstr) + 2 : 0) +
                      length(locationstr)
    if length(msglines) + length(kwargs) == 1 && singlelinewidth <= width
        print_with_color(color, iob, "[ ", bold=true)
        if prefixlevel
            print_with_color(color, iob, levelstr, ": ", bold=true)
        end
        print(iob, msglines[1])
        print(iob, " "^(width - singlelinewidth))
    else
        print_with_color(color, iob, "┌ ", bold=true)
        if prefixlevel
            print_with_color(color, iob, levelstr, ": ", bold=true)
        end
        println(iob, msglines[1])
        for i in 2:length(msglines)
            print_with_color(color, iob, "│ ", bold=true)
            println(iob, msglines[i])
        end
        for (key,val) in pairs(kwargs)
            print_with_color(color, iob, "│ ", bold=true)
            println(iob, "  ", key, " = ", val)
        end
        print_with_color(color, iob, "└ ", bold=true)
        print(iob, " "^(max(1, width - 1 - 1 - length(locationstr))))
    end
    print_with_color(:light_black, iob, locationstr, bold=false)
    print(iob, "\n")
    write(logger.stream, take!(buf))
    nothing
end

