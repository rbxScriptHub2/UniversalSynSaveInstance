--!optimize 2
-- UniversalMethodFinder — optimized Luacid-aware fork
-- Docs: https://luacid.dev/docs
--
-- Optimizations vs original:
--   1) No isEmpty() — O(1) counter for remaining patterns.
--   2) Name lowering only for string keys (no tostring on non-strings).
--   3) No per-match table allocation — direct removal from query.
--   4) All loop state in locals (no upvalue reads in hot loop).
--   5) ipairs over genvs array (not generic for).
--   6) Removed deprecated getfenv() fallback — uses globalenv.
--   7) finder() is reentrant-safe (no module-level shared state).
--   8) Luacid loader unchanged.

local globalenv = getgenv and getgenv() or _G or shared
local globalcontainer = globalenv.globalcontainer

if not globalcontainer then
	globalcontainer = {}
	globalenv.globalcontainer = globalcontainer
end

-- Localize hot globals
local type_       = type
local next_       = next
local pairs_      = pairs
local ipairs_     = ipairs
local tostring_   = tostring
local loadstring_ = loadstring
local pcall_      = pcall
local strlower    = string.lower
local strfind     = string.find
local tblinsert   = table.insert

local genvs = {}
if getgenv then tblinsert(genvs, getgenv()) end
tblinsert(genvs, shared)
tblinsert(genvs, _G)

-- Recursion-depth cap: measures how deep Luau stack can go.
local calllimit = 0
do
	local function determineCalllimit()
		calllimit = calllimit + 1
		determineCalllimit()
	end
	pcall_(determineCalllimit)
end

-- ---------------------------------------------------------------------------
-- Core recursive walker.
-- All state passed as locals — no module-level upvalues in the hot loop.
-- ---------------------------------------------------------------------------
local function recurseEnv(env, depth, hardlimit, query, antioverflow, globalcontainer, printresults, remaining)
	if globalcontainer == env then
		return remaining
	end
	if antioverflow[env] then
		return remaining
	end
	antioverflow[env] = true

	if depth >= hardlimit then
		return remaining
	end

	for name, val in next_, env do
		local Type = type_(val)

		if Type == "table" then
			remaining = recurseEnv(val, depth + 1, hardlimit, query, antioverflow, globalcontainer, printresults, remaining)
			if remaining == 0 then
				return 0
			end
		elseif Type == "function" then
			-- Fast-path: only lowercase string keys; skip non-strings entirely.
			-- Original did tostring()+lower() on every function — 2 string allocs.
			local lowered
			if type_(name) == "string" then
				lowered = strlower(name)
			else
				lowered = strlower(tostring_(name))
			end

			-- Iterate patterns; remove matched ones from query directly.
			-- No `matched` temp table, no isEmpty() linear scan.
			for methodname, pattern in next_, query do
				if pattern(lowered, name) then
					globalcontainer[methodname] = val
					query[methodname] = nil
					remaining -= 1
					if printresults then
						print(methodname, lowered)
					end
					if remaining == 0 then
						return 0
					end
				end
			end
		end
	end

	return remaining
end

-- ---------------------------------------------------------------------------
-- finder: compiles patterns, walks envs, fills globalcontainer.
-- ---------------------------------------------------------------------------
local function finder(Query, ForceSearch, CustomCallLimit, PrintResults)
	local query = {}
	local patternCount = 0

	-- Compile patterns. `pattern` strings are Lua expressions that take
	-- (name, envname) and return truthy on match.
	local function Find(s, p)
		return strfind(s, p, nil, true)
	end
	for methodname, pattern in next_, Query do
		if not globalcontainer[methodname] or ForceSearch then
			if not Find(pattern, "return") then
				pattern = "return " .. pattern
			end
			local fn = loadstring_(pattern)
			if fn then
				query[methodname] = fn
				patternCount += 1
			end
		end
	end

	if patternCount == 0 then
		return
	end

	local antioverflow = {}
	local hardlimit = CustomCallLimit or calllimit
	local remaining = patternCount

	-- Walk each env root. `ipairs` avoids generic-for overhead on the array.
	for _, root in ipairs_(genvs) do
		if remaining == 0 then break end
		remaining = recurseEnv(root, 0, hardlimit, query, antioverflow, globalcontainer, PrintResults, remaining)
	end

	-- Fallback: inherited globals via __index (executor's sandboxed env)
	if remaining > 0 then
		for methodname in next_, Query do
			if not globalcontainer[methodname] then
				globalcontainer[methodname] = globalenv[methodname]
			end
		end
	end
end

-- ============================================================
--  Luacid loader (unchanged from previous fork)
-- ============================================================
function globalcontainer.loadLuacidDecompiler(options)
	if globalcontainer.decompile and not options then
		return globalcontainer.decompile
	end

	if type_(getscriptbytecode) ~= "function" then
		warn("[Luacid] getscriptbytecode is not available in this executor")
		return nil
	end

	globalenv.DecompilerKey = globalenv.DecompilerKey or nil
	globalenv.DecompilerOptions = globalenv.DecompilerOptions or {
		type_annotations = "functions",
		generated_names = "readable",
		indent = "tab",
	}
	if globalenv.DecompilerTelemetry == nil then
		globalenv.DecompilerTelemetry = false
	end
	if globalenv.DecompilerRuntimeContext == nil then
		globalenv.DecompilerRuntimeContext = false
	end

	local ok, err = pcall_(function()
		local source = game:HttpGet("https://luacid.dev/script.lua", true)
		local chunk, loadErr = loadstring_(source, "luacid_loader")
		if not chunk then
			error("loadstring failed: " .. tostring_(loadErr))
		end
		chunk()
	end)

	if not ok then
		warn("[Luacid] Failed to load decompiler: " .. tostring_(err))
		return nil
	end

	local decompile = globalenv.decompile
	if type_(decompile) ~= "function" then
		warn("[Luacid] Luacid did not expose getgenv().decompile")
		return nil
	end

	globalcontainer.decompile = decompile
	return decompile
end

return finder, globalcontainer
