local xcode = require("xcode")

-- mise also runs this hook for every platform it writes into mise.lock, so it
-- must not look at the machine it runs on. Finding the Xcode is left to
-- PostInstall. It returns no url: metadata.lua sets `downloads = false`, and
-- mise stops the install if such a plugin returns one.
function PLUGIN:PreInstall(ctx)
  if not xcode.is_macos() then
    return {
      version = ctx.version,
      note = "Skipping Xcode, which is only available on macOS",
    }
  end

  local version = xcode.resolve_version(ctx.version)
  if version == nil then
    error("No Xcode version exists that corresponds to " .. ctx.version .. ".")
  end

  return {
    version = version,
    note = "Selecting a locally installed Xcode " .. version,
  }
end
