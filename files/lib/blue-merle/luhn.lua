-- Luhn checksum helpers for IMEI generation.
-- Adapted from https://cybersecurity.att.com/blogs/labs-research/luhn-checksum-algorithm-lua-implementation
-- v2: exported as a module; standalone CLI mode kept for backwards compat.

local bit = require("bit")
local M = {}

local function luhn_checksum(card)
    local num = 0
    local nDigits = #card
    local odd = bit.band(nDigits, 1)
    for i = 0, nDigits - 1 do
        local d = tonumber(card:sub(i + 1, i + 1))
        if bit.bxor(bit.band(i, 1), odd) == 0 then
            d = d * 2
        end
        if d > 9 then d = d - 9 end
        num = num + d
    end
    return num
end

-- Return the check digit that makes s a valid Luhn string.
function M.check_digit(s)
    return (10 - (luhn_checksum(s .. "0") % 10)) % 10
end

-- Return true if s (15 digits) has a valid Luhn check digit.
function M.is_valid(s)
    return luhn_checksum(s) % 10 == 0
end

-- Append the Luhn check digit to a 14-digit TAC+serial body.
function M.make_imei(body14)
    return body14 .. tostring(M.check_digit(body14))
end

-- Generate a fully random 15-digit Luhn-valid IMEI (no TAC constraint).
function M.random_imei()
    local body = ""
    for _ = 1, 14 do
        body = body .. tostring(math.random(0, 9))
    end
    return M.make_imei(body)
end

-- Standalone CLI: lua luhn.lua <10-digit-seed>  →  prints 15-digit IMEI
if arg and arg[0] and arg[0]:match("luhn%.lua$") then
    math.randomseed(tonumber(arg[1]) or os.time())
    print(M.random_imei())
end

return M
