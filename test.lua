-- inject_hook.lua
-- Usage: lua tools/inject_hook.lua <infile> <outfile> [dump_name]
-- Rewrites a Luraph-style ModuleScript that starts with `return({...})` to:
--   local __RT = ({...})
--   -- wrap __RT.X to dump its first arg
--   return __RT
-- The resulting file still requires a Luau/executor to run (due to `continue`, etc.).

local inpath, outpath, dumpname = arg[1], arg[2], arg[3] or "deobf.lua"
if not inpath or not outpath then
  io.stderr:write("Usage: lua tools/inject_hook.lua <infile> <outfile> [dump_name]\n")
  os.exit(1)
end

local function readfile(p)
  local f = assert(io.open(p, 'rb'))
  local s = f:read('*a'); f:close(); return s
end
local function writefile(p, s)
  local f = assert(io.open(p, 'wb'))
  f:write(s); f:close()
end

local src = readfile(inpath)
local pos = src:find("return%(")
if not pos then
  io.stderr:write("Could not find leading 'return(' in input. Aborting.\n")
  os.exit(2)
end

-- Replace only the first occurrence at the top-level with local binding
local patched = src:gsub("return%(", "local __RT = (", 1)

local hook = [[

-- injected by inject_hook.lua
do
  local function try_write(name, data)
    local ok
    if type(writefile) == 'function' then
      ok = pcall(writefile, name, data)
      if ok then return end
    end
    if syn and type(syn.writefile) == 'function' then
      ok = pcall(syn.writefile, name, data)
      if ok then return end
    end
    if type(appendfile) == 'function' and type(isfile) == 'function' and not isfile(name) then
      pcall(appendfile, name, data)
      return
    end
    -- Fallback: print a short preview
    local preview = (type(data) == 'string' and data:sub(1, 160)) or tostring(data)
    print('[HOOK] captured len=', (type(data)=='string' and #data or -1), 'preview=', preview)
  end
  local oldX = __RT and __RT.X
  if type(oldX) == 'function' then
    __RT.X = function(src, ...)
      -- capture argument passed to loader
      pcall(try_write, ']]..dumpname..[[', src)
      return oldX(src, ...)
    end
  end
end

return __RT
]]

patched = patched .. hook

writefile(outpath, patched)
print("Patched and wrote:", outpath, "(dump target:", dumpname .. ")")

