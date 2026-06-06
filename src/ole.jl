# OLE2 Compound Document File Format reader.
# Extracts named streams from Microsoft's Compound Binary File format (.xls, .doc, etc.)

const OLE_MAGIC = UInt8[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]

# Sector ID sentinels (stored as signed 32-bit)
const FREESID = Int32(-1)   # 0xFFFFFFFF - free sector
const EOCSID = Int32(-2)   # 0xFFFFFFFE - end of chain
const SATSID = Int32(-3)   # 0xFFFFFFFD - FAT sector marker
const MSATSID = Int32(-4)   # 0xFFFFFFFC - DIFAT sector marker

struct OLEDirEntry
    name::String
    entry_type::UInt8   # 0=empty, 1=storage, 2=stream, 5=root
    left::Int32
    right::Int32
    child::Int32
    start::Int32        # first sector (or mini-sector)
    size::Int32
    OLEDirEntry(name::String, entry_type::UInt8, left::Int32, right::Int32, child::Int32, start::Int32, size::Int32) = new(name, entry_type, left, right, child, start, size)
end

struct OLEDoc
    data::Vector{UInt8}
    sec_size::Int
    short_sec_size::Int
    min_size_std::Int
    fat::Vector{Int32}
    mini_fat::Vector{Int32}
    dirs::Vector{OLEDirEntry}
    mini_stream::Vector{UInt8}
    OLEDoc(data::Vector{UInt8}, sec_size::Int, short_sec_size::Int, min_size_std::Int, fat::Vector{Int32}, mini_fat::Vector{Int32}, dirs::Vector{OLEDirEntry}, mini_stream::Vector{UInt8}) = new(data, sec_size, short_sec_size, min_size_std, fat, mini_fat, dirs, mini_stream)
end

function _ru16(data, off)  # read UInt16 LE at 0-based offset
    return UInt16(data[off + 1]) | (UInt16(data[off + 2]) << 8)
end

function _ri32(data, off)  # read Int32 LE at 0-based offset (reinterpret preserves sentinel bit patterns)
    return reinterpret(
        Int32,
        UInt32(data[off + 1]) |
        (UInt32(data[off + 2]) << 8) |
        (UInt32(data[off + 3]) << 16) |
        (UInt32(data[off + 4]) << 24),
    )
end

function _ru32(data, off)
    return UInt32(data[off + 1]) |
           (UInt32(data[off + 2]) << 8) |
           (UInt32(data[off + 3]) << 16) |
           (UInt32(data[off + 4]) << 24)
end

function open_ole(data::Vector{UInt8})
    data[1:8] == OLE_MAGIC || error("Not an OLE2 compound document (bad magic)")

    ssz_exp = _ru16(data, 30)
    short_ssz_exp = _ru16(data, 32)
    sec_size = 1 << ssz_exp
    short_sec_size = 1 << short_ssz_exp

    num_fat_secs = _ri32(data, 44)
    dir_first_sec = _ri32(data, 48)
    min_size_std = _ri32(data, 56)
    minifat_first = _ri32(data, 60)
    difat_first = _ri32(data, 68)

    # Collect FAT sector IDs via DIFAT
    fat_sids = Int32[]
    # First 109 DIFAT entries are in the header at offset 76
    for i in 0:108
        sid = _ri32(data, 76 + i * 4)
        sid == FREESID && break
        push!(fat_sids, sid)
    end
    # Follow DIFAT chain if present
    nent = sec_size ÷ 4
    cur_difat = difat_first
    while cur_difat != EOCSID && cur_difat != FREESID
        base = 512 + cur_difat * sec_size
        for i in 0:(nent - 2)
            sid = _ri32(data, base + i * 4)
            sid == FREESID && break
            push!(fat_sids, sid)
        end
        cur_difat = _ri32(data, base + (nent - 1) * 4)
    end

    # Build FAT from fat sector chain
    fat = Int32[]
    sizehint!(fat, length(fat_sids) * nent)
    for fsid in fat_sids
        base = 512 + fsid * sec_size
        for i in 0:(nent - 1)
            push!(fat, _ri32(data, base + i * 4))
        end
    end

    # Read directory entries (each 128 bytes)
    dirs = OLEDirEntry[]
    dir_sid = dir_first_sec
    while dir_sid != EOCSID && dir_sid != FREESID
        base = 512 + dir_sid * sec_size
        for i in 0:(sec_size ÷ 128 - 1)
            dbase = base + i * 128
            name_len = _ru16(data, dbase + 64)   # byte count incl. null terminator
            name = ""
            if name_len >= 2
                nb = name_len - 2
                raw = data[(dbase + 1):(dbase + nb)]
                if nb > 0 && length(raw) % 2 == 0
                    u16 = reinterpret(UInt16, raw)
                    name = transcode(String, Vector{UInt16}(u16))
                end
            end
            etype = data[dbase + 66 + 1]   # entry_type at offset 66
            left = _ri32(data, dbase + 68)
            right = _ri32(data, dbase + 72)
            child = _ri32(data, dbase + 76)
            start = _ri32(data, dbase + 116)
            sz = _ri32(data, dbase + 120)
            push!(dirs, OLEDirEntry(name, etype, left, right, child, start, sz))
        end
        dir_sid = fat[dir_sid + 1]
    end

    # Build mini-FAT
    mini_fat = Int32[]
    mf_sid = minifat_first
    while mf_sid != EOCSID && mf_sid != FREESID
        base = 512 + mf_sid * sec_size
        for i in 0:(nent - 1)
            push!(mini_fat, _ri32(data, base + i * 4))
        end
        mf_sid = fat[mf_sid + 1]
    end

    # Read mini-stream (root entry's content stream)
    mini_stream = UInt8[]
    root = dirs[1]
    if root.size > 0 && root.start != EOCSID && root.start != FREESID
        sid = root.start
        while sid != EOCSID && sid != FREESID
            base = 512 + sid * sec_size
            append!(mini_stream, data[(base + 1):(base + sec_size)])
            sid = fat[sid + 1]
        end
        resize!(mini_stream, min(root.size, length(mini_stream)))
    end

    return OLEDoc(
        data, sec_size, short_sec_size, Int(min_size_std), fat, mini_fat, dirs, mini_stream
    )
end

function _read_sector_chain(doc::OLEDoc, start_sid::Int32)
    result = UInt8[]
    sid = start_sid
    while sid != EOCSID && sid != FREESID
        base = 512 + sid * doc.sec_size
        append!(result, doc.data[(base + 1):(base + doc.sec_size)])
        sid = doc.fat[sid + 1]
    end
    return result
end

function _read_mini_chain(doc::OLEDoc, start_sid::Int32, size::Int32)
    result = UInt8[]
    sid = start_sid
    while sid != EOCSID && sid != FREESID
        base = sid * doc.short_sec_size
        append!(result, doc.mini_stream[(base + 1):(base + doc.short_sec_size)])
        sid = doc.mini_fat[sid + 1]
    end
    resize!(result, min(size, length(result)))
    return result
end

function get_stream(doc::OLEDoc, name::String)
    # Search directory entries (case-insensitive)
    uname = uppercase(name)
    for entry in doc.dirs
        entry.entry_type == 0 && continue
        if uppercase(entry.name) == uname
            if entry.size > 0
                if entry.size < doc.min_size_std && !isempty(doc.mini_stream)
                    return _read_mini_chain(doc, entry.start, entry.size)
                else
                    data = _read_sector_chain(doc, entry.start)
                    resize!(data, min(entry.size, length(data)))
                    return data
                end
            else
                return UInt8[]
            end
        end
    end
    return error("Stream '$name' not found in OLE document")
end
