<# : Batch/PowerShell hybrid
@echo off
if "%~1"=="" call "%~f0" usage && exit /b 0
@setlocal enabledelayedexpansion

rem PINT - Portable INsTaller
rem https://github.com/vensko/pint

SET PINT="%~f0"

rem Set variables if they weren't overriden earlier
if not defined PINT_DIST_DIR set "PINT_DIST_DIR=%~dp0packages"
if not defined PINT_APPS_DIR set "PINT_APPS_DIR=%~dp0apps"
if not defined PINT_PACKAGES_FILE set PINT_PACKAGES_FILE="%~dp0packages.ini"
if not defined PINT_PACKAGES_FILE_USER set PINT_PACKAGES_FILE_USER="%~dp0packages.user.ini"
if not defined PINT_SRC_FILE set PINT_SRC_FILE="%~dp0sources.list"
if not defined PINT_TEMP_FILE set PINT_TEMP_FILE="%TEMP%\pint.tmp"
if not defined PINT_USER_AGENT (
	set "PINT_USER_AGENT=User-Agent: Mozilla/5.0 ^(Windows NT 6.1; rv:40.0^) Gecko/20100101 Firefox/40.1"
)

rem PowerShell
for %%x in (usage shim download-file unzip) do (
	if "%~1"=="%%x" (
		SET "_COMMAND=%~1"
		if not "%~2"=="" SET "_PARAM_1=%~2"
		if not "%~3"=="" SET "_PARAM_2=%~3"
		if not "%~4"=="" SET "_PARAM_3=%~4"
		if not "%~5"=="" SET "_PARAM_4=%~5"
		powershell -NonInteractive -NoLogo -NoProfile -executionpolicy bypass "iex (${%~f0} | out-string)"
		exit /b !ERRORLEVEL!
	)
)

path %PINT_APPS_DIR%;%PATH%

rem Hardcoded URLs
set "PINT_PACKAGES=https://raw.githubusercontent.com/vensko/pint/master/packages.ini"
set "PINT_SELF_URL=https://raw.githubusercontent.com/vensko/pint/master/pint.bat"

SET FINDSTR="%WINDIR%\system32\findstr.exe"
SET FIND="%WINDIR%\system32\find.exe"
SET SORT="%WINDIR%\system32\sort.exe"
SET FORFILES="%WINDIR%\system32\forfiles.exe"
SET MSIEXEC="%WINDIR%\system32\msiexec.exe"
SET ROBOCOPY="%WINDIR%\system32\robocopy.exe"

SET CURL=curl --insecure --ssl-no-revoke --ssl-allow-beast --progress-bar --remote-header-name --location
SET CURL=%CURL% --create-dirs --fail --max-redirs 5 --retry 2 --retry-delay 1 -X GET

rem Create directories if needed
if not exist "%PINT_APPS_DIR%" md "%PINT_APPS_DIR%"

call :_has xidel || ( echo Unable to install Xidel.&&	exit /b 1 )
call :_has 7z 7-zip || ( echo Unable to install 7-zip.&& exit /b 1 )
call :_has curl || ( echo Unable to install curl.&& exit /b 1 )

rem Functions accessible directly from the command line
SET BAT_FUNCTIONS=self-update update subscribe subscribed install reinstall list unsubscribe dir tracked
SET BAT_FUNCTIONS=%BAT_FUNCTIONS% download remove purge upgrade search outdated pin unpin installto

for %%x in (%BAT_FUNCTIONS%) do (
	if "%~1"=="%%x" (
		call :%*
		exit /b !ERRORLEVEL!
	)
)

echo Unknown command.
exit /b 1


rem *****************************************
rem  FUNCTIONS
rem *****************************************


:self-update
:: Update Pint.
	echo Fetching %PINT_SELF_URL%

	if exist %PINT_TEMP_FILE% del %PINT_TEMP_FILE%

	"%ComSpec%" /d /c %CURL% -s -S -o %PINT_TEMP_FILE% "%PINT_SELF_URL%" && (
		>nul %FINDSTR% /L /C:"PINT - Portable INsTaller" %PINT_TEMP_FILE% && (
			>nul move /Y %PINT_TEMP_FILE% %PINT% && (
				echo Pint was updated to the latest version.
				exit /b 0
			)
		)
	)

	echo Self-update failed^^!
	exit /b 1


