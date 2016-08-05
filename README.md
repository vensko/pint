# Pint
Portable INsTaller - a command-line manager of portable applications for Windows, which fits into a single file.  
[Support forum](http://www.portablefreeware.com/forums/viewtopic.php?f=6&t=22888) at TPFC.  

Pint is a tool for the people who prefer unpacking over installing. Its primary goal was to provide a way to easily manage a collection of portable apps. With the emergence of portabilizers like [yaP](http://rolandtoth.hu/yaP/), [PortableApps.com Platform](http://portableapps.com/platform/features) and other, focusing solely on the natively portable apps became irrelevant. Pint downloads and unpacks everything it can. At the moment it supports:
- Zip archives.
- MSI packages.
- All formats supported by 7-zip (7z, RAR, NSIS installers, etc.).
- Inno Setup installers.

# Features
- Downloads, unpacks and removes applications.
- Checks for updates and downloads them if available.
- Extracts downloads links from websites using [Xidel](http://www.videlibri.de/xidel.html).
- Supports RSS and PAD files as link sources, has built-in routines to download from FileHippo, PortableApps.com and FossHub.
- Unpacks various types of archives and installers, and upgrades apps, keeping configuration files intact.
- Apps can be installed into arbitrary subdirectories under *apps*. This allows to keep yaP and PortableApps.com packages up to date.
- Automatically detects console applications and creates batch redirects for them in the *shims* directory.
- Can remember, if a 32-bit or a 64-bit application was installed.
- Can handle multiple installations of the same application.
- Detects app versions.
- Forms a report with installed applications.
- Can temporarily suppress updates for selected apps.
- Can update itself.
- Provides a way to subscribe to multiple remote databases, even choose not to use the default one.
- Is able to search across all subscribed databases.
- Allows to keep a custom user database in a separate file (by default, packages.user.ini).
- Allows to override paths and settings via environment variables.

# What Pint is not
- **Pint is not a portabilizer**, though it provides ways to manage portable apps more easily.
- Pint can't install a particular version of an app, only the latest, preferably portable, one. Though, it's often able to detect a version after installation.

# Installation
To install Pint, save [pint.cmd](https://github.com/vensko/pint/raw/master/pint.cmd) to a separate directory. By default, Pint will create the following items:
- **packages.ini** *Pint's database file*
- **sources.list** *databases you are subscribed to*
- **apps** *a directory for your apps*
- **dist** *a directory for downloaded archives and installers*  
- **shims** *a directory for shims*  

All paths are customisable, see the "Environment variables" chapter.  
  
There are also hard dependencies, installed automatically when needed:
- [7-zip](http://www.7-zip.org/) - file archiver supporting a wide range of formats,
- [Xidel](http://www.videlibri.de/xidel.html) - HTML/XML/JSON data extraction tool,
- [innoextract](http://constexpr.org/innoextract/) - a tool to unpack installers created by Inno Setup.

# Requirements
- Powershell 2.0+
- .NET Framework 2.0+  

Both are shipped with Windows 7+.

# Usage
```
pint <command> <parameters>
```

# Available commands
```
pint self-update
```
Self-explanatory. Updates Pint to the latest version.
```
pint update
```
Downloads all files listed in *sources.list* and combines them into *packages.ini*. Never edit *packages.ini* manually, your changes will be lost! Use a separate *packages.user.ini* file for custom packages.  
Also triggers *self-update*.
```
pint search [<term>]
```
If the &lt;term&gt; is empty, yields a full list of packages from packages.ini.  
If not, searches the database for the *term*.
```
pint download <app> [<app>]
```
Downloads one or more apps into *dist* without unpacking them. All downloaded packages are stored with filenames in the format *&lt;app&gt;--&lt;architecture&gt;--&lt;actual-filename&gt;*.  
Keep in mind, that the architecture attribute in Pint never refers to an actual bit count, but rather to a *preferred* value. If a 64-bit version of an app is not available yet and your processor is 64-bit, a 32-bit version will be downloaded and marked as 64. With a 64-bit version released, the app will be automatically upgraded from 32 to 64 bit.
```
pint install <app> [<app>]
```
Downloads an archive (or a few) into *dist* and unpacks them into subdirectories with corresponding names under *apps*.
```
pint installto <app> <dir> [32|64]
```
Installs the app into the given subdirectory.  
Optionally, a preferred bit count can be set with the third parameter (useful if you need to force installation of a 32-bit version in a 64-bit system).
```
pint list
```
Shows a full list of installed apps with some metadata.
```
pint l
```
Lists only directories without retrieving metadata. If the *list* table becomes too large, this may be a faster way to check directory names.
```
pint reinstall <dir> [<dir>]
```
Forces reinstallation of the apps.
```
pint remove <dir> [<dir>]
```
Removes the subdirectories. This is fully equivalent to manual deletion of the folders.
```
pint purge <dir> [<dir>]
```
Removes the subdirectories AND deletes corresponding archives from *dist*.
```
pint cleanup [<prefix> [<prefix>]]
```
Deleted installers. Optionally, prefixes of files to remove can be set.  
For instance, *pint cleanup python node* will remove all archives with names starting with python2, python3, node4 and node5.
```
pint outdated [<dir> [<dir>]]
```
Checks for updates for the apps. With parameters omitted, Pint will check all installed apps.
```
pint upgrade [<dir> [<dir>]]
```
Checks for updates AND installs them if available. Same here, without parameters this will try to upgrade everything.
```
pint forget <dir> [<dir>]
```
Pint never touches subdirectories, where it hadn't installed anything previously. Subdirectories with manually installed apps will simply be ignored. The *forget* command removes Pint's metadata from the subdirectories. To make them manageable again, use *installto*.
```
pint pin <dir> [<dir>]
```
Keeps Pint's metadata yet suppresses automatic updates for the apps.
```
pint unpin <dir> [<dir>]
```
Allows automatic updates (undoes *pin*).
```
pint subscribed
```
Shows a list of databases, that you are subscribed to.
```
pint subscribe <url>
```
Adds the URL to the subscriptions. Basically, this has to be a direct link to an .ini file.
```
pint unsubscribe <url>
```
Removes the URL from subscriptions.

# Custom install destinations (installto)
In fact, Pint deals with app identifiers only during their download and/or installation. After that, all commands refer to actual subdirectories in *apps*, e.g.:  
D:\Pint\apps\\**firefox**  
D:\Pint\apps\\**foobar2000**  
To keep things simple, you may use only the *install* command. This way, database identifiers and subdirectories will always be the same. But if you prefer storing your browser in *apps\Mozilla Firefox* instead of *apps\firefox*, this can be done with *installto*:
```
pint installto firefox "Mozilla Firefox"
```
FF will be installed into  
D:\Pint\apps\\**Mozilla Firefox**  
From this point, it will have to be referred to as "Mozilla Firefox".  

For another example, consider a yaP setup with the directory structure:
- apps\WinRAR\WinRARPortable.exe (yaP executable)
- apps\WinRAR\x86\
- apps\WinRAR\x64\  

To be able to manage this setup, run this:
```
pint installto winrar WinRAR\x86 32
pint installto winrar WinRAR\x64 64
```
Pint will handle handle both copies and update them using a correct archive.  
As can be seen via the *list* command, they'll be referred to as WinRAR\x86 and WinRAR\x64 respectively.

# Environment variables
Certain parameters of Pint can be overriden with the following environment variables. All paths must include names, therefore they can be renamed as well.
 - **PINT_APP_DIR** - absolute path to the *apps* directory.
 - **PINT_DIST_DIR** - absolute path to the *dist* directory.
 - **PINT_SHIM_DIR** - absolute path to the *shims* directory.
 - **PINT_PACKAGES_FILE** - absolute path to packages.ini.
 - **PINT_PACKAGES_FILE_USER** - absolute path to packages.user.ini.
 - **PINT_SRC_FILE** - absolute path to sources.list.
 - **PINT_USER_AGENT** - Pint's user agent.

# INI format
The apps database is located in packages.ini (%PINT_PACKAGES_FILE%). This file is being overwritten upon every update and should never be edited manually. Use a separate *packages.user.ini* (%PINT_PACKAGES_FILE_USER%) file for custom configuration.  
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

**Available keys**

**dist** - if **link** is not defined, **data** is treated as a direct download URL to a file. If **link** is defined, the URL must point to a web page. The only mandatory key.

**link** - must be either a full XPath expression, starting with // and searching for &lt;a&gt; elements, or a comma-separated list of words, expected to be found in a download URL.  
**XPath example:** *//a[contains(@href, '.zip') and contains(@href, 'x86')]*  
**Simplified syntax:** *.zip, x86*  
To scan link texts, wrap words in quotes: *.zip, "portable"*  
Simplified queries are case-insensitive.  
  
There are some meta-values:  
**.arch** means any of the most popular archive formats (at the moment, it includes .7z, .zip, .rar, and .paf.exe),  
**.any** is the same as .arch plus .exe.  
  
**type** - all downloaded files are considered archives, unless this parameter is set. Currently, the only possible value is *standalone*, which means the downloaded file will be copied as is without unpacking.

**base** - a base path inside an archive. To better explain this, I better tell, how this works. Once the archive is unpacked into a temporary directory, the script switches to that directory and retrieves a list of files. Then it goes line by line, until the **base** substring is found (it doesn't have to be a valid file or directory path, can be just a fragment). Once this substring is encountered, the working path changes to the directory, containing the file, where the search stopped. That's right, a *parent* directory of that file/dir will become the base path. Default **base** value is *.exe*, which means, that the first encountered directory with an .exe file will be used.

**keep** - Pint *replaces* contents of target directories, keeping files, listed in this parameter, intact. Typically, is used for configuration files. Must be a comma separated list of filenames/masks. Default value - \*.ini, \*.db.

**only** - comma-separated list of files/masks, which should be copied. Useful for highly customizable apps, which typically contain a lot of custom assets - themes, plugins, etc.

**xd**, **xf** - comma-separated lists of directores and files (respectively), which should be left behind. These files will be neither removed from a target directory, nor copied from a temporary one. Pint uses Robocopy to copy files. These parameters are used as values for its /XD and /XF parameters. If **only** is set, these parameters are ignored.

**noshim** - Pint automatically detects console applications and creates batch redirects for them (this is a temporary solution). Files, listed in **noshim**, will be skipped.

Append *64* to a key to prefer it in a 64-bit system.  
dist = http://example.com/archive.zip  
dist64 = http://example.com/archive64.zip  
If a key has no a 64-bit counterpart, base name will be used as a fallback.

# Alternatives
- [Scoop](https://github.com/lukesampson/scoop)
- [Chocolatey](https://github.com/chocolatey/choco)