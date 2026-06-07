module XLSReader

using Dates
using DataFrames; DataFrame

include("constants.jl")
include("ole.jl")
include("formats.jl")
include("strings.jl")
include("workbook.jl")
include("sheet.jl")

export readxls, readxlsheet, Workbook, Sheet, Cell,
    XL_CELL_EMPTY, XL_CELL_TEXT, XL_CELL_NUMBER, XL_CELL_DATE,
    XL_CELL_BOOLEAN, XL_CELL_ERROR, XL_CELL_BLANK

"""
    Workbook

Holds the parsed contents of an XLS file.

Fields:
- `sheets`: `Vector{Sheet}` — all worksheets in order
- `date1904`: `Bool` — true if the file uses the 1904 date system
"""
struct Workbook
    sheets::Vector{Sheet}
    date1904::Bool
    Workbook(sheets::Vector{Sheet}, date1904::Bool) = new(sheets, date1904)
end

function Base.getindex(wb::Workbook, name::AbstractString)
    let idx = findfirst(s -> s.name == name, wb.sheets)
        idx === nothing ? error("Sheet '$name' not found") : wb.sheets[idx]
    end
end

Base.getindex(wb::Workbook, i::Int) = wb.sheets[i]

"""
    readxls(path) -> Workbook

Read an XLS file and return a `Workbook` containing all worksheets.
Only BIFF8 (Excel 97–2003) is fully supported; BIFF5 (Excel 95) may work
for simple files. BIFF2/3/4 are not supported.

# Example
```julia
wb = readxls("report.xls")
sheet = wb["Summary"]
value = sheet[2, 3].value   # row 2, column 3 (1-based)
```
"""
function readxls(path::AbstractString)
    data = read(path)
    return _parse_xls(data)
end

"""
    readxls(io::IO) -> Workbook

Read an XLS file from an `IO` stream.
"""
function readxls(io::IO)
    data = read(io)
    return _parse_xls(data)
end

"""
    readxlsheet(path, sheetindex::Int; skip=0) -> DataFrame
    readxlsheet(path, sheetname::AbstractString; skip=0) -> DataFrame

Read a single worksheet from an XLS file and return it as a `DataFrame`.
The first row (after skipping `skip` rows) is used as column names.
Empty or blank header cells fall back to `"Column\$c"`. Data cells that are
empty or blank become `missing`.
"""
function readxlsheet(path::AbstractString, sheetindex::Int; skip::Int=0)
    wb = readxls(path)
    sheetindex in eachindex(wb.sheets) ||
        error("Sheet index $sheetindex out of range (file has $(length(wb.sheets)) sheet(s))")
    return _sheet_to_dataframe(wb.sheets[sheetindex]; skip)
end

function readxlsheet(path::AbstractString, sheetname::AbstractString; skip::Int=0)
    wb = readxls(path)
    idx = findfirst(s -> s.name == sheetname, wb.sheets)
    idx === nothing && error("Sheet '$sheetname' not found")
    return _sheet_to_dataframe(wb.sheets[idx]; skip)
end

function _sheet_to_dataframe(sheet::Sheet; skip::Int=0)
    nrows, ncols = sheet.nrows, sheet.ncols
    header_row = skip + 1
    if ncols == 0 || header_row > nrows
        return DataFrames.DataFrame()
    end
    colnames = [begin
        cell = get(sheet.cells, (header_row, c), EMPTY_CELL)
        cell.type in (XL_CELL_EMPTY, XL_CELL_BLANK) || cell.value === nothing ?
            "Column$c" : string(cell.value)
    end for c in 1:ncols]
    data_nrows = nrows - header_row
    cols = [Vector{Any}(undef, data_nrows) for _ in 1:ncols]
    for c in 1:ncols, r in 1:data_nrows
        cell = get(sheet.cells, (header_row + r, c), EMPTY_CELL)
        cols[c][r] = cell.type in (XL_CELL_EMPTY, XL_CELL_BLANK) ? missing : cell.value
    end
    return DataFrames.DataFrame(cols, colnames)
end

function _parse_xls(data::Vector{UInt8})
    doc = open_ole(data)

    # Try "Workbook" first (BIFF8), then "Book" (BIFF5 / older)
    stream = nothing
    for name in ("Workbook", "WORKBOOK", "Book", "BOOK")
        try
            stream = get_stream(doc, name)
            break
        catch
        end
    end
    stream === nothing && error("No Workbook stream found in OLE document")

    wb_globals = read_workbook_globals(stream)

    sheets = Sheet[]
    for info in wb_globals.sheets
        info.sheet_type == 0 || continue   # skip macro, chart, VBA sheets
        bof = info.bof_pos
        bof < length(stream) || continue
        sheet_stream = stream[(bof + 1):end]
        s = parse_sheet(sheet_stream, wb_globals, info.name)
        push!(sheets, s)
    end

    return Workbook(sheets, wb_globals.date1904)
end

"""
    DataFrames.DataFrame(sheet::Sheet) -> DataFrame

Convert a `Sheet` to a `DataFrame`. Each column of the sheet becomes a DataFrame
column (named `"1"`, `"2"`, …). Empty and blank cells become `missing`.
"""
function DataFrames.DataFrame(sheet::Sheet)
    nrows, ncols = sheet.nrows, sheet.ncols
    cols = [Any[missing for _ in 1:nrows] for _ in 1:ncols]
    for ((r, c), cell) in sheet.cells
        cols[c][r] = cell.type in (XL_CELL_EMPTY, XL_CELL_BLANK) ? missing : cell.value
    end
    return DataFrames.DataFrame(cols, string.(1:ncols))
end

end # module XLSReader
