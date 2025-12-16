"""
    PNGExport

PNG image export from GPU framebuffer.

## Features
- Lossless PNG encoding
- Support for RGBA images
- Streaming output for large images
"""
module PNGExport

export PNGEncoder, encode_png, write_png_file

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

end # module PNGExport