:update
:: Download package databases and combine them into packages.ini.
	echo Updating the database...

	if not exist %PINT_SRC_FILE% >%PINT_SRC_FILE% echo %PINT_PACKAGES%

	>nul copy /y NUL %PINT_PACKAGES_FILE%

	for /f "usebackq" %%f in ("%PINT_SRC_FILE:~1,-1%") do (
		>>%PINT_PACKAGES_FILE% "%ComSpec%" /d /c %CURL% --compressed -s -S "%%f"
		if not errorlevel 1 (echo Fetched %%f) else (echo Failed to fetch %%f)
	)

	echo Done.

	for %%f in (%PINT_PACKAGES_FILE%) do if "%%~zf"=="0" exit /b 1
	exit /b 0


:search :: [<term>]
:: Search for an app in the database, or show all items.
	call :_db_exists

	if exist %PINT_PACKAGES_FILE_USER% (
		%FINDSTR% /I /B /R "\s*\[.*%~1.*\]" %PINT_PACKAGES_FILE_USER% | %SORT%
	)

	%FINDSTR% /I /B /R "\s*\[.*%~1.*\]" %PINT_PACKAGES_FILE% | %SORT%

	exit /b !ERRORLEVEL!


:_db_exists
	if not exist %PINT_PACKAGES_FILE% (
		echo Unable to find a package database, updating...
		call :update || ( echo Update failed. && exit /b 1 )
	)
	exit /b 0


:subscribed
:: Show the list of databases, you are subscribed to.
	type %PINT_SRC_FILE%
	exit /b !ERRORLEVEL!


:subscribe :: <url>
:: Add a subscription to a package database.
:: Essentially, it has to be a direct URL of an .ini file.
	if "%~1"=="" (
		echo Enter an URL^^!
		exit /b 1
	)

	>nul !FINDSTR! /L /X "%~1" %PINT_SRC_FILE% && (
		echo This URL is already registered.
		exit /b 1
	)

	>%PINT_TEMP_FILE% echo %~1
	>>%PINT_TEMP_FILE% type %PINT_SRC_FILE%
	>nul move /Y %PINT_TEMP_FILE% %PINT_SRC_FILE%

	echo Registered %~1
	echo.
	echo Your new source list:
	call :subscribed

	exit /b 0


:unsubscribe :: <url>
:: Remove the URL from the list of subscriptions.
	if "%~1"=="" (
		echo Enter an URL^^!
		exit /b 1
	)

	>nul %FINDSTR% /L /X "%~1" %PINT_SRC_FILE% || (
		echo This URL is not registered.
		exit /b 1
	)

	>%PINT_TEMP_FILE% %FINDSTR% /X /L /V "%~1" %PINT_SRC_FILE%
	>nul move /Y %PINT_TEMP_FILE% %PINT_SRC_FILE%

	echo Unregistered %~1
	echo.
	echo Your new source list:
	call :subscribed

	exit /b !ERRORLEVEL!


:list
:: Show all applications installed via Pint.
	for /f "usebackq delims=" %%s in (`2^>nul dir /b /s /ah "%PINT_APPS_DIR%\*.pint"`) do (
		set "_dir=%%s"
		set "_dir=!_dir:%PINT_APPS_DIR%\=!"
		set "_dir=!_dir:\%%~nxs=!"
		echo !_dir!
	)
	exit /b 0


rem "@ref File/directory" "@ref Result"
:_get_app
	set "_path=%~1"
	if "!_path!"=="!_path::=!" set "_path=%PINT_APPS_DIR%\%~1"

	if /I not "%~x1"==".pint" (
		for /f "usebackq delims=" %%x in (`2^>nul dir /b /ah "!_path!\*.pint"`) do (
			call :_get_app "!_path!\%%x" %2
			exit /b !ERRORLEVEL!
		)
		exit /b 1
	) else (
		endlocal
		set "_i=1"
		set "%2[dir]=%~dp1"
		set "%2[dir]=!%2[dir]:~0,-1!"
		set "%2[relpath]=!%2[dir]:%PINT_APPS_DIR%\=!"
		for /f "delims=" %%s in ("!%2[dir]!") do set "%2[name]=%%~nxs"
		for %%x in (%~n1) do (
			if defined _i (
				set "%2[id]=%%x"
				set "_i="
			) else (
				if "%%~x"=="64" (
					set "%2[64]=1"
				) else (
					if "%%~x"=="pinned" (
						set "%2[pinned]=1"
					) else (
						set "_token=%%~x"
						if "!_token:~0,1!"=="v" (
							set "%2[version]=!_token:~1!"
						) else (
							set "%2[size]=%%~x"
						)
					)
				)
			)
		)
	)
	exit /b 0


