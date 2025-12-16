"""
    PNGExport

PNG image export from GPU framebuffer.

## Features
- Lossless PNG encoding
- Support for RGBA images
- Streaming output for large images
"""
module PNGExport

export PNGEncoder, encode_png, write_png_file, decode_png, read_png_file

# PNG signature
const PNG_SIGNATURE = UInt8[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

# Chunk type codes
const CHUNK_IHDR = UInt8[0x49, 0x48, 0x44, 0x52]
const CHUNK_IDAT = UInt8[0x49, 0x44, 0x41, 0x54]
const CHUNK_IEND = UInt8[0x49, 0x45, 0x4E, 0x44]

"""
    crc32(data::Vector{UInt8}) -> UInt32

Calculate CRC32 checksum for PNG chunks.
"""
function crc32(data::Vector{UInt8})::UInt32
    # CRC32 lookup table
    crc_table = zeros(UInt32, 256)
    for n in 0:255
        c = UInt32(n)
        for _ in 1:8
            if (c & 1) != 0
                c = 0xedb88320 ⊻ (c >> 1)
            else
                c >>= 1
            end
        end
        crc_table[n + 1] = c
    end
    
    crc = 0xffffffff
    for byte in data
        crc = crc_table[(crc ⊻ byte) & 0xff + 1] ⊻ (crc >> 8)
    end
    
    return crc ⊻ 0xffffffff
end

"""
    adler32(data::Vector{UInt8}) -> UInt32

Calculate Adler-32 checksum for zlib.
"""
function adler32(data::Vector{UInt8})::UInt32
    a = UInt32(1)
    b = UInt32(0)
    
    for byte in data
        a = (a + UInt32(byte)) % 65521
        b = (b + a) % 65521
    end
    
    return (b << 16) | a
end

"""
    write_chunk!(io::IOBuffer, chunk_type::Vector{UInt8}, data::Vector{UInt8})

Write a PNG chunk with length, type, data, and CRC.
"""
function write_chunk!(io::IOBuffer, chunk_type::Vector{UInt8}, data::Vector{UInt8})
    # Length (big-endian 4 bytes)
    len = UInt32(length(data))
    len_bytes = reinterpret(UInt8, [hton(len)])
    for b in len_bytes
        write(io, b)
    end
    
    # Type + Data
    for b in chunk_type
        write(io, b)
    end
    for b in data
        write(io, b)
    end
    
    # CRC (of type + data)
    crc_data = vcat(chunk_type, data)
    crc = crc32(crc_data)
    crc_bytes = reinterpret(UInt8, [hton(crc)])
    for b in crc_bytes
        write(io, b)
    end
end

"""
    deflate_store(data::Vector{UInt8}) -> Vector{UInt8}

Simple store-only DEFLATE compression (no actual compression).
This is a minimal implementation for correctness.
"""
function deflate_store(data::Vector{UInt8})::Vector{UInt8}
    output = UInt8[]
    
    # Split into blocks of at most 65535 bytes
    max_block_size = 65535
    pos = 1
    
    while pos <= length(data)
        remaining = length(data) - pos + 1
        block_size = min(remaining, max_block_size)
        is_final = (pos + block_size > length(data))
        
        # Block header: BFINAL (1 bit) + BTYPE (2 bits = 00 for stored)
        push!(output, is_final ? 0x01 : 0x00)
        
        # LEN (2 bytes, little-endian)
        push!(output, UInt8(block_size & 0xff))
        push!(output, UInt8((block_size >> 8) & 0xff))
        
        # NLEN (one's complement of LEN)
        nlen = ~UInt16(block_size)
        push!(output, UInt8(nlen & 0xff))
        push!(output, UInt8((nlen >> 8) & 0xff))
        
        # Data
        for i in 0:(block_size - 1)
            push!(output, data[pos + i])
        end
        
        pos += block_size
    end
    
    return output
end

"""
    zlib_compress(data::Vector{UInt8}) -> Vector{UInt8}

Wrap data in zlib format with store-only deflate.
"""
function zlib_compress(data::Vector{UInt8})::Vector{UInt8}
    output = UInt8[]
    
    # Zlib header
    cmf = 0x78  # Deflate with 32K window
    flg = 0x01  # No preset dictionary, check bits for valid header
    push!(output, cmf)
    push!(output, flg)
    
    # Deflate compressed data
    deflated = deflate_store(data)
    append!(output, deflated)
    
    # Adler-32 checksum (big-endian)
    checksum = adler32(data)
    push!(output, UInt8((checksum >> 24) & 0xff))
    push!(output, UInt8((checksum >> 16) & 0xff))
    push!(output, UInt8((checksum >> 8) & 0xff))
    push!(output, UInt8(checksum & 0xff))
    
    return output
end

"""
    encode_png(framebuffer::Vector{UInt8}, width::UInt32, height::UInt32) -> Vector{UInt8}

Encode RGBA framebuffer to PNG format.
"""
function encode_png(framebuffer::Vector{UInt8}, width::UInt32, height::UInt32)::Vector{UInt8}
    io = IOBuffer()
    
    # PNG signature
    for b in PNG_SIGNATURE
        write(io, b)
    end
    
    # IHDR chunk
    ihdr_data = UInt8[]
    # Width (big-endian)
    append!(ihdr_data, reinterpret(UInt8, [hton(width)]))
    # Height (big-endian)
    append!(ihdr_data, reinterpret(UInt8, [hton(height)]))
    # Bit depth (8)
    push!(ihdr_data, 0x08)
    # Color type (6 = RGBA)
    push!(ihdr_data, 0x06)
    # Compression method (0 = deflate)
    push!(ihdr_data, 0x00)
    # Filter method (0)
    push!(ihdr_data, 0x00)
    # Interlace method (0 = none)
    push!(ihdr_data, 0x00)
    
    write_chunk!(io, CHUNK_IHDR, ihdr_data)
    
    # Prepare filtered image data
    # Add filter byte (0 = None) at start of each row
    filtered = UInt8[]
    bytes_per_row = width * 4
    
    for y in 0:(height - 1)
        push!(filtered, 0x00)  # Filter type: None
        row_start = y * bytes_per_row + 1
        row_end = row_start + bytes_per_row - 1
        if row_end <= length(framebuffer)
            append!(filtered, framebuffer[row_start:row_end])
        else
            # Pad with zeros if framebuffer is too short
            available = max(0, min(Int(bytes_per_row), length(framebuffer) - Int(row_start) + 1))
            if available > 0
                append!(filtered, framebuffer[row_start:row_start + available - 1])
            end
            for _ in available:(Int(bytes_per_row) - 1)
                push!(filtered, 0x00)
            end
        end
    end
    
    # Compress with zlib
    compressed = zlib_compress(filtered)
    
    # IDAT chunk
    write_chunk!(io, CHUNK_IDAT, compressed)
    
    # IEND chunk
    write_chunk!(io, CHUNK_IEND, UInt8[])
    
    return take!(io)
end

"""
    write_png_file(filename::String, framebuffer::Vector{UInt8}, 
                   width::UInt32, height::UInt32)

Write framebuffer to a PNG file.
"""
function write_png_file(filename::String, framebuffer::Vector{UInt8},
                        width::UInt32, height::UInt32)
    png_data = encode_png(framebuffer, width, height)
    open(filename, "w") do file
        write(file, png_data)
    end
end

"""
    PNGEncoder

Stateful PNG encoder for streaming output.
"""
mutable struct PNGEncoder
    width::UInt32
    height::UInt32
    current_row::UInt32
    output::IOBuffer
    header_written::Bool
    
    function PNGEncoder(width::UInt32, height::UInt32)
        new(width, height, UInt32(0), IOBuffer(), false)
    end
end

"""
    begin_encoding!(encoder::PNGEncoder)

Begin PNG encoding (write header).
"""
function begin_encoding!(encoder::PNGEncoder)
    if encoder.header_written
        return
    end
    
    # PNG signature
    for b in PNG_SIGNATURE
        write(encoder.output, b)
    end
    
    # IHDR chunk
    ihdr_data = UInt8[]
    append!(ihdr_data, reinterpret(UInt8, [hton(encoder.width)]))
    append!(ihdr_data, reinterpret(UInt8, [hton(encoder.height)]))
    push!(ihdr_data, 0x08, 0x06, 0x00, 0x00, 0x00)
    
    write_chunk!(encoder.output, CHUNK_IHDR, ihdr_data)
    encoder.header_written = true
end

"""
    finish_encoding!(encoder::PNGEncoder) -> Vector{UInt8}

Finish encoding and return PNG data.
"""
function finish_encoding!(encoder::PNGEncoder)::Vector{UInt8}
    # IEND chunk
    write_chunk!(encoder.output, CHUNK_IEND, UInt8[])
    
    return take!(encoder.output)
end

# ============================================================================
# PNG Decoding (for pixel comparison)
# ============================================================================

"""
    inflate_decompress(data::Vector{UInt8}) -> Vector{UInt8}

Simple DEFLATE decompression (handles store-only blocks).
This is a minimal implementation for our own encoded PNGs.
"""
function inflate_decompress(data::Vector{UInt8})::Vector{UInt8}
    output = UInt8[]
    pos = 1
    
    while pos <= length(data)
        if pos > length(data)
            break
        end
        
        header = data[pos]
        pos += 1
        
        # BFINAL is bit 0, BTYPE is bits 1-2
        is_final = (header & 0x01) != 0
        btype = (header >> 1) & 0x03
        
        if btype == 0
            # Stored block
            if pos + 3 > length(data)
                break
            end
            
            len = UInt16(data[pos]) | (UInt16(data[pos+1]) << 8)
            pos += 4  # Skip LEN and NLEN
            
            for i in 0:(len-1)
                if pos + i > length(data)
                    break
                end
                push!(output, data[pos + i])
            end
            pos += len
        else
            # Dynamic or fixed Huffman - not supported in this minimal decoder
            # Just return what we have so far
            break
        end
        
        if is_final
            break
        end
    end
    
    return output
end

"""
    zlib_decompress(data::Vector{UInt8}) -> Vector{UInt8}

Decompress zlib-wrapped DEFLATE data.
"""
function zlib_decompress(data::Vector{UInt8})::Vector{UInt8}
    if length(data) < 6
        return UInt8[]
    end
    
    # Skip zlib header (2 bytes) and Adler-32 checksum (4 bytes at end)
    compressed = data[3:end-4]
    return inflate_decompress(compressed)
end

"""
    read_png_chunk(io::IO) -> Tuple{Vector{UInt8}, Vector{UInt8}}

Read a PNG chunk from IO, returning (type, data).
"""
function read_png_chunk(io::IO)::Tuple{Vector{UInt8}, Vector{UInt8}}
    # Read length (big-endian)
    len_bytes = read(io, 4)
    if length(len_bytes) < 4
        return (UInt8[], UInt8[])
    end
    len = ntoh(reinterpret(UInt32, len_bytes)[1])
    
    # Read type
    chunk_type = read(io, 4)
    if length(chunk_type) < 4
        return (UInt8[], UInt8[])
    end
    
    # Read data
    data = len > 0 ? read(io, Int(len)) : UInt8[]
    
    # Read CRC (we skip validation for simplicity)
    read(io, 4)
    
    return (chunk_type, data)
end

"""
    decode_png(filename::String) -> Vector{UInt8}

Decode a PNG file to raw RGBA pixel data.

# Returns
Raw RGBA pixel data (4 bytes per pixel).

# Limitations
This is a minimal decoder optimized for PNG files produced by this module's encoder.
It supports:
- 8-bit depth only
- RGBA (color type 6), RGB (color type 2), and Grayscale (color type 0)
- Store-only DEFLATE compression (no Huffman encoding)
- All filter types (None, Sub, Up, Average, Paeth)

For PNG files with Huffman-compressed data (most real-world PNGs), the decoder
will return partial or incorrect results. Use a full PNG library for general PNG decoding.
"""
function decode_png(filename::String)::Vector{UInt8}
    data = read(filename)
    return decode_png_data(data)
end

"""
    decode_png_data(data::Vector{UInt8}) -> Vector{UInt8}

Decode PNG data to raw RGBA pixels.

See `decode_png` for limitations of this minimal decoder.
"""
function decode_png_data(data::Vector{UInt8})::Vector{UInt8}
    io = IOBuffer(data)
    
    # Verify PNG signature
    sig = read(io, 8)
    if length(sig) < 8 || sig != PNG_SIGNATURE
        error("Invalid PNG signature")
    end
    
    width = UInt32(0)
    height = UInt32(0)
    bit_depth = UInt8(0)
    color_type = UInt8(0)
    idat_data = UInt8[]
    
    # Read chunks
    while !eof(io)
        (chunk_type, chunk_data) = read_png_chunk(io)
        
        if isempty(chunk_type)
            break
        end
        
        if chunk_type == CHUNK_IHDR
            # Parse IHDR
            if length(chunk_data) >= 13
                width = ntoh(reinterpret(UInt32, chunk_data[1:4])[1])
                height = ntoh(reinterpret(UInt32, chunk_data[5:8])[1])
                bit_depth = chunk_data[9]
                color_type = chunk_data[10]
            end
        elseif chunk_type == CHUNK_IDAT
            append!(idat_data, chunk_data)
        elseif chunk_type == CHUNK_IEND
            break
        end
    end
    
    if width == 0 || height == 0 || isempty(idat_data)
        return UInt8[]
    end
    
    # Decompress image data
    decompressed = zlib_decompress(idat_data)
    
    # Remove filter bytes and defilter
    bytes_per_pixel = color_type == 6 ? 4 : (color_type == 2 ? 3 : 1)
    bytes_per_row = width * bytes_per_pixel
    expected_filtered_size = height * (bytes_per_row + 1)  # +1 for filter byte
    
    if length(decompressed) < expected_filtered_size
        # Pad if necessary
        resize!(decompressed, expected_filtered_size)
    end
    
    # Unfilter and extract pixel data
    output = UInt8[]
    prev_row = zeros(UInt8, bytes_per_row)
    
    for y in 0:(height-1)
        row_start = y * (bytes_per_row + 1) + 1
        filter_type = decompressed[row_start]
        
        current_row = UInt8[]
        for x in 0:(bytes_per_row-1)
            raw = decompressed[row_start + 1 + x]
            
            # Apply defilter based on filter type
            # 0 = None, 1 = Sub, 2 = Up, 3 = Average, 4 = Paeth
            # 'a' is the pixel bytes_per_pixel positions to the left (at index x + 1 - bytes_per_pixel)
            a = x >= bytes_per_pixel ? current_row[x + 1 - bytes_per_pixel] : UInt8(0)
            b = prev_row[x + 1]
            c = x >= bytes_per_pixel ? prev_row[x + 1 - bytes_per_pixel] : UInt8(0)
            
            if filter_type == 0
                push!(current_row, raw)
            elseif filter_type == 1
                push!(current_row, UInt8((raw + a) & 0xff))
            elseif filter_type == 2
                push!(current_row, UInt8((raw + b) & 0xff))
            elseif filter_type == 3
                push!(current_row, UInt8((raw + (Int(a) + Int(b)) ÷ 2) & 0xff))
            elseif filter_type == 4
                # Paeth predictor
                p = Int(a) + Int(b) - Int(c)
                pa = abs(p - Int(a))
                pb = abs(p - Int(b))
                pc = abs(p - Int(c))
                pr = pa <= pb && pa <= pc ? a : (pb <= pc ? b : c)
                push!(current_row, UInt8((raw + pr) & 0xff))
            else
                push!(current_row, raw)
            end
        end
        
        # Convert to RGBA if needed
        if color_type == 6
            # Already RGBA
            append!(output, current_row)
        elseif color_type == 2
            # RGB -> RGBA
            for x in 0:3:(length(current_row)-3)
                append!(output, current_row[x+1:x+3])
                push!(output, 0xff)
            end
        else
            # Grayscale -> RGBA
            for v in current_row
                push!(output, v, v, v, 0xff)
            end
        end
        
        prev_row = current_row
    end
    
    return output
end

"""
    read_png_file(filename::String) -> Tuple{Vector{UInt8}, UInt32, UInt32}

Read a PNG file and return (pixel_data, width, height).
"""
function read_png_file(filename::String)::Tuple{Vector{UInt8}, UInt32, UInt32}
    data = read(filename)
    io = IOBuffer(data)
    
    # Verify signature
    sig = read(io, 8)
    if sig != PNG_SIGNATURE
        return (UInt8[], UInt32(0), UInt32(0))
    end
    
    # Read IHDR to get dimensions
    (chunk_type, chunk_data) = read_png_chunk(io)
    if chunk_type != CHUNK_IHDR || length(chunk_data) < 8
        return (UInt8[], UInt32(0), UInt32(0))
    end
    
    width = ntoh(reinterpret(UInt32, chunk_data[1:4])[1])
    height = ntoh(reinterpret(UInt32, chunk_data[5:8])[1])
    
    # Decode full image
    pixels = decode_png_data(data)
    
    return (pixels, width, height)
end

end # module PNGExport
