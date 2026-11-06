local file = require("file")
local xcode = require("xcode")

function PLUGIN:ParseLegacyFile(ctx)
  local content = file.read(ctx.filepath)
  local version = xcode.parse_xcode_version_file(content)

  -- mise ignores errors raised here, so unrecognized contents are passed
  -- through as written and installing them fails with a visible error.
  -- mise splits the returned version on whitespace, so it is removed first.
  if version == nil then
    version = tostring(content or ""):match("^%s*([^\r\n]*)"):gsub("%s+", "")
  end

  return {
    version = version,
  }
end