:outdated :: [<path>]
:: Check for updates for all or some packages by your choice.
	if not "%~1"=="" (
		for %%x in (%*) do (
			if exist "%PINT_APPS_DIR%\%%~x" (
				call :_package_outdated "%%~x"
			) else (
				echo Not found: %PINT_APPS_DIR%\%%~x
			)
		)
	) else (
		for /f "usebackq delims=" %%s in (`2^>nul dir /b /s /ah "%PINT_APPS_DIR%\*.pint"`) do (
			call :_package_outdated "%%s"
		)
	)
	exit /b !ERRORLEVEL!


rem "Path"
:_package_outdated
	call :_get_app %1 app || exit /b 1

	if "!app[size]!"=="" (
		echo %~1 is not tracked by Pint, try to reinstall.
		exit /b 0
	)

	>nul call :_get_dist_info "!app[id]!" url || (
		echo Unable to get a link for %~1.
		exit /b 1
	)

	call :_url_is_updated app url
	exit /b !ERRORLEVEL!


:upgrade :: [<path>]
:: Install updates for all or selected apps.
	if not "%~1"=="" (
		for %%x in (%*) do call :_package_upgrade "%%~x"
	) else (
		for /f "usebackq delims=" %%x in (`%PINT% list`) do call :_package_upgrade "%%x"
	)
	exit /b !ERRORLEVEL!


rem "Path"
:_package_upgrade
	call :_is_dir_non_empty %1 || (
		call :install %1
		exit /b !ERRORLEVEL!
	)
	call :_is_dir_tracked %1 || exit /b 1
	call :_is_dir_upgradable %1 || exit /b 1

	call :_get_app %1 app

	if "!app[size]!"=="" (
		echo %~1 is not tracked by Pint, try to reinstall.
		exit /b 0
	)

	>nul call :_get_dist_info "!app[id]!" url || (
		echo Unable to get a link for %~1.
		exit /b 1
	)

	call :_url_is_updated app url && (
		call :_get_dist_file "!app[id]!" url _destfile
		call :_download url[url] _destfile && (
			call :_force_install "!app[id]!" "%PINT_APPS_DIR%\%~1"
			exit /b !ERRORLEVEL!
		)
	)
	exit /b 1


:pin :: <path>
:: Suppress updates for selected apps.
	if not "%~2"=="" (
		for %%x in (%*) do call :pin "%%~x"
		exit /b 0
	)
	call :_is_dir_tracked %1 || exit /b 1
	call :_get_app %1 app
	if defined _unpin (
		set "app[pinned]="
		echo %~1 is unpinned.
	) else (
		set "app[pinned]=1"
		echo %~1 is pinned.
	)
	call :_save_app_data app
	exit /b !ERRORLEVEL!


:unpin :: <path>
:: Allow updates for selected apps.
	set "_unpin=1"
	call :pin %*
	exit /b 0


:remove :: <path>
:: Delete selected apps (this is equivalent to manual deletion).
	if not "%~2"=="" (
		for %%x in (%*) do call :remove "%%~x"
		exit /b 0
	)
	if exist "%PINT_APPS_DIR%\%~1" (
		echo Uninstalling %~1...
		2>nul rd /S /Q "%PINT_APPS_DIR%\%~1"
		call :_shims %1 "%PINT_APPS_DIR%\%~1" delete
	) else (
		echo %~1 is not installed
	)
	exit /b !ERRORLEVEL!


:purge :: <path>
:: Delete selected apps AND their installers.
	if not "%~2"=="" (
		for %%x in (%*) do call :purge "%%~x"
		exit /b 0
	)
	call :remove %1
	2>nul del /Q /S "%PINT_DIST_DIR%\%~1--*.*"
	exit /b !ERRORLEVEL!


:forget :: <path>
:: Stop tracking of selected apps.
	if not "%~2"=="" (
		for %%x in (%*) do call :forget "%%~x"
		exit /b 0
	)
	2>nul del /Q /S /AH "%PINT_APPS_DIR%\%~1\*.pint"
	echo %~1 is no longer managed by Pint.
	exit /b


:download :: <app>
:: Only download selected installers without unpacking them.
	if not "%~2"=="" (
		for %%x in (%*) do call :download "%%~x"
		exit /b 0
	)

	call :_get_dist_info %1 url || (
		echo Unable to get a link for %1.
		exit /b 1
	)

	call :_get_dist_file %1 url _destfile
	for %%x in ("!_destfile!") do set "size=%%~zx"

	if not "!size!"=="" (
		if not "!url[size]!"=="" (
			if "!size!"=="!url[size]!" (
				echo Remote file size is equal to the local, skipping redownloading.
				exit /b 0
			)
		)
	)

	2>nul del /Q /S "%PINT_DIST_DIR%\%~1--*.*"

	call :_download url _destfile || (
		echo Unable to download a package with %1.
		exit /b 1
	)

	exit /b !ERRORLEVEL!


