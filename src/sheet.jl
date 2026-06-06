# Worksheet cell record parsing (BIFF8).
# Reads NUMBER, LABELSST, LABEL, RK, MULRK, FORMULA, BOOLERR, BLANK records.

"""
    Cell

A single cell value read from an XLS worksheet.

Fields:
- `type::Int` — cell type:
  - `0` — empty (no data)
  - `1` — text; `value` is a `String`
  - `2` — number; `value` is a `Float64`
  - `3` — date/time; `value` is a `Date` or `DateTime`
  - `4` — boolean; `value` is a `Bool`
  - `5` — error (e.g. `"#DIV/0!"`); `value` is a `String`
  - `6` — blank (formatted but empty); `value` is `nothing`
- `value` — the cell content typed according to `type`, or `nothing` for empty/blank cells

# Example
```julia
wb = readxls("report.xls")
cell = wb["Sheet1"][2, 3]
cell.type == 2 && println(cell.value::Float64)
```
"""
struct Cell
    type::Int
    value::Any
end

const EMPTY_CELL = Cell(XL_CELL_EMPTY, nothing)

"""
    Sheet

A single worksheet within a [`Workbook`](@ref).

Fields:
- `name::String` — sheet name as it appears in the workbook
- `nrows::Int` — number of rows containing data
- `ncols::Int` — number of columns containing data
- `cells::Dict{Tuple{Int,Int},Cell}` — sparse cell map keyed by `(row, col)` (1-based)

Use `sheet[row, col]` to retrieve a [`Cell`](@ref). Positions outside the populated range
return an empty cell (`type == 0`, `value === nothing`).

# Example
```julia
wb = readxls("report.xls")
sheet = wb["Summary"]
for row in 1:sheet.nrows, col in 1:sheet.ncols
    cell = sheet[row, col]
    println(cell.value)
end
```
"""
mutable struct Sheet
    name::String
    nrows::Int
    ncols::Int
    cells::Dict{Tuple{Int,Int},Cell}  # (row, col) 1-based -> Cell
    Sheet(name::String, nrows::Int, ncols::Int, cells::Dict{Tuple{Int,Int},Cell}) = new(name, nrows, ncols, cells)
end

Sheet(name::String) = Sheet(name, 0, 0, Dict{Tuple{Int,Int},Cell}())

function Base.getindex(s::Sheet, row::Int, col::Int)
    return get(s.cells, (row, col), EMPTY_CELL)
end

function _put_cell!(sheet::Sheet, row0::Int, col0::Int, cell::Cell)
    row = row0 + 1   # convert 0-based to 1-based
    col = col0 + 1
    sheet.cells[(row, col)] = cell
    sheet.nrows = max(sheet.nrows, row)
    return sheet.ncols = max(sheet.ncols, col)
end

function _xf_cell_type(wb::WorkbookGlobals, xf_idx::Int)
    xf_idx += 1   # 1-based
    return xf_idx > length(wb.xf_type) ? XL_CELL_NUMBER : wb.xf_type[xf_idx]
end

