# Pint
Portable INsTaller - a package manager for Windows, which fits into a single batch file

# Usage
```
pint <command> <parameters>
```
Available commands:
```
self-update        Update Pint.
update             Download package databases and combine them into packages.ini.
search [<term>]    Search for an app in the database, or show all items.
subscribed         Show the list of databases, you are subscribed to.
subscribe <url>    Add a subscription to a package database.
                   Essentially, it has to be a direct URL of an .ini file.
unsubscribe <url>  Remove the URL from the list of subscriptions.
list               Show all applications installed via Pint.
outdated [<path>]  Check for updates for all or some packages by your choice.
upgrade [<path>]   Install updates for all or selected apps.
pin <path>         Suppress updates for selected apps.
unpin <path>       Allow updates for selected apps.
remove <path>      Delete selected apps (this is equivalent to manual deletion).
purge <path>       Delete selected apps AND their installers.
forget <path>      Stop tracking of selected apps.
download <app>     Only download selected installers without unpacking them.
installto <app> <path> Install the app to the given path.
install <app>      Install one or more apps to directories with the same names.
reinstall <path>   Force reinstallation of the package.
```

<app> refers to an ID from the database, which can be seen via the search command.
<path> refers to a relative path to an app in the 'apps' directory as shown by the list command.