rem "Application ID" "@ref URL" "@ref Result"
:_get_dist_file
	endlocal
	set "%~3=%PINT_DIST_DIR%\%~1--!%~2[name]!"
	exit /b 0


:installto :: <app> <path>
:: Install the app to the given path.
	call :_is_dir_non_empty %2 && (
		call :_is_dir_tracked %2
		if errorlevel 1 (
			echo %PINT_APPS_DIR%\%~2 is not empty.
			set /p _confirm=Do you want to REPLACE its contents? [Y/N] 
			if /I not "!_confirm!"=="Y" exit /b 1
		) else (
			echo %PINT_APPS_DIR%\%~2 is not empty.
			echo Use `reinstall` to force this action.
			exit /b 1
		)
	)
	call :_force_install %1 %2
	exit /b !ERRORLEVEL!


rem "Application ID []"
:install :: <app>
:: Install one or more apps to directories with the same names.
	if not "%~2"=="" (
		for %%x in (%*) do call :install "%%~x"
		exit /b 0
	)
	call :installto %1 %1
	exit /b !ERRORLEVEL!


rem "Application ID" "Destination directory"
:_force_install
	call :download %1
	call :_install_app_to %1 "%PINT_APPS_DIR%\%~2"
	exit /b !ERRORLEVEL!


:reinstall :: <path>
:: Force reinstallation of the package.
	if not "%~2"=="" (
		for %%x in (%*) do call :reinstall "%%~x"
		exit /b 0
	)
	call :_is_dir_upgradable %1 || exit /b 1
	call :_get_app %1 app || set "app[id]=%~1"
	call :download "!app[id]!"
	call :_install_app_to "!app[id]!" "%PINT_APPS_DIR%\%~1"
	exit /b !ERRORLEVEL!


:_get_dist_info :: <app-id> <@ref result>
	endlocal & SET "%~2="

	call :_db %1 dist follow link

	if not defined dist exit /b 1

	if not defined link (
		if not "!dist!"=="!dist:portableapps.com/apps/=!" (
			set "link=//a[contains(@href, '.paf.exe')]"
		)
	)

	SET "referer="

	if defined link (

		if defined follow (
			SET follow=!follow:^"=\"!
			SET follow=--follow "!follow: | =" --follow "!"
		)

		if not "!link!"=="!link:/a=!" (
			SET "link=!link!/resolve-uri(normalize-space(@href), base-uri())"
		)
		SET link=!link:^"=\"!
		SET referer=--referer "!dist!"
		SET _parsed=

		echo Extracting a download link from !dist!
		for /f "usebackq tokens=* delims=" %%i in (`2^>nul xidel "!dist!" !follow! --quiet --extract "(!link:%%=%%%%!)[1]" --header="Referer^: !dist!" --user-agent="!PINT_USER_AGENT!"`) do (
			set "dist=%%i"
			SET _parsed=1
		)

		if not defined _parsed (
			exit /b 1
		)
	)

	if not defined dist exit /b 1

	if not "!dist!"=="!dist:fosshub.com/=!" (
		set dist=!dist:fosshub.com/=fosshub.com/genLink/!
		set dist=!dist:.html/=/!
		for /f "usebackq tokens=* delims=" %%i in (`%CURL% -s !referer! "!dist!"`) do (
			set "dist=%%i"
		)
	)

	call :_get_url_info dist %~2
	exit /b !ERRORLEVEL!