function parse_sheet(stream::Vector{UInt8}, wb::WorkbookGlobals, name::String)
    sheet = Sheet(name)
    pos = 1
    # pending_formula_cell: when FORMULA result is a string, we need the next STRING record
    pending_string_cell = nothing   # (row0, col0) or nothing

    while pos + 3 <= length(stream)
        opcode = Int(UInt16(stream[pos]) | (UInt16(stream[pos + 1]) << 8))
        reclen = Int(UInt16(stream[pos + 2]) | (UInt16(stream[pos + 3]) << 8))
        pos += 4

        if reclen == 0
            opcode == XL_EOF && break
            continue
        end

        data = @view stream[pos:(pos + reclen - 1)]
        pos += reclen

        if opcode == XL_NUMBER
            reclen >= 14 || continue
            row0 = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
            col0 = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
            xf = Int(UInt16(data[5]) | (UInt16(data[6]) << 8))
            val = reinterpret(
                Float64,
                UInt64(data[7]) |
                (UInt64(data[8]) << 8) |
                (UInt64(data[9]) << 16) |
                (UInt64(data[10]) << 24) |
                (UInt64(data[11]) << 32) |
                (UInt64(data[12]) << 40) |
                (UInt64(data[13]) << 48) |
                (UInt64(data[14]) << 56),
            )
            ctype = _xf_cell_type(wb, xf)
            cell = if ctype == XL_CELL_DATE
                Cell(XL_CELL_DATE, excel_date_to_datetime(val, wb.date1904))
            else
                Cell(XL_CELL_NUMBER, val)
            end
            _put_cell!(sheet, row0, col0, cell)

        elseif opcode == XL_LABELSST
            reclen >= 8 || continue
            row0 = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
            col0 = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
            # xf  = Int(UInt16(data[5]) | (UInt16(data[6]) << 8))
            ssti = Int(
                Int32(
                    UInt32(data[7]) |
                    (UInt32(data[8]) << 8) |
                    (UInt32(data[9]) << 16) |
                    (UInt32(data[10]) << 24),
                ),
            )
            str = (ssti >= 0 && ssti < length(wb.sst)) ? wb.sst[ssti + 1] : ""
            _put_cell!(sheet, row0, col0, Cell(XL_CELL_TEXT, str))

        elseif opcode == XL_LABEL
            reclen >= 7 || continue
            row0 = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
            col0 = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
            str = unpack_label_string(data, 7)
            _put_cell!(sheet, row0, col0, Cell(XL_CELL_TEXT, str))

        elseif opcode == XL_RK
            reclen >= 10 || continue
            row0 = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
            col0 = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
            xf = Int(UInt16(data[5]) | (UInt16(data[6]) << 8))
            val = decode_rk(@view data[7:10])
            ctype = _xf_cell_type(wb, xf)
            cell = if ctype == XL_CELL_DATE
                Cell(XL_CELL_DATE, excel_date_to_datetime(val, wb.date1904))
            else
                Cell(XL_CELL_NUMBER, val)
            end
            _put_cell!(sheet, row0, col0, cell)

        elseif opcode == XL_MULRK
            # Row(2) + FirstCol(2) + [XF(2)+RK(4)]... + LastCol(2)
            reclen >= 6 || continue
            row0 = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
            first_col = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
            last_col = Int(UInt16(data[reclen - 1]) | (UInt16(data[reclen]) << 8))
            col = first_col
            dpos = 5   # start of first XF+RK pair (1-based in data)
            while col <= last_col && dpos + 5 <= reclen
                xf = Int(UInt16(data[dpos]) | (UInt16(data[dpos + 1]) << 8))
                val = decode_rk(@view data[(dpos + 2):(dpos + 5)])
                ctype = _xf_cell_type(wb, xf)
                cell = if ctype == XL_CELL_DATE
                    Cell(XL_CELL_DATE, excel_date_to_datetime(val, wb.date1904))
                else
                    Cell(XL_CELL_NUMBER, val)
                end
                _put_cell!(sheet, row0, col, cell)
                dpos += 6
                col += 1
            end

        elseif opcode == XL_BOOLERR
            reclen >= 8 || continue
            row0 = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
            col0 = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
            bval = data[7]
            is_err = data[8] != 0
            if is_err
                errstr = get(XL_ERRORS, bval, "#ERR!")
                _put_cell!(sheet, row0, col0, Cell(XL_CELL_ERROR, errstr))
            else
                _put_cell!(sheet, row0, col0, Cell(XL_CELL_BOOLEAN, bval != 0))
            end

        elseif opcode == XL_BLANK
            # Blank cells only matter for formatting; store as blank
            reclen >= 6 || continue
            row0 = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
            col0 = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
            _put_cell!(sheet, row0, col0, Cell(XL_CELL_BLANK, nothing))

        elseif opcode == XL_MULBLANK
            reclen >= 6 || continue
            row0 = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
            first_col = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
            last_col = Int(UInt16(data[reclen - 1]) | (UInt16(data[reclen]) << 8))
            for col in first_col:last_col
                _put_cell!(sheet, row0, col, Cell(XL_CELL_BLANK, nothing))
            end

        elseif opcode in (XL_FORMULA, XL_FORMULA_ALT1, XL_FORMULA_ALT2)
            reclen >= 14 || continue
            row0 = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
            col0 = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
            xf = Int(UInt16(data[5]) | (UInt16(data[6]) << 8))
            # Result is 8 bytes at offset 7-14
            # If data[14] == 0xFF and data[13] == 0xFF: numeric result
            # If data[14] == 0xFF and data[13] != 0xFF: special (string/bool/err/blank)
            first_byte = data[14]
            if data[14] == 0xFF && data[13] == 0xFF
                # Numeric result
                val = reinterpret(
                    Float64,
                    UInt64(data[7]) |
                    (UInt64(data[8]) << 8) |
                    (UInt64(data[9]) << 16) |
                    (UInt64(data[10]) << 24) |
                    (UInt64(data[11]) << 32) |
                    (UInt64(data[12]) << 40) |
                    (UInt64(data[13]) << 48) |
                    (UInt64(data[14]) << 56),
                )
                ctype = _xf_cell_type(wb, xf)
                cell = if ctype == XL_CELL_DATE
                    Cell(XL_CELL_DATE, excel_date_to_datetime(val, wb.date1904))
                else
                    Cell(XL_CELL_NUMBER, val)
                end
                _put_cell!(sheet, row0, col0, cell)
            else
                type_byte = data[14]
                if type_byte == 0x01  # Boolean
                    _put_cell!(sheet, row0, col0, Cell(XL_CELL_BOOLEAN, data[8] != 0))
                elseif type_byte == 0x02  # Error
                    errstr = get(XL_ERRORS, data[8], "#ERR!")
                    _put_cell!(sheet, row0, col0, Cell(XL_CELL_ERROR, errstr))
                elseif type_byte == 0x03  # Blank string
                    _put_cell!(sheet, row0, col0, Cell(XL_CELL_TEXT, ""))
                elseif type_byte == 0x00  # String - value in next STRING record
                    pending_string_cell = (row0, col0)
                end
            end

        elseif opcode == XL_STRING
            # String result of FORMULA - follows immediately after FORMULA record
            if pending_string_cell !== nothing
                row0, col0 = pending_string_cell
                str = unpack_label_string(data, 1)
                _put_cell!(sheet, row0, col0, Cell(XL_CELL_TEXT, str))
                pending_string_cell = nothing
            end

        elseif opcode == XL_DIMENSIONS
            # Store sheet dimensions hint (optional - we track dynamically)
            if reclen >= 10
                # BIFF8: first_row(4) + last_row(4) + first_col(2) + last_col(2)
                # last_row and last_col are exclusive upper bounds
            end

        elseif opcode == XL_EOF
            break
        end
    end

    return sheet
end
