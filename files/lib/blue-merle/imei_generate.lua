#!/usr/bin/env lua
-- blue-merle v2: IMEI generator — replaces v1's imei_generate.py
-- Usage:
--   lua imei_generate.lua                       → random IMEI using TAC pool
--   lua imei_generate.lua random                → same as above
--   lua imei_generate.lua deterministic <imsi>  → deterministic: same IMEI for same IMSI (stable per-SIM)
--
-- Note: the user-facing "static" IMEI mode is handled entirely in shell
-- (_gen_imei in functions.sh reads blue-merle.options.static_imei_slotN);
-- it never reaches this generator.
--
-- TAC pool path: /usr/share/blue-merle/tac_pool.json (or dev path via ENV)
-- Fallback if pool is missing/empty: fully random 14-digit body + Luhn check digit.
--
-- Returns: one line, the 15-digit IMEI, to stdout.
-- Exits non-zero on error.

-- Ensure the blue-merle library directory is in the search path.
package.path = "/lib/blue-merle/?.lua;" .. package.path

local luhn = require("luhn")

local TAC_POOL_PATH = os.getenv("BLUE_MERLE_TAC_POOL") or "/usr/share/blue-merle/tac_pool.json"

-- Minimal JSON array scanner — extracts "tac" string values without a full JSON library.
-- Returns a table of TAC strings, or an empty table on failure.
local function load_tac_pool(path)
    local tacs = {}
    local f = io.open(path, "r")
    if not f then return tacs end
    local content = f:read("*all")
    f:close()
    -- Extract every "tac": "<8-digits>" entry.
    for tac in content:gmatch('"tac"%s*:%s*"(%d%d%d%d%d%d%d%d)"') do
        tacs[#tacs + 1] = tac
    end
    return tacs
end

-- Pick a random TAC from the pool; fall back to a random 8-digit prefix if empty.
local function pick_tac(pool)
    if #pool > 0 then
        return pool[math.random(1, #pool)]
    end
    -- Fallback: random 8 digits (no TAC constraint).
    local t = ""
    for _ = 1, 8 do t = t .. tostring(math.random(0, 9)) end
    return t
end

-- Generate a random 15-digit Luhn-valid IMEI using a TAC from the pool.
local function gen_imei_from_pool(pool)
    local tac = pick_tac(pool)
    -- 6 random serial digits.
    local serial = ""
    for _ = 1, 6 do serial = serial .. tostring(math.random(0, 9)) end
    return luhn.make_imei(tac .. serial)
end

-- djb2 hash of a string → integer seed in [0, 2^31).
local function djb2_seed(s)
    local seed = 5381
    for i = 1, #s do
        seed = (seed * 33 + s:byte(i)) % (2^31)
    end
    return seed
end

-- Deterministic IMEI (SIM-stable): derive from the SIM's IMSI.
-- Same IMSI always produces the same IMEI — matching v1's -d flag behaviour.
-- $1 = 15-digit IMSI string.
local function gen_imei_deterministic(pool, imsi)
    if not imsi or #imsi < 6 then
        io.stderr:write("imei_generate: deterministic mode requires a valid IMSI argument\n")
        os.exit(1)
    end
    math.randomseed(djb2_seed(imsi))
    return gen_imei_from_pool(pool)
end

-- Seed from /dev/urandom so rapid back-to-back calls don't collide.
local function urandom_seed()
    local f = io.open("/dev/urandom", "rb")
    if f then
        local b = f:read(4)
        f:close()
        if b and #b == 4 then
            local b1, b2, b3, b4 = b:byte(1, 4)
            return (b1 * 16777216 + b2 * 65536 + b3 * 256 + b4) % (2^31)
        end
    end
    return os.time()
end

-- Main
math.randomseed(urandom_seed())
local mode = arg[1] or "random"
local pool = load_tac_pool(TAC_POOL_PATH)

local imei
if mode == "deterministic" then
    imei = gen_imei_deterministic(pool, arg[2])
elseif mode == "random" or mode == "" then
    imei = gen_imei_from_pool(pool)
else
    io.stderr:write("Usage: imei_generate.lua [random|deterministic <imsi>]\n")
    os.exit(1)
end

-- Sanity check before printing.
if not luhn.is_valid(imei) then
    io.stderr:write("BUG: generated IMEI failed Luhn check: " .. imei .. "\n")
    os.exit(1)
end

print(imei)