rem "@ref URL" "@ref Result (without quotes!)"
:_get_url_info
	if "!%~1!"=="" ( echo Incorrect arguments. && exit /b 1 )
	if "%2"=="" ( echo Incorrect arguments. && exit /b 1 )
	endlocal
	set "%2[type]="
	set "%2[size]="
	set "%2[name]="
	set "%2[ext]="
	for /f "tokens=* delims=" %%i in ("!%~1!") do (
		set "%2[name]=%%~nxi"
		set "%2[ext]=%%~xi"
		if not "!%2[ext]!"=="" set "%2[ext]=!%2[ext]:~1!"
	)
	set "%2[url]=!%~1!"
	set "%2[protocol]="
	set "%2[code]="

	for /f "usebackq tokens=1,* delims=: " %%a in (`%CURL: --fail=% -s -S -I "!%~1!"`) do (
		set "_key=%%a"
		if /I "!_key:~0,5!"=="HTTP/" (
			for /f "tokens=1" %%s in ("%%b") do set "%2[code]=%%~s"
		)
		if /I "%%a"=="Content-Type" (
			for /f "tokens=1 delims=;" %%s in ("%%b") do set "%2[type]=%%s"
		)
		if /I "%%a"=="Content-Length" (
			set "%2[size]=%%b"
		)
		if /I "%%a"=="Location" (
			set "%2[name]=%%~nxb"
			set "%2[url]=%%~b"
		)
		if /I "%%a"=="Content-Disposition" (
			for /f "tokens=2 delims=^=" %%s in ("%%b") do (
				set "%2[name]=%%~nxs"
			)
		)
	)

	if "!%2[name]!"=="" exit /b 1

	for /f "tokens=1 delims=?" %%s in ("!%2[name]!") do (
		set "%2[name]=%%~nxs"
		set "%2[ext]=%%~xs"
		if not "!%2[ext]!"=="" set "%2[ext]=!%2[ext]:~1!"
	)

	if /I "!%2[url]:~0,4!"=="http" (
		set "%2[protocol]=0"
		if not "!%2[code]!"=="200" exit /b 1
	)
	if /I "!%2[url]:~0,4!"=="ftp:" (
		set "%2[protocol]=1"
		if "!%2[size]!"=="" exit /b 1
	)

rem		echo "!%2[type]!"
rem		echo "!%2[size]!"
rem		echo "!%2[name]!"
rem		echo "!%2[ext]!"
rem		echo "!%2[url]!"
rem		echo "!%2[protocol]!"
rem		echo "!%2[code]!"

	if "!%2[ext]!"=="" exit /b 1
	exit /b 0


rem "@ref App" "@ref Info"
:_url_is_updated
	if "!%1[size]!"=="" (
		echo %~1 is not tracked by Pint, try to reinstall.
		exit /b 3
	)

	if "%2[size]"=="" (
		echo Unable to check updates for %~1.
		exit /b 2
	)

	if /I "!%2[type]:~0,5!"=="text/" (
		echo The !%~1[id]! ^(!%~1[relpath]!^) server responded with a html page.
		exit /b 2
	) else (
		if "!%2[size]!"=="!%1[size]!" (
			echo !%~1[relpath]! is up to date.
			exit /b 1
		) else (
			echo !%~1[relpath]! is OUTDATED.
			exit /b 0
		)
	)


rem "@ref File path" "@ref Destination directory"
:_unpack_file_to
	for %%i in ("%~1") do (
		echo Unpacking %%~nxi

		if not exist "!%~2!" md "!%~2!"

		if /I "%%~xi"==".msi" (
			>nul !MSIEXEC! /a "%%~i" /norestart /qn TARGETDIR="!%~2!"
		) else (
			call :_where 7z
			if errorlevel 1 (
				if /I "%%~xi"==".zip" (
					call %PINT% unzip "%%~i" "!%~2!"
				) else (
					exit /b 1
				)
			) else (
				>nul "%ComSpec%" /d /c 7z x -y -aoa -o"!%~2!" "%%~i"
			)
		)
		if errorlevel 1 (
			echo Unpacking failed.
			exit /b 1
		)
		exit /b 0
	)


rem "Directory" "Search string" "@ref Result path"
:_get_root
	endlocal & set "%~3="
	cd /D %1 || exit /b 1
	for /f "usebackq delims=" %%i in (`2^>nul dir /b /s`) do (
		set "_file=%%i"
		if not "!_file!"=="!_file:%~2=!" (
			endlocal & set "%~3=%%i"
			exit /b 0
		)
	)
	exit /b 1


