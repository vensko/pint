# Pint
Portable INsTaller - a command line manager of portable applications for Windows, which fits into a single file.  
[Support forum](https://www.portablefreeware.com/forums/viewtopic.php?f=6&t=22888) at TPFC.

Pint is a tool for the people who prefer unpacking over installing. Its primary goal was to provide a way to easily manage a collection of portable apps. With the emergence of portabilizers like [yaP](http://rolandtoth.hu/yaP/), [PortableApps.com Platform](http://portableapps.com/platform/features) and other, focusing solely on the natively portable apps became irrelevant. Pint downloads and unpacks everything it can. At the moment it supports:
- Zip archives.
- MSI packages.
- All formats supported by 7-zip (7z, RAR, NSIS installers, etc.).
- Inno Setup installers.

# Features
- Downloads, unpacks and removes applications.
- Checks for updates and downloads them if available. Unlike Chocolatey and Scoop, Pint's databases do not require constant attention by humans. Pint will automatically detect, download and install an update once it becomes available on a website.
- Extracts download links from websites using [Xidel](http://www.videlibri.de/xidel.html).
- Supports RSS and PAD files as link sources.
- Unpacks various types of archives and installers and upgrades apps, keeping configuration files intact.
- Apps can be installed into arbitrary subdirectories under *apps*. This allows to keep yaP and PortableApps.com packages up to date.
- Automatically detects console applications and creates shim files for them in the *shims* directory.
- Can remember, if a 32-bit or a 64-bit application was installed.
- Can handle multiple installations of the same application.
- Detects app versions.
- Forms a report with installed applications.
- Can temporarily suppress updates for selected apps.
- Can update itself.
- Can use multiple local and remote databases, even choose not to use default ones.
- Allows to override paths and settings via environment variables.

# What Pint is not
- **Pint is not a portabilizer**, though it provides ways to manage portable apps more easily.
- Pint can't install a particular version of an app, only the latest, preferably portable, one. Though, it's often able to detect a version after installation.

# Installation
To install Pint, save [pint.cmd](https://github.com/vensko/pint/raw/master/pint.cmd) to a separate directory. By default, Pint will create the following items:
- **apps** *a directory for your apps*
- **apps\\.shims** *a directory for shims*
- **dist** *a directory for downloaded archives and installers*
- **deps** *a directory for Pint's dependencies*

All paths are customisable, see the [Environment variables](#environment-variables) chapter.

# Requirements
- Powershell 2.0+
- .NET Framework 2.0+  

Both are shipped with Windows 7+.

There are also hard dependencies, installed automatically when needed:
- [7-zip](http://www.7-zip.org/) - file archiver supporting a wide range of formats,
- [Xidel](http://www.videlibri.de/xidel.html) - HTML/XML/JSON data extraction tool,
- [innoextract](http://constexpr.org/innoextract/) - unpacks installers created by Inno Setup,
- [shimgen](https://github.com/chocolatey/choco/blob/master/src/chocolatey.resources/tools/shimgen.exe) - shim generator by Chocolatey team.

# Usage
```
pint <command> <parameters>
```

## Available commands

### `pint self-update`
Self-explanatory. Updates Pint to the latest version.

### `pint search [<term>]`
If `<term>` is empty, yields a full list of app IDs from all databases.  
If not, searches the databases for `<term>`.

Example: `pint search xnview`

### `pint download <app> [<app>]`
`<app>` is an ID from the `search` list. This downloads one or more apps into **dist** without unpacking them. All downloaded packages are stored with filenames in the format `<app>--<architecture>--<actual-filename>`.

Keep in mind, that the architecture attribute in Pint never refers to an actual bit count, but rather to a *preferred* value. If a 64-bit version of an app is not available yet and your processor is 64-bit, a 32-bit version will be downloaded and marked as 64. With a 64-bit version released, the app will be automatically upgraded from 32 to 64 bit.

Example: `pint download xnview foobar2000`

### `pint install <app> [<app>]`
Downloads an archive (or a few) into **dist** and unpacks them into subdirectories with corresponding names under **apps**.

Example: `pint install foobar2000`

### `pint installto <app> <dir> [32|64]`
Installs `<app>` into an arbitrary **apps** subdirectory. After installation, the app directory can be renamed or moved anywhere under **apps**, all installations are self-contained. Check `pint l` for a changed `<dir>` value.

Optionally, preferred bit count can be set with the third parameter (useful, if you need to force installation of a 32-bit version in a 64-bit system).

Example: `pint installto subtitle-workshop "Subtitle Workshop"`  
For more examples, see [this chapter](#custom-install-destinations-installto).

### `pint list`
Shows a full list of installed apps with some metadata.

### `pint l`
Lists only directories without retrieving metadata.  
If the `pint list` table becomes too large, this may be a faster way to check directory names.

### `pint reinstall <dir> [<dir>]`
Forces reinstallation of the apps.

Example: `pint reinstall foobar2000 "Subtitle Workshop"`

### `pint remove <dir> [<dir>]`
Removes the subdirectories. This is fully equivalent to manual deletion of the folders.

Example: `pint remove "Subtitle Workshop"`

### `pint purge <dir> [<dir>]`
Removes subdirectories AND corresponding archives from **dist**.

Example: `pint purge foobar2000 1by1`

### `pint cleanup`
Deletes all downloaded installers and archives from **dist**.

### `pint outdated [<dir> [<dir>]]`
Checks for updates for the apps. With parameters omitted, Pint will check all installed apps.

Example: `pint outdated 7-zip`

### `pint upgrade [<dir> [<dir>]]`
Checks for updates AND installs them if available. Same here, without parameters this will try to upgrade everything.

Example: `pint upgrade foobar2000 1by1 7-zip`

### `pint forget <dir> [<dir>]`
Pint never touches subdirectories, where it hadn't installed anything previously. Subdirectories with manually installed apps will simply be ignored. This command removes Pint's metadata from the subdirectories. To make them manageable again, use `installto`.

Example: `pint forget 7-zip`

### `pint pin <dir> [<dir>]`
Keeps Pint's metadata yet suppresses automatic updates for the apps.

Example: `pint pin 7-zip`

### `pint unpin <dir> [<dir>]`
Allows automatic updates (undoes `pin`).

Example: `pint unpin 7-zip`

### `pint shims`
Removes all shims files and recreates them.

### `pint test [<file.ini>|<app>] [32|64]`
Tests given file, URL or app ID. Verifies remote file availability, content type and reported content length.

Examples:  
`pint test "D:\my-packages.ini"`  
`pint test foobar2000`

### `pint info <app>`
Show package configuration.

### `pint unpack <file> <dir>`
Unpacks a file to a specified directory.

Example: `pint unpack "D:\foobar2000.zip" "D:\foobar2000"`

# Custom install destinations (installto)
Pint deals with app identifiers only during their download and/or installation. After that, all commands refer to actual subdirectories in **apps**, e.g.:
- apps\\**firefox**
- apps\\**foobar2000**

To keep things simple, you may use only the `install` command. This way, database identifiers and subdirectories will always be the same. But if you prefer storing your browser in *apps\Mozilla Firefox* instead of *apps\firefox*, this can be done with `installto`:
```
pint installto firefox "Mozilla Firefox"
```
FF will be installed into
- apps\\**Mozilla Firefox**

From this point, it will have to be referred to as "Mozilla Firefox":
```
pint outdated "Mozilla Firefox"
pint remove "Mozilla Firefox"
```

For another example, consider a yaP setup with the directory structure:
- apps\WinRAR\WinRARPortable.exe (yaP executable)
- apps\WinRAR\x86\
- apps\WinRAR\x64\  

To be able to manage this setup, run this:
```
pint installto winrar WinRAR\x86 32
pint installto winrar WinRAR\x64 64
```
Pint will handle both copies and update them using a correct archive.
As can be seen via the `list` command, they'll be referred to as *WinRAR\x86* and *WinRAR\x64* respectively:
```
pint pin WinRAR\x86
pint upgrade WinRAR\x64
```

Absolute paths outside **apps** are allowed. They will not be visible in `list` and not automatically included by `upgrade` or `outdated`, because there is no database tracking their locations. To manage them, you'll always have to use absolute paths, e.g.
```
pint installto imagine "E:\Total Commander\Plugins\Imagine"
pint upgrade "E:\Total Commander\Plugins\Imagine"
```

# Environment variables
Certain parameters of Pint can be overriden with the following environment variables. All paths must include names, therefore they can be renamed as well.
 - **PINT_APP_DIR** - absolute path to the *apps* directory.
 - **PINT_DIST_DIR** - absolute path to the *dist* directory.
 - **PINT_SHIM_DIR** - absolute path to the *shims* directory. If changed, recreate shim files with `pint shims`.
 - **PINT_DEPS_DIR** - absolute path to the *deps* directory.
 - **PINT_DB** - comma-separated list of file paths and URLs to .ini files with app definitions.
 - **PINT_USER_AGENT** - Pint's user agent.
 - **PINT_CACHE_TTL** - remote sources are updated once in %PINT_CACHE_TTL% hours, set to 0 to disable the cache.

The easiest way to override environment variables is to use a proxy .bat file with your parameters, something like this:
```
@echo off
SET "PINT_APP_DIR=D:\Apps"
call "D:\pint.cmd" %*
```

# Database
App definitions are described in INI format. File paths and URLs to .ini files are passed to Pint via the PINT_DB environment variable as a comma-separated list. Databases, registered by default:
- [https://d.vensko.net/pint/db/packages.ini](https://d.vensko.net/pint/db/packages.ini) - maintained by Pint's author in [this repository](https://github.com/vensko/pint-packages). Also includes automatically imported PortableApps.com and SyMenu databases.
- packages.user.ini - missing by default, can be used for custom app definitions.  

Feel free to override PINT_DB with your own app sources.

Alterntively, create a directory named 'packages' and add packages in separate files (one app per file, [example](https://github.com/vensko/pint-packages/tree/master/packages)).

## INI format
Each app is described in a separate section:
```
[app-id]
dist = http://example.com/dist.zip

[another-app-id]
dist = http://example.com/
link = x86, .zip
link64 = x64, .zip
keep = *.xml
```
Use lowercase strings without spaces as application identifiers. They must be unique, otherwise they may be overridden by an app with the same id.  

By default, new app definitions can be added to local file packages.user.ini.

## Available keys
Append *64* to a key to prefer it in a 64-bit system.
```
dist = http://example.com/archive.zip
dist64 = http://example.com/archive64.zip
```
If a key has no a 64-bit counterpart, base name will be used as a fallback.

### `dist`
If `link` is not defined, `data` is treated as a direct download URL to a file. If `link` is defined, the URL must point to a web page. The only mandatory key.

### `link`
Must be either a full XPath expression, starting with // and searching for &lt;a&gt; elements, or a comma-separated list of words, expected to be found in a download URL.  
**XPath example:** `//a[contains(@href, '.zip') and contains(@href, 'x86')]`  
**Simplified syntax:** `.zip, x86`  
To scan link texts, wrap words in quotes: `.zip, "portable"`  
Simplified queries are case-insensitive.

There are some meta-values:  
`.arch` means any of the most popular archive formats (at the moment, it includes .7z, .zip, .rar, and .paf.exe),  
`.any` is the same as `.arch` plus .exe.

Thanks to Xidel, JSON is supported. Consult [Xidel's documentation](http://www.videlibri.de/xidel.html#examples) (11. Reading JSON) on how to use the $json function. A few usage examples can also be found in [default database](https://d.vensko.net/pint/db/packages.ini).

### `follow`
When a download requires following through one or more web pages, set `follow` value to a list of consequent queries (same way as `link`), separated by |, leading to a page with a download link. `link` is still needed, when `follow` is set.  
Example: `"click here" | "go to download page"`

### `type`
Possible values:
- `standalone` - downloaded file will be considered an executable and will be copied as is with filename equal to app id.
- `inno` - force installer type to Inno Setup.
- `zip`, `cab`, etc. - any format, supported by 7-zip.

Usually, type enforcement is not needed, use it only when autodetection fails.

### `base`
A base path inside an archive. To better explain this, I better tell, how this works. Once the archive is unpacked into a temporary directory, the script switches to that directory and retrieves a list of files. Then it goes line by line, until the `base` substring is found (it doesn't have to be a valid file or directory path, can be just a fragment). Once this substring is encountered, the working path changes to the directory, containing the file, where the search stopped. *Parent* directory of that file/dir will become the base path.  
Default `base` value is `.exe`, which means, that the first encountered directory with an .exe file will be used.

### `keep`
Pint *replaces* contents of target directories, keeping files, listed in this parameter, intact. Typically, is used for configuration files. Must be a comma separated list of filenames/masks.  
Default value: `*.ini, *.db`.

### `only`
Comma-separated list of specific files/masks, which should be copied.

### `xd`, `xf`
Comma-separated lists of directores and files (respectively), which should be left behind. These files will be neither removed from a target directory, nor copied from a temporary one. Pint uses Robocopy to copy files. These parameters are used as values for its /XD and /XF parameters. If `only` is set, these parameters are ignored.

### `purge`
If set to `false`, Pint only copies new files to a target directory instead of full replacement (the /PURGE parameter for robocopy).

### `noshim`
Pint automatically detects console applications and creates shim files for them. Files, listed in `noshim`, will be skipped.

### `shim`
Sometimes console app detector misses them. Add file names/masks to `shim` to force shim creation for them.

### `create`
To enable portable mode, some applications require particular files to be created. These files can be listed in `create`.

### `method`
Set HTTP method for link request (GET by default).  

### `data`
If **method** is changed to POST, use this key to set custom payload in the x-www-form-urlencoded format.  

# Alternatives
- [Scoop](https://github.com/lukesampson/scoop)
- [Chocolatey](https://github.com/chocolatey/choco)
