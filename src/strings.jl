# Unicode string decoding and Shared String Table (SST) parsing for BIFF8.

# Decode a BIFF8 Unicode string starting at `pos` (1-based index into `data`).
# lenlen: 1 or 2 bytes for the character count prefix.
# Returns (string, new_pos).
function unpack_unicode(data::AbstractVector{UInt8}, pos::Int; lenlen::Int=2)
    if lenlen == 2
        nchars = Int(UInt16(data[pos]) | (UInt16(data[pos + 1]) << 8))
        pos += 2
    else
        nchars = Int(data[pos])
        pos += 1
    end

    nchars == 0 && return ("", pos + 1)   # still consume options byte

    options = data[pos]
    pos += 1

    is_utf16 = (options & 0x01) != 0
    has_ext = (options & 0x04) != 0
    has_rich = (options & 0x08) != 0

    nruns = 0
    ext_sz = 0
    if has_rich
        nruns = Int(UInt16(data[pos]) | (UInt16(data[pos + 1]) << 8))
        pos += 2
    end
    if has_ext
        ext_sz = Int(
            UInt32(data[pos]) |
            (UInt32(data[pos + 1]) << 8) |
            (UInt32(data[pos + 2]) << 16) |
            (UInt32(data[pos + 3]) << 24),
        )
        pos += 4
    end

    if is_utf16
        nbytes = nchars * 2
        raw = data[pos:(pos + nbytes - 1)]
        str = transcode(String, reinterpret(UInt16, raw))
        pos += nbytes
    else
        raw = data[pos:(pos + nchars - 1)]
        str = String(map(c -> Char(c), raw))   # Latin-1
        pos += nchars
    end

    pos += nruns * 4   # skip rich-text runs
    pos += ext_sz      # skip phonetic data

    return (str, pos)
end

# A chunk of raw concatenated BIFF data (SST record + its CONTINUEs).
# Parses all unique strings from the SST.
function parse_sst(chunks::Vector{Vector{UInt8}})
    # Concatenate chunks but track record boundaries for options-byte restart.
    # When an SST string crosses a CONTINUE boundary, the first byte of the
    # continuation gives a new options byte (compression flag only, bits 0).
    # We handle this by building a virtual stream that inserts restart markers.

    # Strategy: walk through chunks, building strings one at a time.
    # Each chunk except the first starts fresh and may change the encoding mid-string.

    # First, read header from chunk[1]:
    # offset 0-3: total string references (ignored for indexing)
    # offset 4-7: unique string count
    c1 = chunks[1]
    # total_refs = read UInt32 at 0
    unique_count = Int(
        UInt32(c1[5]) | (UInt32(c1[6]) << 8) | (UInt32(c1[7]) << 16) | (UInt32(c1[8]) << 24)
    )

    strings = Vector{String}(undef, unique_count)

    # Build a flat buffer with boundary info.
    # Each boundary = index (1-based) in the flat buffer where a new options byte starts.
    flat = UInt8[]
    bounds = Set{Int}()   # positions where a CONTINUE options byte appears

    first_data = @view c1[9:end]   # skip 8-byte header
    append!(flat, first_data)

    for i in 2:length(chunks)
        push!(bounds, length(flat) + 1)
        append!(flat, chunks[i])
    end

    pos = 1
    for idx in 1:unique_count
        # Read character count (2 bytes)
        nchars = Int(UInt16(flat[pos]) | (UInt16(flat[pos + 1]) << 8))
        pos += 2

        options = flat[pos]
        pos += 1
        is_utf16 = (options & 0x01) != 0
        has_rich = (options & 0x08) != 0
        has_ext = (options & 0x04) != 0

        nruns = 0
        ext_sz = 0
        if has_rich
            nruns = Int(UInt16(flat[pos]) | (UInt16(flat[pos + 1]) << 8))
            pos += 2
        end
        if has_ext
            ext_sz = Int(
                UInt32(flat[pos]) |
                (UInt32(flat[pos + 1]) << 8) |
                (UInt32(flat[pos + 2]) << 16) |
                (UInt32(flat[pos + 3]) << 24),
            )
            pos += 4
        end

        # Read character data, handling CONTINUE boundaries
        char_buf = UInt8[]
        remaining = nchars
        while remaining > 0
            # Check if we're at a CONTINUE boundary - if so, read new options byte
            if pos in bounds
                new_opts = flat[pos]
                pos += 1
                is_utf16 = (new_opts & 0x01) != 0
            end

            bytes_per_char = is_utf16 ? 2 : 1
            # How many chars can we read before the next boundary?
            next_bound = typemax(Int)
            for b in bounds
                if b > pos
                    next_bound = min(next_bound, b)
                end
            end

            avail_bytes =
                next_bound == typemax(Int) ? remaining * bytes_per_char : next_bound - pos
            chars_avail = avail_bytes ÷ bytes_per_char
            chars_now = min(remaining, chars_avail)
            nbytes_now = chars_now * bytes_per_char

            if is_utf16
                # Append as UTF-8 on the fly
                raw = flat[pos:(pos + nbytes_now - 1)]
                u16 = reinterpret(UInt16, raw)
                for cu in u16
                    c = Char(cu)
                    append!(char_buf, collect(codeunits(string(c))))
                end
            else
                for b in flat[pos:(pos + nbytes_now - 1)]
                    c = Char(b)   # Latin-1: byte value = code point
                    append!(char_buf, collect(codeunits(string(c))))
                end
            end

            pos += nbytes_now
            remaining -= chars_now
        end

        strings[idx] = String(char_buf)
        pos += nruns * 4   # skip rich-text runs
        pos += ext_sz      # skip phonetic data
    end

    return strings
end

# Simple short string for LABEL records (BIFF8): 2-byte length + 1-byte options + chars.
function unpack_label_string(data::AbstractVector{UInt8}, pos::Int)
    nchars = Int(UInt16(data[pos]) | (UInt16(data[pos + 1]) << 8))
    pos += 2
    options = data[pos]
    pos += 1
    is_utf16 = (options & 0x01) != 0
    if is_utf16
        raw = data[pos:(pos + nchars * 2 - 1)]
        return transcode(String, reinterpret(UInt16, raw))
    else
        return String(map(b -> Char(b), data[pos:(pos + nchars - 1)]))
    end
end