rem "Application ID" "Destination directory"
:_install_app_to
	cd /D "%PINT_DIST_DIR%"
	for %%f in (%~1--*.*) do set "_archive=%PINT_DIST_DIR%\%%f"

	echo Installing %~1 to %~2
	call :_db %1 type base xf xd

	if /I "!type!"=="standalone" (
		if not exist %2 md %2
		for %%f in ("!_archive!") do >nul copy /Y "!_archive!" /B "%~2\%~1%%~xf"
	) else (
		set "_tempdir=%TEMP%\pint\%~1%RANDOM%"
		if not exist "!_tempdir!" md "!_tempdir!"
		cd /D "!_tempdir!" || exit /b !ERRORLEVEL!

		call :_unpack_file_to "!_archive!" _tempdir || exit /b !ERRORLEVEL!

		if defined base (
			call :_get_root "!_tempdir!" "!base!" _base_dir && (
				cd /D "!_base_dir!\.."
			)
		)

		set "xf=/XF !xf! *.pint $R0"
		set "xd=/XD !xd! $PLUGINSDIR $TEMP"
		>nul !ROBOCOPY! "!cd!" %2 /E /PURGE /NJS /NJH /NFL /NDL /ETA !xf! !xd!
		cd /D %2
		rd /Q /S "%TEMP%\pint"
	)

	call :_get_app %2 app
	set "app[id]=%~1"
	set "app[dir]=%~2"
	call :_app_get_version %2 app[version]
	for %%f in ("!_archive!") do set "app[size]=%%~zf"
	call :_save_app_data app

	call :_shims %1 %2

	exit /b !ERRORLEVEL!


rem "@ref App"
:_save_app_data
	if "!%~1[id]!"=="" echo Invalid application.&& exit /b 1
	if "!%~1[dir]!"=="" echo Invalid application !%~1[dir]!.&& exit /b 1

	set "_name=!%~1[id]!"
	if not "!%~1[version]!"=="" set "_name=!_name! v!%~1[version]!"
	if not "!%~1[64]!"=="" set "_name=!_name! 64"
	if not "!%~1[pinned]!"=="" set "_name=!_name! pinned"
	if not "!%~1[size]!"=="" set "_name=!_name! !%~1[size]!"
	>nul 2>nul del /S /Q /AH "!%~1[dir]!\*.pint"
	if "!_name!"=="" exit /b 1
	>nul copy /y NUL "!%~1[dir]!\!_name!.pint"
	attrib +H "!%~1[dir]!\!_name!.pint"
	exit /b 0


rem "Path"
:_is_dir_non_empty
	if exist "%PINT_APPS_DIR%\%~1\*" exit /b 0
	exit /b 1


rem "Path"
:_is_dir_upgradable
	if exist "%PINT_APPS_DIR%\%~1\* pinned*.pint" (
		echo %~1 updates are suppressed. To allow this action, use `pint unpin %~1`.
		exit /b 1
	)
	exit /b 0


rem "Path"
:_is_dir_tracked
	if not exist "%PINT_APPS_DIR%\%~1\*.pint" (
		echo %~1 is not tracked by Pint, try to reinstall it.
		exit /b 1
	)
	exit /b 0


rem "Application ID" "Directory" "delete"
:_shims
	call :_db %1 shim noshim
	call %PINT% shim %2 "!shim!" "!noshim!" %3
	exit /b 0


rem "@ref URL" "@ref Destination file"
:_download
	echo Downloading !%~1[url]!
	if not exist "!%~dp2!" md "!%~dp2!"
	call :_where curl
	if errorlevel 1 (
		echo "!%~1[url]!" "!%~2!"
		call %PINT% download-file "%~1[url]" "!%~2!"
	) else (
		"%ComSpec%" /d /c %CURL% -o "!%~2!" "!%~1[url]!"
	)
	if errorlevel 1 (
		echo Download FAILED^^!
		exit /b 1
	) else (
		echo Saved to !%~2!
		exit /b 0
	)


rem "Path" "@ref Filename"
:_filename
	endlocal & set "%~2=%~nx1"
	exit /b 0


rem "Application ID" "@ref Keys[]"
:_db
	call :_db_exists

	if "!ini[%~1]!"=="" (
		call :_read_ini %PINT_PACKAGES_FILE% "%~1" ini
		if exist %PINT_PACKAGES_FILE_USER% call :_read_ini %PINT_PACKAGES_FILE_USER% "%~1" ini
	)
	set _i=1
	for %%x in (%*) do (
		if not defined _i (
			endlocal & (
				set "%%x=!ini[%~1][%%x]!"
				if not "%PROCESSOR_ARCHITECTURE%"=="x86" (
					if not "!ini[%~1][%%x64]!"=="" set "%%x=!ini[%~1][%%x64]!"
				)
			)
		)
		set _i=
	)
	exit /b 0


rem "Directory" "@ref result"
:_app_get_version
	for /f "usebackq tokens=* delims=" %%i in (`2^>nul dir /b /s /a-d /o-s "%~1\*.exe"`) do (
		SET "_exefile=%%i"
		SET "_exefile=!_exefile:\=\\!"
		for /f "usebackq tokens=2 delims=^= " %%a in (`2^>nul wmic datafile where name^="!_exefile!" get version /value`) do (
			SET _ver=%%a
			set _ver=!_ver:~0,-1!
			for /L %%x in (1,1,4) do (
				if "!_ver:~-2!"==".0" set _ver=!_ver:~0,-2!
			)
			if not defined _ver exit /b 1
			endlocal & set %~2=!_ver!
			exit /b 0
		)
		exit /b 1
	)
	exit /b 1


