PLUGIN = {
  name = "xcode",
  version = "2.0.0",
  description = "Select an installed Xcode version by setting DEVELOPER_DIR",
  author = "qasim",
  homepage = "https://github.com/Nozbe/mise-xcode",
  license = "MIT",
  minRuntimeVersion = "0.3.0",
  -- Xcode is never downloaded. With this, `mise install --locked` (mise
  -- 2026.11.7 or later) installs xcode without a lockfile URL.
  downloads = false,
  legacyFilenames = {
    ".xcode-version",
  },
}
