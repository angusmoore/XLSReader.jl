using Test
using Dates
using XLSReader
using Aqua

@testset "decode_rk" begin
    # Integer 100: bit0=1 (int), bit1=0, value = 100 << 2 = 400 = 0x190
    rk_100 = reinterpret(UInt8, [Int32(100 << 2 | 1)])
    @test XLSReader.decode_rk(rk_100) == 100.0

    # Integer 1 divided by 100: bits = (1<<2)|3 = 7
    rk_001 = reinterpret(UInt8, [Int32(1 << 2 | 3)])
    @test XLSReader.decode_rk(rk_001) ≈ 0.01

    # Float 1.0: IEEE 754 double 0x3FF0000000000000
    # Top 32 bits: 0x3FF00000, clear bottom 2 bits: 0x3FF00000
    # RK = 0x3FF00000 | 0 (float, no mul100)
    rk_float1 = [0x00, 0x00, 0xF0, 0x3F]
    @test XLSReader.decode_rk(rk_float1) == 1.0
end

@testset "date formats" begin
    @test XLSReader.format_is_date(14, "") == true
    @test XLSReader.format_is_date(15, "") == true
    @test XLSReader.format_is_date(20, "") == true
    @test XLSReader.format_is_date(0, "General") == false
    @test XLSReader.format_is_date(0, "yyyy-mm-dd") == true
    @test XLSReader.format_is_date(0, "0.00%") == false
end

@testset "is_date_format_string" begin
    @test XLSReader.is_date_format_string("yyyy-mm-dd") == true
    @test XLSReader.is_date_format_string("h:mm:ss") == true
    @test XLSReader.is_date_format_string("0.00") == false
    @test XLSReader.is_date_format_string("#,##0") == false
    @test XLSReader.is_date_format_string("m/d/yy") == true
    # Quoted content should be ignored
    @test XLSReader.is_date_format_string("\"Year:\" yyyy") == true
end

@testset "excel_date" begin
    # Excel serial 1 = 1900-01-01 in 1900 system
    d = XLSReader.excel_date_to_datetime(1.0, false)
    @test d == Dates.Date(1900, 1, 1)

    # Excel serial 44927 = 2023-01-01 (1900 system)
    d2 = XLSReader.excel_date_to_datetime(44927.0, false)
    @test d2 == Dates.Date(2023, 1, 1)

    # 1904 system: day 0 = 1904-01-01
    d3 = XLSReader.excel_date_to_datetime(0.0, true)
    @test d3 == Dates.Date(1904, 1, 1)

    # Fractional: 0.5 = noon on epoch day
    dt = XLSReader.excel_date_to_datetime(1.5, false)
    @test dt isa Dates.DateTime
    @test Dates.hour(dt) == 12
end

@testset "OLE magic check" begin
    bad = zeros(UInt8, 512)
    @test_throws ErrorException XLSReader.open_ole(bad)
end

@testset "f11hist-1969-2009.xls" begin
    wb = readxls(joinpath(@__DIR__, "testdata", "f11hist-1969-2009.xls"))

    # Sheet structure
    @test length(wb.sheets) == 2
    @test wb.sheets[1].name == "Data"
    @test wb.sheets[2].name == "Notes "
    @test wb["Data"].nrows == 531
    @test wb["Data"].ncols == 16
    @test wb["Notes "].nrows == 27

    data = wb["Data"]

    # Text cells
    @test data[1, 1].type == XL_CELL_TEXT
    @test data[1, 1].value == "F11 EXCHANGE RATES "
    @test data[2, 2].value == "A\$1=JPY"
    @test data[2, 3].value == "A\$1=USD"
    @test data[3, 2].value == "AUD/JPY Exchange Rate"
    @test data[9, 1].value == "Source"
    @test data[11, 2].value == "FXRJY"
    @test data[11, 3].value == "FXRUSD"

    # Date cells — publication date row (row 10)
    @test data[10, 1].type == XL_CELL_TEXT
    @test data[10, 1].value == "Publication date"
    @test data[10, 2].type == XL_CELL_DATE
    @test data[10, 2].value == Date(2009, 12, 31)

    # First data row (row 12) — date + numeric values
    @test data[12, 1].type == XL_CELL_DATE
    @test data[12, 1].value == Date(1969, 7, 31)
    @test data[12, 2].type == XL_CELL_NUMBER
    @test data[12, 2].value ≈ 2.7216392e8 rtol = 1e-6
    @test data[12, 3].type == XL_CELL_NUMBER
    @test data[12, 3].value ≈ 1.1138 rtol = 1e-6

    # Second data row
    @test data[13, 1].value == Date(1969, 8, 31)
    @test data[13, 3].value ≈ 1.1091 rtol = 1e-6

    # Last data row (row 497)
    @test data[497, 1].value == Date(2009, 12, 31)
    @test data[497, 2].value ≈ 2.71584064e8 rtol = 1e-6
    @test data[497, 3].value ≈ 0.8969 rtol = 1e-6

    # Blank cells
    @test data[7, 1].type == XL_CELL_BLANK
    @test data[8, 2].type == XL_CELL_BLANK

    # Empty cells (beyond data)
    @test data[1, 3].type == XL_CELL_EMPTY

    # Indexing by sheet name
    @test wb["Data"][2, 1].value == "Title"
end

include("test_readxlsheet.jl")

@testset "Code quality" begin
    Aqua.test_all(XLSReader)
end