rem "INI file path" "Section" "@ref Result"
:_read_ini
	if "%~2"=="" (
		echo Incorrect arguments in _read_ini: %*
		exit /b 1
	)

	set _section=
	set _key=

	for /f "usebackq tokens=1* delims=^=" %%A in ("%~1") do (
		for /f "tokens=*" %%M in ("%%A") do set _key=%%M

		if not defined _section (
			if "!_key:~0,1!"=="[" (
				for /f "tokens=1 delims=]" %%M in ("!_key!") do (
					if /I "%%M]"=="[%~2]" set _section=1
				)
			)
		) else (
			rem Reached next section
			if "!_key:~0,1!"=="[" exit /b 0

			if not "%%B"=="" (
				for /l %%x in (1,1,10) do if "!_key:~-1!"==" " set _key=!_key:~0,-1!
				endlocal & (
					set "%~3[%~2]=1"
					for /f "tokens=*" %%V in ("%%B") do set "%~3[%~2][!_key!]=%%V"
				)
			)
		)
	)

	if not "!%~3[%~2]!"=="" exit /b 0
	exit /b 1


rem "INI file path" "Section" "Key" "@ref Value"
:_write_ini
	if "%~2"=="" exit /b 1
	if "%~1"=="" exit /b 1

	set _file="%~1"

	for /f "tokens=*" %%M in ("%~2") do set section=%%M
	for /l %%x in (1,1,10) do if "!section:~-1!"==" " set section=!section:~0,-1!

	set "ini[!section!][%~3]=%~4"

	if not "%~4"=="" (
		rem No file
		if not exist !_file! (
			>!_file! echo [!section!]
			>>!_file! echo %~3 = %~4
			exit /b !ERRORLEVEL!
		)
		rem No section
		>nul !FIND! "[!section!]" !_file! || (
			>>!_file! echo [!section!]
			>>!_file! echo %~3 = %~4
			exit /b !ERRORLEVEL!
		)
	)

	SET _section=
	SET _added=
	SET _pending=
	SET _header=

	>nul copy /y NUL %PINT_TEMP_FILE%

	for /f "usebackq tokens=1* delims=^=" %%A in ("%~1") do (
		for /f "tokens=*" %%M in ("%%A") do set _key=%%M
		for /l %%x in (1,1,10) do if "!_key:~-1!"==" " set _key=!_key:~0,-1!

		set _value=
		for /f "tokens=*" %%M in ("%%B") do set _value=%%M

		set _header=!_key!

		if "!_header:~0,1!"=="[" (
			set "_pending=!_key!"
		) else (
			SET _header=
		)

		if not defined _section (
			if defined _header (
				if not defined _added (
					if /I "!_key!"=="[!section!]" (
						SET _section=1
					)
				)
			)
			if not defined _section (
				if not defined _header (
					if defined _pending (
						>>%PINT_TEMP_FILE% echo !_pending!
						SET _pending=
					)
					>>%PINT_TEMP_FILE% echo !_key! = !_value!
				)
			)
		) else (
			rem Reached next section, but not found yet
			if defined _header (
				if not defined _added (
					if not "%~4"=="" (
						>>%PINT_TEMP_FILE% echo %~3 = %~4
						SET _added=1
						if defined _pending (
							>>%PINT_TEMP_FILE% echo !_pending!
							SET _pending=
						)
					)
				)
				SET _section=
			) else (
				if not "%~3"=="" (
					if /I "!_key!"=="%~3" (
						if not "%~4"=="" (
							if defined _pending (
								>>%PINT_TEMP_FILE% echo !_pending!
								SET _pending=
							)
							>>%PINT_TEMP_FILE% echo %~3 = %~4
							SET _added=1
						)
					) else (
						if not defined _header (
							if defined _pending (
								>>%PINT_TEMP_FILE% echo !_pending!
								SET _pending=
							)
							>>%PINT_TEMP_FILE% echo !_key! = !_value!
						)
					)
				)
			)
		)
	)

	if defined _section (
		if not defined _added (
			if not "%~4"=="" (
				if defined _pending (
					>>%PINT_TEMP_FILE% echo !_pending!
					SET _pending=
				)
				>>%PINT_TEMP_FILE% echo %~3 = %~4
			)
		)
	)

	>nul move /Y %PINT_TEMP_FILE% !_file!

	exit /b 0


