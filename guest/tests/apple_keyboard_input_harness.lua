-- Run apple-keyboard-input.lua against a fake /proc/cmdline (arg[1]).
local cmdline = assert(arg[1], "cmdline required")
local overlay = assert(arg[2], "overlay path required")
local recorded = nil

hl = {
  get_config = function(key)
    local values = {
      ["input.kb_layout"] = arg[3] or "us",
      ["input.kb_variant"] = arg[4] or "",
      ["input.kb_options"] = arg[5] or "",
      ["input.kb_file"] = arg[6] or "",
    }
    return values[key]
  end,
  config = function(tbl)
    recorded = tbl
  end,
}

function io.open(path)
  if path == "/proc/cmdline" then
    return {
      read = function()
        return cmdline
      end,
      close = function() end,
    }
  end
  return nil
end

assert(loadfile(overlay))()

if recorded and recorded.input and recorded.input.kb_model then
  io.write(recorded.input.kb_model)
end

if arg[3] and recorded then
  io.write("|" .. (recorded.input.kb_options or "<preserved>"))
end
