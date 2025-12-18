module ApplicationUtils

"""
Utilities for example applications and small helpers that are convenient
across multiple example scripts. This module is included into the
`DOPBrowser` top-level module via `include("Application/Utils.jl")` so
it's available as `DOPBrowser.ApplicationUtils`.
"""

export CountingLogger, parse_hex_color, point_in_rect, get_button_rect

using Logging

# ---------------------------------------------------------------------------
# Counting logger
# ---------------------------------------------------------------------------

struct CountingLogger <: AbstractLogger
    dest::AbstractLogger
    count::Base.RefValue{Int}
end

Logging.min_enabled_level(cl::CountingLogger) = Logging.min_enabled_level(cl.dest)

Logging.shouldlog(cl::CountingLogger, level, _module, group, id) =
    Logging.shouldlog(cl.dest, level, _module, group, id)

function Logging.handle_message(cl::CountingLogger, level, message, _module, group, id, file, line; kwargs...)
    try
        if level === Logging.Warn
            cl.count[] += 1
        end
    catch
        # be robust: don't let counting break logging
    end
    return Logging.handle_message(cl.dest, level, message, _module, group, id, file, line; kwargs...)
end

# ---------------------------------------------------------------------------
# Small geometry / color helpers
# ---------------------------------------------------------------------------

"""Parse a 6-digit hex color string ("#RRGGBB") into RGB floats (0-1).

Returns a tuple (r,g,b) as Float64.
"""
function parse_hex_color(hex::String)::Tuple{Float64,Float64,Float64}
    hex = lstrip(hex, '#')
    if length(hex) >= 6
        r = parse(Int, hex[1:2], base=16) / 255.0
        g = parse(Int, hex[3:4], base=16) / 255.0
        b = parse(Int, hex[5:6], base=16) / 255.0
        return (r, g, b)
    end
    return (0.0, 0.0, 0.0)
end

"""Return true when the point (x,y) lies inside the rectangle defined by
`rect_x, rect_y, rect_w, rect_h`.

This is a lightweight helper used in examples to hit-test simple UI regions.
"""
function point_in_rect(x::Real, y::Real, rect_x::Real, rect_y::Real, rect_w::Real, rect_h::Real)::Bool
    return x >= rect_x && x <= rect_x + rect_w && y >= rect_y && y <= rect_y + rect_h
end

"""Compute a simple "Add" button rectangle for the memo example.

This helper provides a default placement for the Add button given the
number of memos and layout width. The calculation is intentionally simple
and tailored for the example app layout.
"""
function get_button_rect(num_memos::Int; x_margin::Float64=20.0, width::Int=400)
    content_width = Float64(width - 2 * x_margin)
    y_pos = 55.0  # After title

    for i in 1:num_memos
        # Approximate card height (60 + 20 per content line, assuming some average)
        y_pos += 120.0 + 10.0  # card height + gap
    end

    return (x_margin, y_pos, content_width, 40.0)
end

end # module ApplicationUtils