rem Installs missing executables
rem "Executable path" "Application ID"
:_has
	call :_where %1 && exit /b 0
	echo Pint depends on %1, trying to install it automatically. Please wait...
	if not "%~2"=="" ( call :reinstall %2 ) else ( call :reinstall %1 )
	call :_where %1
	exit /b !ERRORLEVEL!


:_where
	if exist "%PINT_APPS_DIR%\%~1.bat" exit /b 0
	exit /b 1

goto :eof

end Batch / begin PowerShell #>

switch ($env:_COMMAND) {
	usage {
		write-host "PINT - Portable INsTaller" -foreground "white"
		""
		"Usage:"
		write-host "pint `<command`> `<parameters`>" -foreground "yellow"
		""
		"Available commands:"
		foreach ($line in (Get-Content $env:PINT.Replace("`"",""))) {
			if ($line.StartsWith("::")) {
				if ($command -eq 1) {
					write-host $line.replace(":: ", "")
					$command = 0
				} else {
					write-host "".padright(19, " ") -nonewline
					write-host $line.replace(":: ", "")
				}
			} elseif ($line.StartsWith(":") -and -not $line.StartsWith(":_")) {
				write-host $line.substring(1).replace(":: ", "").padright(18, " ") -foreground "green" -nonewline
				write-host " " -nonewline
				$command = 1
			}
		}
		""
		"`<app`> refers to an ID from the database, which can be seen via the search command."
		"`<path`> refers to a relative path to an app in the 'apps' directory as shown by the list command."
	}
	unzip {
		$shell = New-Object -com Shell.Application
		$zip = $shell.NameSpace($env:_PARAM_1)
		if (!(Test-Path $env:_PARAM_2)) { New-Item $env:_PARAM_2 -type directory | Out-Null }
		$shell.Namespace($env:_PARAM_2).copyhere($zip.items(), 20)
		if (!(Test-Path "$env:_PARAM_2\$($zip.items().item(0).Name)")) { exit 1 }
	}
	download-file {
		try {
			(new-object System.Net.WebClient).DownloadFile([Environment]::GetEnvironmentVariable($env:_PARAM_1), $env:_PARAM_2)
			if ($env:_PARAM_2 -and !(Test-Path $env:_PARAM_2)) {
				exit 1
			}
		} catch {
			exit 1
		}
	}
	shim {
		$params = @{
			"recurse" = $true
			"force" = $true
			"include" = "*.exe"
			 "EA" = "SilentlyContinue"
		}
		if ($env:_PARAM_2) { $params['include'] = ("*.exe $env:_PARAM_2" -split " ") }
		if ($env:_PARAM_3) { $params['exclude'] = ($env:_PARAM_3 -split " ") }

		Set-Location $env:PINT_APPS_DIR

		Get-ChildItem $env:_PARAM_1 @params | %{
			if ($_.extension -eq ".exe") {
				try {
					$fs = [IO.File]::OpenRead($_.fullname);
					$br = New-Object IO.BinaryReader($fs);
					if ($br.ReadUInt16() -ne 23117) { return }
					$fs.Position = 0x3C;
					$fs.Position = $br.ReadUInt32();
					$offset = $fs.Position;
					if ($br.ReadUInt32() -ne 17744) { return }
					# $fs.Position += 0x14;
					# switch ($br.ReadUInt16()) { 0x10B { $arch = 32 } 0x20B { $arch = 64 } }
					$fs.Position = $offset + 4 + 20 + 68;
					$subsystem = $br.ReadUInt16();
					if ($subsystem -ne 3) {
						return
					}
				} catch {
					return
				} finally {
					if ($br  -ne $null) { $br.Close() }
					if ($fs  -ne $null) { $fs.Close() }
				}
			}

			$batch = "$env:PINT_APPS_DIR\$($_.Basename).bat"

			if ($env:_PARAM_4 -eq "delete") {
				if (Test-Path $batch) {
					Remove-Item $batch
					"Removed $($_.Basename).bat"
				}
			} else {
				$relpath = (Resolve-Path -relative $_.fullname).Substring(2)
				$cmd = "`@echo off`n`"%~dp0$relpath`" %*`nexit /b %ERRORLEVEL%"
				$cmd | Out-File $batch -encoding ascii
				"Added a shim for $($_.Name)"
			}
		}
	}
	default {
		write-host "This is PowerShell." -f cyan
	}
}

exit 0