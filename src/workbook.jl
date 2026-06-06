# Workbook globals parsing: BOF, CODEPAGE, BOUNDSHEET, SST, FORMAT, XF, DATEMODE.

struct SheetInfo
    name::String
    bof_pos::Int      # absolute byte offset in the Workbook stream
    visible::UInt8    # 0=visible, 1=hidden, 2=very hidden
    sheet_type::UInt8 # 0=worksheet, 1=macro, 2=chart, 6=VBA
    SheetInfo(name::String, bof_pos::Int, visible::UInt8, sheet_type::UInt8) = new(name, bof_pos, visible, sheet_type)
end

mutable struct WorkbookGlobals
    biff_version::Int
    codepage::Int
    date1904::Bool
    sheets::Vector{SheetInfo}
    sst::Vector{String}
    # format_strings: code -> format string
    formats::Dict{Int,String}
    # xf_list: each entry is (format_code,) - enough to determine date vs number
    xf_fmt::Vector{Int}
    # Precomputed: xf_index -> cell type (XL_CELL_NUMBER or XL_CELL_DATE)
    xf_type::Vector{Int}
    function WorkbookGlobals(biff_version::Int, codepage::Int, date1904::Bool, sheets::Vector{SheetInfo}, sst::Vector{String}, formats::Dict{Int,String}, xf_fmt::Vector{Int}, xf_type::Vector{Int})
        new(biff_version, codepage, date1904, sheets, sst, formats, xf_fmt, xf_type)
    end
end

function WorkbookGlobals()
    return WorkbookGlobals(
        0, 1252, false, SheetInfo[], String[], copy(BUILTIN_FORMATS), Int[], Int[]
    )
end

function read_workbook_globals(stream::Vector{UInt8})
    wb = WorkbookGlobals()
    pos = 1
    sst_chunks = Vector{UInt8}[]

    while pos + 3 <= length(stream)
        opcode = Int(UInt16(stream[pos]) | (UInt16(stream[pos + 1]) << 8))
        reclen = Int(UInt16(stream[pos + 2]) | (UInt16(stream[pos + 3]) << 8))
        pos += 4
        data = @view stream[pos:(pos + reclen - 1)]
        pos += reclen

        if opcode == XL_BOF
            reclen >= 4 || continue
            vers = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
            btype = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
            if vers == 0x0600
                wb.biff_version = 8
            elseif vers == 0x0500
                wb.biff_version = 5
            end

        elseif opcode == XL_CODEPAGE
            reclen >= 2 || continue
            wb.codepage = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))

        elseif opcode == XL_DATEMODE
            reclen >= 2 || continue
            wb.date1904 = (UInt16(data[1]) | (UInt16(data[2]) << 8)) != 0

        elseif opcode == XL_BOUNDSHEET
            reclen >= 6 || continue
            sheet_bof = Int(
                UInt32(data[1]) |
                (UInt32(data[2]) << 8) |
                (UInt32(data[3]) << 16) |
                (UInt32(data[4]) << 24),
            )
            visibility = data[5]
            sheet_type = data[6]
            # Sheet name: 1-byte length + 1-byte options + chars (BIFF8)
            name = ""
            if reclen >= 8
                nchars = Int(data[7])
                opts = data[8]
                is_utf16 = (opts & 0x01) != 0
                if is_utf16 && reclen >= 8 + nchars * 2
                    raw = data[9:(8 + nchars * 2)]
                    name = transcode(String, reinterpret(UInt16, raw))
                elseif !is_utf16 && reclen >= 8 + nchars
                    name = String(map(b -> Char(b), data[9:(8 + nchars)]))
                end
            end
            push!(wb.sheets, SheetInfo(name, sheet_bof, visibility, sheet_type))

        elseif opcode == XL_SST
            # Collect SST record + subsequent CONTINUE records
            empty!(sst_chunks)
            push!(sst_chunks, Vector{UInt8}(data))
            # Peek ahead for CONTINUE records
            while pos + 3 <= length(stream)
                next_op = Int(UInt16(stream[pos]) | (UInt16(stream[pos + 1]) << 8))
                next_len = Int(UInt16(stream[pos + 2]) | (UInt16(stream[pos + 3]) << 8))
                next_op == XL_CONTINUE || break
                pos += 4
                push!(sst_chunks, Vector{UInt8}(stream[pos:(pos + next_len - 1)]))
                pos += next_len
            end
            wb.sst = parse_sst(sst_chunks)

        elseif opcode == XL_FORMAT
            reclen >= 5 || continue
            fmt_code = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
            # BIFF8: 2-byte code, then a Unicode string (2-byte length + options)
            nchars = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
            opts = reclen >= 5 ? data[5] : 0x00
            is_utf16 = (opts & 0x01) != 0
            fmt_str = ""
            if is_utf16 && reclen >= 5 + nchars * 2
                raw = data[6:(5 + nchars * 2)]
                fmt_str = transcode(String, reinterpret(UInt16, raw))
            elseif !is_utf16 && reclen >= 5 + nchars
                fmt_str = String(map(b -> Char(b), data[6:(5 + nchars)]))
            end
            wb.formats[fmt_code] = fmt_str

        elseif opcode == XL_XF
            # BIFF8 XF record: 20 bytes
            # offset 2-3: format_key (index into format table)
            reclen >= 4 || continue
            fmt_key = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
            push!(wb.xf_fmt, fmt_key)

        elseif opcode == XL_EOF
            break
        end
    end

    # Build xf_type lookup: for each XF record, determine if it's date or number
    resize!(wb.xf_type, length(wb.xf_fmt))
    for (i, fk) in enumerate(wb.xf_fmt)
        fmt_str = get(wb.formats, fk, "")
        wb.xf_type[i] = format_is_date(fk, fmt_str) ? XL_CELL_DATE : XL_CELL_NUMBER
    end

    return wb
end
