"""
    TextJIT

Content-- JIT text shaping for Paragraph nodes.

## Text-Only JIT Strategy
Only Paragraph nodes trigger JIT compilation:
1. State Change: Dynamic Paragraph receives new text
2. Layout Pass: JIT Engine runs HarfBuzz + line-breaking
3. Caching: Results cached by (StringHash, MaxWidth)
4. Output: Paragraph reports height and pre-calculated Render Commands

## Text Primitives
- `Paragraph`: Container for flowing text (JIT target)
- `Span/Link`: Inline text units (generate Shaping Clusters)
- `TextCluster`: Internal primitive - atomic GPU glyph run
"""
module TextJIT

export TextCluster, ShapedParagraph, ParagraphCache, TextShaper
export shape_paragraph!, get_cached_paragraph, invalidate_paragraph
export GlyphRun, GlyphInfo

"""
    GlyphInfo

Information about a single glyph.
"""
struct GlyphInfo
    glyph_id::UInt32      # Font glyph ID
    cluster::UInt32       # Character cluster index
    x_advance::Float32    # Horizontal advance
    y_advance::Float32    # Vertical advance
    x_offset::Float32     # Horizontal offset
    y_offset::Float32     # Vertical offset
end

"""
    GlyphRun

A run of shaped glyphs with consistent styling.
"""
struct GlyphRun
    glyphs::Vector{GlyphInfo}
    font_id::UInt32           # Font atlas ID
    font_size::Float32        # Font size in pixels
    color_r::UInt8
    color_g::UInt8
    color_b::UInt8
    color_a::UInt8
    baseline_y::Float32       # Baseline position
    line_index::UInt32        # Which line this run is on
end

"""
    TextCluster

Internal primitive: atomic GPU command representing a glyph run.
This is the output of the JIT shaper.
"""
struct TextCluster
    # Position in parent
    x::Float32
    y::Float32
    width::Float32
    height::Float32
    
    # Glyph data
    glyph_run::GlyphRun
    
    # Vertex buffer offset for GPU upload
    vertex_offset::UInt32
    vertex_count::UInt32
end

"""
    ShapedParagraph

Result of JIT paragraph shaping.
"""
struct ShapedParagraph
    # Text clusters ready for rendering
    clusters::Vector{TextCluster}
    
    # Computed dimensions
    width::Float32
    height::Float32
    
    # Line metrics
    line_count::UInt32
    line_heights::Vector{Float32}
    
    # Cache key
    text_hash::UInt64
    max_width::Float32
end

"""
    CacheKey

Key for paragraph cache lookup.
"""
struct CacheKey
    text_hash::UInt64
    max_width::Float32
    font_id::UInt32
    font_size::Float32
end

"""
    ParagraphCache

LRU cache for shaped paragraphs.
"""
mutable struct ParagraphCache
    cache::Dict{CacheKey, ShapedParagraph}
    lru_order::Vector{CacheKey}
    max_size::Int
    
    function ParagraphCache(max_size::Int = 1024)
        new(Dict{CacheKey, ShapedParagraph}(), CacheKey[], max_size)
    end
end

"""
    get_cached_paragraph(cache::ParagraphCache, key::CacheKey) -> Union{ShapedParagraph, Nothing}

Look up a shaped paragraph in the cache.
"""
function get_cached_paragraph(cache::ParagraphCache, key::CacheKey)::Union{ShapedParagraph, Nothing}
    if haskey(cache.cache, key)
        # Move to front of LRU
        filter!(k -> k != key, cache.lru_order)
        pushfirst!(cache.lru_order, key)
        return cache.cache[key]
    end
    return nothing
end

"""
    cache_paragraph!(cache::ParagraphCache, key::CacheKey, shaped::ShapedParagraph)

Add a shaped paragraph to the cache.
"""
function cache_paragraph!(cache::ParagraphCache, key::CacheKey, shaped::ShapedParagraph)
    # Evict if at capacity
    while length(cache.lru_order) >= cache.max_size
        evict_key = pop!(cache.lru_order)
        delete!(cache.cache, evict_key)
    end
    
    cache.cache[key] = shaped
    pushfirst!(cache.lru_order, key)
end

"""
    invalidate_paragraph(cache::ParagraphCache, text_hash::UInt64)

Invalidate all cached paragraphs for a given text.
"""
function invalidate_paragraph(cache::ParagraphCache, text_hash::UInt64)
    keys_to_remove = [k for k in keys(cache.cache) if k.text_hash == text_hash]
    for key in keys_to_remove
        delete!(cache.cache, key)
        filter!(k -> k != key, cache.lru_order)
    end
