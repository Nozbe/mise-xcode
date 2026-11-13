local cmd = require("cmd")
local http = require("http")
local json = require("json")

local xcode = {}

-- The list of Xcode releases that xcodes also uses: each release's version,
-- build and download link.
xcode.releases_url = "https://xcodereleases.com/data.json"

-- Plugin versions before 2.0.0 had mise download this placeholder in locked
-- mode, and lockfiles made with them still record its URL. mise before
-- 2026.11.7 still downloads it into the install directory, so PostInstall
-- removes it.
xcode.lockfile_placeholder_name = "lockfile-placeholder.txt"

local records_cache = nil
local records_by_version_cache = nil

-- Xcode only exists on macOS. Elsewhere the plugin installs nothing and sets no
-- environment, so a project can list xcode in a config shared with other platforms.
function xcode.is_macos()
  return tostring(RUNTIME.osType):lower() == "darwin"
end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function command_succeeds(command)
  return pcall(function()
    cmd.exec(command, { timeout = 10000 })
  end)
end

local function path_exists(path)
  return command_succeeds("test -e " .. shell_quote(path)) or command_succeeds("test -L " .. shell_quote(path))
end

local function path_is_symlink(path)
  return command_succeeds("test -L " .. shell_quote(path))
end

local function symlink_target(path)
  local ok, target = pcall(function()
    return cmd.exec("readlink " .. shell_quote(path), { timeout = 10000 })
  end)
  if ok then
    return trim(target)
  end
  return nil
end

local function split_lines(value)
  local lines = {}
  for line in tostring(value or ""):gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  return lines
end

