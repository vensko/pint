# Pint
Portable INsTaller - a manager of portable applications for Windows, which fits into a single file.

# Installation
To launch Pint, save [pint.cmd](https://github.com/vensko/pint/raw/master/pint.cmd) to a separate directory. Pint will create the following items:
- **packages.ini** *Pint's database file*
- **sources.list** *databases you are subscribed to*
- **apps** *a directory for your apps*
- **dist** *a directory for downloaded archives and installers*
All paths are customisable, see the "Environment Variables" chapter.
There are also hard dependencies, installed automatically, when needed:
- [7-zip](http://www.7-zip.org/) - file archiver supporting a wide range of formats,
- [Xidel](http://www.videlibri.de/xidel.html) - HTML/XML/JSON data extraction tool,
- [innoextract](http://constexpr.org/innoextract/) - a tool to unpack installers created by Inno Setup.

# Usage
```
pint <command> <parameters>
```
Available commands:
```
self-update
```
Self-explanatory. Updates Pint to the latest version.
```
update
```
Downloads all files listed in *sources.list* and combines them into *packages.ini*. Never edit *packages.ini* manually, your changes will be lost! Create a separate *packages.user.ini* file for custom packages.
```
search [<term>]
```
If the &lt;term&gt; is empty, yields a full list of packages from packages.ini.
If not, searches the databases for the term.
```
download <app> [<app>]
```
Downloads one or more apps into the *dist* directory without unpacking them. All downloaded packages are stored with filenames in the format &lt;app&gt;--&lt;architecture&gt;--&lt;actual-filename&gt;. Keep in mind, that the architecture attribute in Pint never refers to the actual bit count, but rather to a *preferred* value. If a 64-bit version of an app is not available yet and your processor is 64-bit, a 32-bit version will be downloaded and marked as 64. With a 64-bit version released, the app will be automatically upgraded from 32 to 64 bit.
```
install <app> [<app>]
```
Downloads an archive (or a few) with the given apps into *dist* and unpacks them into subdirectories with corresponding names under *apps*.
```
installto <app> <dir> [32|64]
```
Here comes is a twist. In fact, you deal with app identifiers only during their download and/or installation. After that, all commands refer to actual subdirectories in *apps*, e.g.:
*D:\Pint\apps\**firefox**
D:\Pint\apps\**foobar2000***
To keep things simple, you may use only the *install* command. This way, database identifiers and subdirectories will always be the same. But if you prefer storing your browser in *apps\Mozilla Firefox* instead of *apps\firefox*, this can be done with the *installto* command:
```
installto firefox "Mozilla Firefox"
```
FF will be installed into
*D:\Pint\apps\**Mozilla Firefox***
and from this point, it will have to be referred to as "Mozilla Firefox".
Optionally, a preferred bit count can set with the third parameter (this is useful if you need to force installation of a 32-bit version in a 64-bit system).
```
list
```
Shows a full list of installed apps, where each item contains an actual directory, an identifier, a version (if available), directory size and a preferred architecture.
```
l
```
Lists only apps directories without retrieving metadata. If the *list* table becomes too large, this may be a faster way to check directory names.
```
reinstall <dir> [<dir>]
```
Forces reinstallation of apps in the subdirectories.
```
remove <dir> [<dir>]
```
Removes the subdirectories. This is fully equivalent to manual deletion of the folders.
```
purge <dir> [<dir>]
```
Removes the subdirectories AND deletes corresponding archives from *dist*.
```
outdated [<dir> [<dir>]]
```
Checks for updates for apps in the subdirectories. With parameters omitted, Pint will check all installed apps.
```
upgrade [<dir> [<dir>]]
```
Checks for updates AND installs them if available. Same here, without parameters this will try to upgrade everything.
```
forget <dir> [<dir>]
```
Pint never touches subdirectories, where it hadn't install anything. Subdirectories with manually installed apps will simply be ignored. The *forget* command removed Pint's metadata from the subdirectories. To make them manageable again, use the *installto* command.
```
pin <dir> [<dir>]
```
Keeps Pint's metadata yet suppresses automatic updates for the apps.
```
unpin <dir> [<dir>]
```
Allows automatic updates (undoes the *pin* command).
```
subscribed
```
Shows a list of databases, you are subscribed to. By default, it contains a single item.
```
subscribe <url>
```
Adds the URL to the subscriptions. Basically, this has to be a direct link to an .ini file.
```
unsubscribe <url>
```
Removed the URL from subscriptions.

# Environment Variables
Certain parameters of Pint can be overriden with the following environment variables:
 - **PINT_APP_DIR** - absolute path to the *apps* directory.
 - **PINT_DIST_DIR** - absolute path to the *dist* directory.
 - **PINT_PACKAGES_FILE** - absolute path to packages.ini, including file name. This means, the file name can be changed as well.
 - **PINT_PACKAGES_FILE_USER** - absolute path to packages.user.ini, including file name.
 - **PINT_SRC_FILE** - absolute path to sources.list, including file name.
 - **PINT_USER_AGENT** - Pint's user agent.