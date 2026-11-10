local xcode = require("xcode")

-- mise also runs this hook for every platform it writes into mise.lock, so it
-- must not look at the machine it runs on. Finding the Xcode is left to
-- PostInstall.
function PLUGIN:PreInstall(ctx)
  local placeholder = xcode.lockfile_placeholder

  if not xcode.is_macos() then
    return {
      version = ctx.version,
      url = placeholder.url,
      sha256 = placeholder.sha256,
      note = "Skipping Xcode, which is only available on macOS",
    }
  end

  local version = xcode.resolve_version(ctx.version)
  if version == nil then
    error("No Xcode version exists that corresponds to " .. ctx.version .. ".")
  end

  return {
    version = version,
    url = placeholder.url,
    sha256 = placeholder.sha256,
    note = "Selecting a locally installed Xcode " .. version,
  }
end
