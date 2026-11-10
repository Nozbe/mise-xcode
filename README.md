# mise-xcode

Xcode plugin for the [Mise](https://github.com/jdx/mise) version manager.

> [!NOTE]
> This plugin manages your actively selected Xcode version, but does not take the responsibility of downloading or installing Xcode versions themselves.

## Install

### Option 1: Specify the plugin inside your project's [configuration](https://mise.jdx.dev/configuration.html)

```toml
[plugins]
xcode = 'https://github.com/Nozbe/mise-xcode'
```

### Option 2: Install the plugin globally

```bash
mise plugins install xcode https://github.com/Nozbe/mise-xcode
```

## Use

### Selecting the latest stable version of Xcode

```bash
mise use xcode@latest
```

or

```toml
[tools]
xcode = 'latest'
```

This resolves to the latest stable Xcode version known by the plugin.

### Selecting a specific version of Xcode

```toml
[tools]
xcode = '16.0.0'
```

### Selecting the latest stable version of a major Xcode

Using version `26` will select the latest stable `26.x.y` release known by the plugin.

```console
foo@bar:~$ mise use xcode@26
mise ~/foo/bar/mise.toml tools: xcode@26.5.0
```

### Selecting a version with an `.xcode-version` file

The plugin can read the version from an `.xcode-version` file, the format used by [xcodes](https://github.com/XcodesOrg/xcodes) and [fastlane](https://docs.fastlane.tools/actions/xcodes/).
mise only reads idiomatic version files for tools you opt in, so enable it for `xcode` first:

```bash
mise settings add idiomatic_version_file_enable_tools xcode
```

Then, in your project:

```console
foo@bar:~$ echo "26.2" > .xcode-version
foo@bar:~$ mise current xcode
26.2.0
```

The file is read the way xcodes reads it, so the version it names is exact:

| `.xcode-version` | Resolved version |
| --- | --- |
| `26`, `26.0` | `26.0.0` |
| `26.0.1`, `Xcode 26.0.1` | `26.0.1` |
| `14.0b6`, `14.0 Beta 6` | `14.0.0-beta.6` |
| `26.3 RC 2`, `26.3 Release Candidate 2` | `26.3.0-rc.2` |
| `10.2 GM seed` | `10.2.0-seed` |

This differs from versions in `mise.toml`, where `xcode = '26.0'` follows mise's usual prefix matching and selects the latest `26.0.x` release.
Anything else in the file is used as written, e.g. `26.0.0-beta.3`.

### Selecting Xcodes within a specific search path

By default, this plugin looks for Xcode installations with a search path of `/`, i.e. anywhere on your disk.
You can specify a custom search path via the `search_path` parameter:

```toml
[tools]
xcode = {version='16.0.0', search_path='/Applications'}
```

### Using a shared configuration on other platforms

Xcode is only available on macOS. On other platforms the plugin does nothing: `mise install` succeeds without looking for Xcode and `DEVELOPER_DIR` is not set, so `xcode` can stay in a `mise.toml` that is also used on Linux or Windows.

### Using a lockfile

`mise lock` and `mise install --locked` work for `xcode` on every platform, whether the version comes from `mise.toml` or from an `.xcode-version` file.

mise's locked mode only installs a tool from a plugin when `mise.lock` records a download URL and checksum for it. Xcode is never downloaded, so the plugin gives mise a placeholder instead: [`lockfile-placeholder.txt`](lockfile-placeholder.txt), pinned to the commit that added it. mise downloads it into the install directory, and the plugin removes it again. The lockfile entries look like this:

```toml
[tools.xcode."platforms.macos-arm64"]
checksum = "sha256:b7602d41f4c6e3c47f9e9369609932b4958e589a9a36c93418fcbbe946e338d3"
url = "https://raw.githubusercontent.com/Nozbe/mise-xcode/bced723a7733cde1049d0fef0d6ccd96caed019b/lockfile-placeholder.txt"
```

Installing an Xcode version therefore needs access to GitHub, even though nothing is installed from there. `mise lock` doesn't need the Xcode versions to be installed.

## Troubleshooting

### ```No Xcode <version> installation found within search path.```

The plugin was not able to find a valid Xcode installation for the provided version.

Make sure you have it installed and it's available inside the search path. By default, this plugin looks for Xcode installations with a search path of `/`, i.e. anywhere on your disk.

The plugin links each mise installation to the selected Xcode's `Contents/Developer` directory. If you move or rename the Xcode application after selecting it, refresh the link:

```bash
mise install --force xcode@<version>
```

### ```No lockfile URL found for xcode@<version> on platform <platform> (--locked mode)```

Either `mise.lock` or the installation was created by an earlier version of the plugin, which didn't support locked mode:

- If the `xcode` entries in `mise.lock` have no `url`, run `mise lock` to add them.
- If `mise install --force --locked` fails for an Xcode that is already installed, reinstall it once without locked mode:

  ```bash
  mise install --force xcode@<version>
  ```

### ```No Xcode version exists that corresponds to <version>.```

According to the plugin, this Xcode version doesn't exist at all.

Double check that the Xcode version you're trying to use is accounted for at [xcodereleases.com](https://xcodereleases.com/).
