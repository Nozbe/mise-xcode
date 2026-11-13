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

This resolves to the latest stable Xcode version known by the plugin. The plugin reads the Xcode versions and their builds from [xcodereleases.com](https://xcodereleases.com/), the list that xcodes also uses.

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

`mise lock` and `mise install --locked` work for `xcode` on every platform, whether the version comes from `mise.toml` or from an `.xcode-version` file. Locked mode needs mise 2026.11.7 or later, so require it in your project's `mise.toml`:

```toml
min_version = "2026.11.7"
```

Xcode is never downloaded, so the lockfile records only the version:

```toml
[[tools.xcode]]
version = "26.2.0"
backend = "vfox:xcode"
```

Installing an Xcode version on macOS needs access to xcodereleases.com. `mise lock` doesn't need the Xcode versions to be installed.

## Troubleshooting

### ```No Xcode <version> installation found within search path.```

The plugin was not able to find a valid Xcode installation for the provided version.

Make sure you have it installed and it's available inside the search path. By default, this plugin looks for Xcode installations with a search path of `/`, i.e. anywhere on your disk.

The plugin links each mise installation to the selected Xcode's `Contents/Developer` directory. If you move or rename the Xcode application after selecting it, refresh the link:

```bash
mise install --force xcode@<version>
```

### ```No lockfile URL found for xcode@<version> on platform <platform> (--locked mode)```

mise is older than 2026.11.7, which added locked mode for plugins that download nothing. Upgrade mise.

Lockfiles made with plugin versions before 2.0.0 record a placeholder `url` and `checksum` for `xcode` on each platform. They still work, with both old and new versions of mise. To drop the entries, delete the `xcode` entries from `mise.lock` and run `mise lock` again.

### `.xcode-version` is ignored on a new machine, or ```.../plugins/xcode/bin/install exited with non-zero status: no exit status```

mise before 2026.11.7 doesn't install the plugin from `[plugins]` before it reads the configuration. On a machine without the plugin, `mise install` and `mise lock` skip a version set in `.xcode-version` without an error, and `mise lock` records a version set in `mise.toml` with the wrong kind of plugin:

```toml
[[tools.xcode]]
backend = "asdf:https://github.com/Nozbe/mise-xcode"
```

Every installation from such a lockfile fails, including on machines that have the plugin. Upgrade mise, then lock again, which records `backend = "vfox:xcode"`:

```bash
mise lock
```

### ```No Xcode version exists that corresponds to <version>.```

According to the plugin, this Xcode version doesn't exist at all.

Double check that the Xcode version you're trying to use is accounted for at [xcodereleases.com](https://xcodereleases.com/).
