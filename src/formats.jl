# Number format string analysis for date detection and XF record handling.

# Determine if a format string represents a date/time value.
# Logic: strip quoted text, escaped chars, and bracketed content, then count
# date chars (y,m,d,h,s) vs numeric chars (0,#,?). Date wins if count is higher.
function is_date_format_string(fmt::String)
    date_chars = 0
    num_chars = 0
    i = firstindex(fmt)
    last = lastindex(fmt)
    while i <= last
        c = fmt[i]
        if c == '"'
            # Skip quoted string
            i = nextind(fmt, i)
            while i <= last && fmt[i] != '"'
                i = nextind(fmt, i)
            end
        elseif c == '\\'
            # Escaped character - skip next
            i = nextind(fmt, i)
        elseif c == '['
            # Bracketed section (e.g. [h], [Red]) - skip
            while i <= last && fmt[i] != ']'
                i = nextind(fmt, i)
            end
        elseif c in ('y', 'Y', 'd', 'D', 'h', 'H', 's', 'S')
            date_chars += 1
        elseif c == 'm' || c == 'M'
            # 'm' is ambiguous (minutes or months) but count as date
            date_chars += 1
        elseif c in ('0', '#', '?')
            num_chars += 1
        end
        i = nextind(fmt, i)
    end
    return date_chars > 0 && date_chars >= num_chars
end

function format_is_date(format_code::Int, format_str::String)
    format_code in BUILTIN_DATE_FORMATS && return true
    # For built-in codes that aren't date, return false without string analysis
    if format_code > 0 && format_code <= 49
        return false
    end
    return is_date_format_string(format_str)
end

# Decode an RK value (4-byte packed number used in RK and MULRK records).
# Bit 0: 0=float, 1=integer
# Bit 1: 0=as-is, 1=divide by 100
function decode_rk(rk_bytes::AbstractVector{UInt8})
    u = UInt32(rk_bytes[1]) |
        (UInt32(rk_bytes[2]) << 8) |
        (UInt32(rk_bytes[3]) << 16) |
        (UInt32(rk_bytes[4]) << 24)
    rk = reinterpret(Int32, u)
    mul100 = (rk & 2) != 0
    is_int = (rk & 1) != 0
    if is_int
        val = Float64(rk >> 2)   # arithmetic right shift preserves sign
    else
        # Top 30 bits of rk become top 30 bits of the 64-bit IEEE 754 double.
        # Clear bottom 2 bits then place in upper 32 bits of Int64.
        i64 = Int64(rk & Int32(-4)) << 32   # -4 == 0xFFFFFFFC as Int32
        val = reinterpret(Float64, i64)
    end
    return mul100 ? val / 100.0 : val
end

# Convert an Excel serial date number to a Julia DateTime.
# date1904: true for the 1904 date system (Mac legacy), false for 1900 system.
# Returns Date for integers, DateTime for fractional values.
function excel_date_to_datetime(serial::Float64, date1904::Bool)
    day_offset = Int(floor(serial))
    frac = serial - floor(serial)

    if date1904
        # Day 0 = 1904-01-01
        d = Date(1904, 1, 1) + Day(day_offset)
    else
        # Excel 1900 system. Excel incorrectly treats 1900 as a leap year,
        # so day 60 = fake Feb 29. We use two different epochs:
        #   days  < 60: epoch 1899-12-31, offset = n      (day 1 → 1900-01-01)
        #   day  == 60: map to 1900-02-28
        #   days  > 60: epoch 1899-12-30, offset = n      (day 61 → 1900-03-01)
        if day_offset == 60
            d = Date(1900, 2, 28)
        elseif day_offset < 60
            d = Date(1899, 12, 31) + Day(day_offset)
        else
            d = Date(1899, 12, 30) + Day(day_offset)
        end
    end

    if frac > 1e-6
        total_secs = round(Int, frac * 86400)
        h = total_secs ÷ 3600
        m = (total_secs % 3600) ÷ 60
        s = total_secs % 60
        return DateTime(d) + Hour(h) + Minute(m) + Second(s)
    else
        return d
    end
end