local function path_is_within(path, parent)
  local normalized_parent = tostring(parent or "/"):gsub("/+$", "")
  if normalized_parent == "" then
    normalized_parent = "/"
  end

  return normalized_parent == "/"
    or path == normalized_parent
    or path:sub(1, #normalized_parent + 1) == normalized_parent .. "/"
end

local function selected_xcode_bundle_path(search_path)
  local ok, output = pcall(function()
    return cmd.exec("/usr/bin/xcode-select -p", { timeout = 10000 })
  end)
  if not ok then
    return nil
  end

  local developer_dir = trim(output):gsub("/+$", "")
  local bundle_path = developer_dir:match("^(.*%.app)/Contents/Developer$")
  if bundle_path == nil or not path_is_within(bundle_path, search_path or "/") then
    return nil
  end

  return bundle_path
end

local function parse_version(version)
  local base, prerelease = version:match("^([%d%.]+)%-?(.*)$")
  local parts = {}
  for part in tostring(base or ""):gmatch("%d+") do
    table.insert(parts, tonumber(part))
  end
  return parts, prerelease ~= "" and prerelease or nil
end

local function compare_versions(left, right)
  local left_parts, left_prerelease = parse_version(left)
  local right_parts, right_prerelease = parse_version(right)

  for i = 1, math.max(#left_parts, #right_parts) do
    local left_part = left_parts[i] or 0
    local right_part = right_parts[i] or 0
    if left_part ~= right_part then
      return left_part - right_part
    end
  end

  if left_prerelease == nil and right_prerelease ~= nil then
    return 1
  end
  if left_prerelease ~= nil and right_prerelease == nil then
    return -1
  end
  if left_prerelease == nil and right_prerelease == nil then
    return 0
  end
  if left_prerelease == right_prerelease then
    return 0
  end
  return left_prerelease > right_prerelease and 1 or -1
end

local function compare_natural(left, right)
  local left_tokens = {}
  local right_tokens = {}

  for token in tostring(left):gmatch("%d+%D*") do
    local number, suffix = token:match("^(%d+)(%D*)$")
    table.insert(left_tokens, { number = tonumber(number), suffix = suffix })
  end
  for token in tostring(right):gmatch("%d+%D*") do
    local number, suffix = token:match("^(%d+)(%D*)$")
    table.insert(right_tokens, { number = tonumber(number), suffix = suffix })
  end

  for i = 1, math.max(#left_tokens, #right_tokens) do
    local left_token = left_tokens[i]
    local right_token = right_tokens[i]
    if left_token == nil then
      return -1
    end
    if right_token == nil then
      return 1
    end
    if left_token.number ~= right_token.number then
      return left_token.number - right_token.number
    end
    if left_token.suffix ~= right_token.suffix then
      return left_token.suffix > right_token.suffix and 1 or -1
    end
  end

  return 0
end

-- Returns the releases, or nil and an error message. Callers can't catch errors
-- with pcall here, because mise's http module yields, which isn't allowed inside
-- pcall. When the server can't be reached at all, mise raises the error itself.
local function fetch_releases()
  local failure = "Failed to download the list of Xcode releases from " .. xcode.releases_url .. ": "

  local resp, err = http.get({ url = xcode.releases_url })
  if err ~= nil or resp == nil then
    return nil, failure .. tostring(err)
  end
  if resp.status_code ~= 200 then
    return nil, failure .. "HTTP status " .. tostring(resp.status_code)
  end

  local ok, releases = pcall(json.decode, resp.body)
  if not ok or type(releases) ~= "table" then
    return nil, failure .. "the response is not valid JSON"
  end
  return releases
end

local function list_releases()
  local releases, err = fetch_releases()
  if releases ~= nil then
    return releases
  end

  -- Off macOS the versions are never used to find an Xcode, so a failed
  -- download doesn't fail the run.
  if not xcode.is_macos() then
    return {}
  end
  error(err)
end

-- How each kind of xcodereleases.com release appears in this plugin's versions.
-- Stable and GM releases have no prerelease identifier. Kinds missing here, such
-- as developer previews, are left out rather than mistaken for stable releases.
local release_kinds = {
  release = "",
  gm = "",
  rc = "rc",
  beta = "beta",
  gmSeed = "seed",
}

-- Converts an xcodereleases.com release into a record with this plugin's version
-- format, e.g. Xcode 26.3 RC 2 becomes 26.3.0-rc.2. Returns nil for releases the
-- plugin doesn't offer: other products, and Xcode versions older than 8.
local function release_record(release)
  if type(release) ~= "table" or release.name ~= "Xcode" then
    return nil
  end
  local release_version = release.version
  if type(release_version) ~= "table" or type(release_version.release) ~= "table" then
    return nil
  end

  local number = tostring(release_version.number or "")
  local build = release_version.build
  if not number:match("^%d+$") and not number:match("^%d+%.%d+$") and not number:match("^%d+%.%d+%.%d+$") then
    return nil
  end
  if type(build) ~= "string" or build == "" or tonumber(number:match("^%d+")) < 8 then
    return nil
  end

  local dot_count = select(2, number:gsub("%.", ""))
  local version = number .. string.rep(".0", 2 - dot_count)

  -- Prerelease kinds are checked first, so a release that is also marked
  -- stable keeps its prerelease identifier.
  local kind = nil
  for _, name in ipairs({ "rc", "beta", "gmSeed", "gm", "release" }) do
    if release_version.release[name] ~= nil then
      kind = name
      break
    end
  end
  if kind == nil then
    return nil
  end

  local prerelease = release_kinds[kind]
  if prerelease ~= "" then
    version = version .. "-" .. prerelease
    local index = release_version.release[kind]
    if type(index) == "number" and index > 1 then
      version = version .. "." .. string.format("%d", index)
    end
  end

  local links = type(release.links) == "table" and release.links or {}
  local download = type(links.download) == "table" and links.download or {}

  return {
    version = version,
    build = build,
    download_url = type(download.url) == "string" and download.url or nil,
  }
end

local function load_records()
  if records_cache ~= nil then
    return records_cache, records_by_version_cache
  end

  local by_version = {}
  for _, release in ipairs(list_releases()) do
    local record = release_record(release)
    if record ~= nil then
      by_version[record.version] = by_version[record.version] or {}
      table.insert(by_version[record.version], record)
    end
  end

  local records = {}
  for _, version_records in pairs(by_version) do
    table.sort(version_records, function(left, right)
      return compare_natural(left.build, right.build) > 0
    end)
    table.insert(records, version_records[1])
  end
  table.sort(records, function(left, right)
    return compare_versions(left.version, right.version) > 0
  end)

  records_cache = records
  records_by_version_cache = by_version
  return records_cache, records_by_version_cache
end

local function latest_records()
  local records = load_records()
  return records
end

local function records_for_version(version)
  local _, by_version = load_records()
  return by_version[version] or {}
end

function xcode.available_versions()
  local result = {}
  for _, record in ipairs(latest_records()) do
    table.insert(result, {
      version = record.version,
      note = "build " .. record.build,
    })
  end
  return result
end

function xcode.record_for_version(version, search_path)
  local records = records_for_version(version)
  for _, record in ipairs(records) do
    if xcode.find_developer_dir(record.build, search_path) ~= nil then
      return record
    end
  end

  return records[1]
end

function xcode.latest_stable_version()
  for _, record in ipairs(latest_records()) do
    if record.version:find("-", 1, true) == nil then
      return record.version
    end
  end
  return nil
end

function xcode.resolve_version(version)
  if version == "latest" then
    return xcode.latest_stable_version()
  end

  for _, record in ipairs(latest_records()) do
    if record.version == version then
      return record.version
    end
    if record.version:sub(1, #version + 1) == version .. "." then
      return record.version
    end
  end

  return nil
end

function xcode.build_for_version(version, search_path)
  local resolved_version = xcode.resolve_version(version)
  if resolved_version == nil then
    error("No Xcode version exists that corresponds to " .. version .. ".")
  end

  local record = xcode.record_for_version(resolved_version, search_path)
  if record == nil then
    error("No Xcode version exists that corresponds to " .. version .. ".")
  end

  return record.build, record.version, record
end

local function xcode_bundle_paths(search_path)
  local query = "kMDItemCFBundleIdentifier='com.apple.dt.Xcode'"
  local output =
    cmd.exec("mdfind -onlyin " .. shell_quote(search_path or "/") .. " " .. shell_quote(query), { timeout = 30000 })
  return split_lines(output)
end

local function product_build_version(bundle_path)
  local plist_path = bundle_path .. "/Contents/version.plist"
  local output = cmd.exec(
    "/usr/libexec/PlistBuddy -c " .. shell_quote("print 'ProductBuildVersion'") .. " " .. shell_quote(plist_path),
    { timeout = 10000 }
  )
  return trim(output)
end

function xcode.find_developer_dir(build, search_path)
  local selected_bundle_path = selected_xcode_bundle_path(search_path or "/")
  if selected_bundle_path ~= nil then
    local ok, selected_build = pcall(product_build_version, selected_bundle_path)
    if ok and selected_build == build then
      return selected_bundle_path .. "/Contents/Developer"
    end
  end

  for _, bundle_path in ipairs(xcode_bundle_paths(search_path or "/")) do
    if product_build_version(bundle_path) == build then
      return bundle_path .. "/Contents/Developer"
    end
  end

  return nil
end

function xcode.require_developer_dir(version, build, search_path, record)
  local developer_dir = xcode.find_developer_dir(build, search_path)
  if developer_dir == nil then
    local message = "No Xcode " .. version .. " installation found within search path."
    if record ~= nil and record.download_url ~= nil then
      message = message .. "\nInstall it from: " .. record.download_url
    end
    error(message)
  end
  return developer_dir
end

function xcode.remove_lockfile_placeholder(install_path)
  os.remove(install_path .. "/" .. xcode.lockfile_placeholder_name)
end

-- Points the install directory's Developer link at the selected Xcode. The
-- install directory itself must stay a real directory: mise writes its own files
-- into it after PostInstall, and they must not end up inside the Xcode bundle.
function xcode.link_developer_dir(install_path, developer_dir)
  -- Earlier versions of the plugin replaced the install directory itself with a
  -- link to Xcode, so a reinstall over one of those turns it back into a directory.
  if path_is_symlink(install_path) then
    cmd.exec("rm -f " .. shell_quote(install_path), { timeout = 10000 })
  end
  cmd.exec("mkdir -p " .. shell_quote(install_path), { timeout = 10000 })

  local link_path = install_path .. "/Developer"
  if path_exists(link_path) then
    cmd.exec("rm -f " .. shell_quote(link_path), { timeout = 10000 })
  end
  cmd.exec("ln -s " .. shell_quote(developer_dir) .. " " .. shell_quote(link_path), { timeout = 10000 })
end

function xcode.read_build_file(path)
  local file = require("file")
  return trim(file.read(path .. "/BUILD"))
end

function xcode.developer_dir_for_install(path, search_path)
  -- Installs from earlier versions of the plugin link the install directory
  -- itself to Xcode.
  if path_is_symlink(path) then
    return symlink_target(path) or path
  end

  -- Installs older still only recorded the Xcode build, so the link is created
  -- here. The broken-link fallback deliberately keeps DEVELOPER_DIR
  -- version-specific, so a removed Xcode cannot silently fall back to another
  -- installation.
  local link_path = path .. "/Developer"
  if path_exists(link_path) then
    return symlink_target(link_path) or link_path
  end

  local build_ok, build = pcall(xcode.read_build_file, path)
  local developer_dir = nil
  if build_ok and build ~= "" then
    local find_ok, result = pcall(xcode.find_developer_dir, build, search_path)
    if find_ok then
      developer_dir = result
    end
  end

  local target = developer_dir or (path .. "/Xcode-not-installed")
  command_succeeds("ln -s " .. shell_quote(target) .. " " .. shell_quote(link_path))

  if path_exists(link_path) then
    return symlink_target(link_path) or link_path
  end
  return developer_dir or link_path
end

-- Prerelease names xcodes understands, mapped to the identifiers used by
-- this plugin's versions.
local xcode_version_prereleases = {
  ["b"] = "beta",
  ["beta"] = "beta",
  ["rc"] = "rc",
  ["release candidate"] = "rc",
  ["gm seed"] = "seed",
}

-- Converts the contents of an `.xcode-version` file into this plugin's version
-- format, reading it the way xcodes does: the number is exact ("26" and "26.0"
-- both mean 26.0.0) and prereleases use Apple's names ("14.0b6" and
-- "14.0 Beta 6" both mean 14.0.0-beta.6). Returns nil for anything else.
function xcode.parse_xcode_version_file(content)
  local line = trim(tostring(content or ""):match("^%s*([^\r\n]*)")):lower():gsub("^xcode%s+", "")

  local number, rest = line:match("^(%d[%d%.]*)(.*)$")
  if number == nil or number:find("..", 1, true) or number:sub(-1) == "." then
    return nil
  end

  local parts = {}
  for part in number:gmatch("%d+") do
    table.insert(parts, tostring(tonumber(part)))
  end
  if #parts > 3 then
    return nil
  end
  while #parts < 3 do
    table.insert(parts, "0")
  end
  local version = table.concat(parts, ".")

  rest = trim(rest:gsub("%s+", " "))
  if rest == "" then
    return version
  end

  local name, index = rest:match("^(%a[%a ]-) ?(%d*)$")
  local prerelease = name and xcode_version_prereleases[name]
  if prerelease == nil then
    return nil
  end

  version = version .. "-" .. prerelease
  if index ~= "" and tonumber(index) > 1 then
    version = version .. "." .. tonumber(index)
  end
  return version
end

function xcode.context_field(ctx, key, fallback)
  local ok, value = pcall(function()
    return ctx[key]
  end)
  if ok and value ~= nil then
    return value
  end
  return fallback
end

return xcode
