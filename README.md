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

All paths are customisable, see the [Environment variables](https://github.com/vensko/pint/wiki/Environment-Variables) chapter.

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

# More
- [Environment Variables](https://github.com/vensko/pint/wiki/Environment-Variables)
- [Database How To](https://github.com/vensko/pint/wiki/Database-How-To)

# Alternatives
- [Scoop](https://github.com/lukesampson/scoop)
- [Chocolatey](https://github.com/chocolatey/choco)
