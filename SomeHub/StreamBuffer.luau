--!native
--!optimize 2
--[[
	StreamBuffer (optimized)

	A growable wrapper around Luau's `buffer` type.

	Optimizations vs original:
	  * `reserve` inlined into writers — fast-path (len+extra <= cap)
	    is a single branch, no function call, no math.max.
	  * Pre-computed `needed` for multi-byte writers.
	  * Direct `buffer.*` writes with local function refs (no
	    `self.reserve` indirect calls).
	  * `writeLenString` merged into a single reserve for len+string.
	  * `allocRegion` fast-path.
	  * `tostring` uses `buffer.readstring` (required for exact len).
	  * `__index` metatable kept so all writes stay method calls
	    (Luau JIT optimizes these well).
]]

local StreamBuffer = {}
StreamBuffer.__index = StreamBuffer

-- Cache buffer functions once (global lookups are slow in hot loops)
local bcreate      = buffer.create
local bcopy        = buffer.copy
local breadstring  = buffer.readstring
local bwriteu8     = buffer.writeu8
local bwriteu16    = buffer.writeu16
local bwritei16    = buffer.writei16
local bwriteu32    = buffer.writeu32
local bwritei32    = buffer.writei32
local bwritef32    = buffer.writef32
local bwritef64    = buffer.writef64
local bwritestring = buffer.writestring
local bfill        = buffer.fill
local m_max        = math.max

local DEFAULT_CAPACITY = 4096

-- Internal: grow the buffer to hold at least `needed` bytes total.
-- Always doubles, never shrinks. Called only on slow path.
local function grow(self, needed)
	local newCap = self.cap * 2
	if newCap < needed then
		newCap = needed
	end
	if newCap < 64 then
		newCap = 64
	end
	local newBuf = bcreate(newCap)
	bcopy(newBuf, 0, self.buf, 0, self.len)
	self.buf = newBuf
	self.cap = newCap
end

function StreamBuffer.new(initialCapacity)
	local cap = initialCapacity or DEFAULT_CAPACITY
	if cap < 64 then
		cap = 64
	end
	return setmetatable({
		buf = bcreate(cap),
		len = 0,
		cap = cap,
	}, StreamBuffer)
end

-- Explicit reserve — kept for API compatibility, but writers no longer
-- call it on every byte (they inline the fast-path).
function StreamBuffer:reserve(extra)
	local needed = self.len + extra
	if needed > self.cap then
		grow(self, needed)
	end
end

function StreamBuffer:allocRegion(size)
	local needed = self.len + size
	if needed > self.cap then
		grow(self, needed)
	end
	local base = self.len
	self.len = needed
	return base
end

-- ---------------------------------------------------------------------------
-- Writers: fast-path is inlined; slow-path calls grow()
-- ---------------------------------------------------------------------------

function StreamBuffer:writeu8(v)
	local len = self.len
	if len + 1 > self.cap then
		grow(self, len + 1)
	end
	bwriteu8(self.buf, len, v)
	self.len = len + 1
end

function StreamBuffer:writeu16(v)
	local len = self.len
	if len + 2 > self.cap then
		grow(self, len + 2)
	end
	bwriteu16(self.buf, len, v)
	self.len = len + 2
end

function StreamBuffer:writei16(v)
	local len = self.len
	if len + 2 > self.cap then
		grow(self, len + 2)
	end
	bwritei16(self.buf, len, v)
	self.len = len + 2
end

function StreamBuffer:writeu32(v)
	local len = self.len
	if len + 4 > self.cap then
		grow(self, len + 4)
	end
	bwriteu32(self.buf, len, v)
	self.len = len + 4
end

function StreamBuffer:writei32(v)
	local len = self.len
	if len + 4 > self.cap then
		grow(self, len + 4)
	end
	bwritei32(self.buf, len, v)
	self.len = len + 4
end

function StreamBuffer:writef32(v)
	local len = self.len
	if len + 4 > self.cap then
		grow(self, len + 4)
	end
	bwritef32(self.buf, len, v)
	self.len = len + 4
end

function StreamBuffer:writef64(v)
	local len = self.len
	if len + 8 > self.cap then
		grow(self, len + 8)
	end
	bwritef64(self.buf, len, v)
	self.len = len + 8
end

function StreamBuffer:writestring(s)
	local n = #s
	local len = self.len
	if len + n > self.cap then
		grow(self, len + n)
	end
	bwritestring(self.buf, len, s)
	self.len = len + n
end

-- Single reserve for both length prefix and string body — halves the
-- number of grow-checks vs original (which called writeu32 + writestring).
function StreamBuffer:writeLenString(s)
	local n = #s
	local total = 4 + n
	local len = self.len
	if len + total > self.cap then
		grow(self, len + total)
	end
	local buf = self.buf
	bwriteu32(buf, len, n)
	bwritestring(buf, len + 4, s)
	self.len = len + total
end

function StreamBuffer:fill(value, count)
	local len = self.len
	if len + count > self.cap then
		grow(self, len + count)
	end
	bfill(self.buf, len, value, count)
	self.len = len + count
end

-- Absolute-offset single-byte write into an already-reserved region.
-- `offset` is a byte offset from the start of the buffer, NOT relative to
-- self.len. Caller must have reserved it via allocRegion first.
function StreamBuffer:pokeu8(offset, v)
	bwriteu8(self.buf, offset, v)
end

function StreamBuffer:tostring()
	return breadstring(self.buf, 0, self.len)
end

return StreamBuffer