end

"""
    TextShaper

JIT text shaper that processes Paragraph nodes.
"""
mutable struct TextShaper
    cache::ParagraphCache
    default_font_id::UInt32
    default_font_size::Float32
    
    # Glyph metrics lookup (simplified)
    glyph_advances::Dict{Tuple{UInt32, Char}, Float32}
    
    function TextShaper()
        new(
            ParagraphCache(),
            UInt32(1),  # Default font atlas
            16.0f0,     # Default font size
            Dict{Tuple{UInt32, Char}, Float32}()
        )
    end
end

"""
    shape_paragraph!(shaper::TextShaper, text::String, max_width::Float32;
                     font_id::UInt32 = UInt32(0),
                     font_size::Float32 = 0.0f0) -> ShapedParagraph

Shape a paragraph of text (JIT operation).
"""
function shape_paragraph!(shaper::TextShaper, text::String, max_width::Float32;
                          font_id::UInt32 = UInt32(0),
                          font_size::Float32 = 0.0f0)::ShapedParagraph
    # Use defaults if not specified
    if font_id == 0
        font_id = shaper.default_font_id
    end
    if font_size == 0.0f0
        font_size = shaper.default_font_size
    end
    
    text_hash = hash(text)
    key = CacheKey(text_hash, max_width, font_id, font_size)
    
    # Check cache
    cached = get_cached_paragraph(shaper.cache, key)
    if cached !== nothing
        return cached
    end
    
    # Perform shaping (simplified - real implementation would use HarfBuzz)
    shaped = do_shape(shaper, text, max_width, font_id, font_size)
    
    # Cache result
    cache_paragraph!(shaper.cache, key, shaped)
    
    return shaped
end

"""
    do_shape(shaper::TextShaper, text::String, max_width::Float32,
             font_id::UInt32, font_size::Float32) -> ShapedParagraph

Perform actual text shaping (simplified implementation).
Real implementation would use HarfBuzz for proper shaping.
"""
function do_shape(shaper::TextShaper, text::String, max_width::Float32,
                  font_id::UInt32, font_size::Float32)::ShapedParagraph
    clusters = TextCluster[]
    line_heights = Float32[]
    
    # Simplified monospace shaping
    char_width = font_size * 0.6f0
    line_height = font_size * 1.2f0
    
    # Word wrap
    words = split(text)
    current_line = String[]
    current_width = 0.0f0
    lines = String[]
    
    for word in words
        word_width = length(word) * char_width
        space_width = char_width
        
        if current_width + word_width + (isempty(current_line) ? 0.0f0 : space_width) > max_width && !isempty(current_line)
            push!(lines, join(current_line, " "))
            push!(line_heights, line_height)
            current_line = [word]
            current_width = word_width
        else
            if !isempty(current_line)
                current_width += space_width
            end
            push!(current_line, word)
            current_width += word_width
        end
    end
    
    if !isempty(current_line)
        push!(lines, join(current_line, " "))
        push!(line_heights, line_height)
    end
    
    # Create clusters for each line
    y = 0.0f0
    for (line_idx, line) in enumerate(lines)
        glyphs = GlyphInfo[]
        x = 0.0f0
        
        for (char_idx, char) in enumerate(line)
            advance = char_width
            glyph = GlyphInfo(
                UInt32(Int(char)),  # Simplified: use char code as glyph ID
                UInt32(char_idx),
                advance,
                0.0f0,
                0.0f0,
                0.0f0
            )
            push!(glyphs, glyph)
            x += advance
        end
        
        run = GlyphRun(
            glyphs,
            font_id,
            font_size,
            0x00, 0x00, 0x00, 0xff,  # Black text
            y + font_size,  # Baseline
            UInt32(line_idx)
        )
        
        cluster = TextCluster(
            0.0f0, y,
            x, line_height,
            run,
            UInt32(0), UInt32(length(glyphs))
        )
        
        push!(clusters, cluster)
        y += line_height
    end
    
    total_height = isempty(line_heights) ? 0.0f0 : sum(line_heights)
    max_line_width = isempty(clusters) ? 0.0f0 : maximum(c.width for c in clusters)
    
    return ShapedParagraph(
        clusters,
        max_line_width,
        total_height,
        UInt32(length(lines)),
        line_heights,
        hash(text),
        max_width
    )
end

end # module TextJIT
