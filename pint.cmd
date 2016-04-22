<# :
@echo off
@setlocal enabledelayedexpansion

rem PINT - Portable INsTaller
rem https://github.com/vensko/pint

SET "PINT=%~f0"
SET "PINT_VERSION=1.0"

rem Set variables if they weren't overriden earlier
if not defined PINT_DIST_DIR set "PINT_DIST_DIR=%~dp0dist"
if not defined PINT_APPS_DIR set "PINT_APPS_DIR=%~dp0apps"
if not defined PINT_PACKAGES_FILE set "PINT_PACKAGES_FILE=%~dp0packages.ini"
if not defined PINT_PACKAGES_FILE_USER set "PINT_PACKAGES_FILE_USER=%~dp0packages.user.ini"
if not defined PINT_SRC_FILE set "PINT_SRC_FILE=%~dp0sources.list"
if not defined PINT_TEMP_FILE set "PINT_TEMP_FILE=%TEMP%\pint.tmp"
if not defined PINT_USER_AGENT set "PINT_USER_AGENT=PintBot/%PINT_VERSION% (+https://github.com/vensko/pint)"

SET "FINDSTR=%WINDIR%\system32\findstr.exe"
SET "FIND=%WINDIR%\system32\find.exe"
SET "SORT=%WINDIR%\system32\sort.exe"
SET "FORFILES=%WINDIR%\system32\forfiles.exe"
SET "MSIEXEC=%WINDIR%\system32\msiexec.exe"
SET "ROBOCOPY=%WINDIR%\system32\robocopy.exe"
SET "POWERSHELL=powershell -NonInteractive -NoLogo -NoProfile -executionpolicy bypass"

path %PINT_APPS_DIR%;%PATH%

rem Hardcoded URLs
set "PINT_PACKAGES=https://raw.githubusercontent.com/vensko/pint/master/packages.ini"
set "PINT_SELF_URL=https://raw.githubusercontent.com/vensko/pint/master/pint.bat"

SET CURL="%PINT_APPS_DIR%\curl.bat" -X GET -k -# -J -L -f -A "%PINT_USER_AGENT%" --create-dirs
SET CURL=%CURL% --ssl-no-revoke --ssl-allow-beast --create-dirs --max-redirs 5 --retry 2 --retry-delay 1

rem call :_setup || exit /b 1

rem Functions accessible directly from the command line
SET BATCH=list search subscribed subscribe unsubscribe pin unpin remove purge forget _download

for %%x in (%BATCH%) do (
	if "%~1"=="%%x" (
		call :%*
		exit /b !ERRORLEVEL!
	)
)

set "_args=%*"
if defined _args set "_args=!_args:"=""""""!"
%POWERSHELL% "$s = ${%~f0} | out-string; $s += """pint-start !_args!"""; iex($s)"
exit /b !ERRORLEVEL!


rem *****************************************
rem  FUNCTIONS
rem *****************************************


:search :: [<term>]
:: Search for an app in the database, or show all items.
	if exist "%PINT_PACKAGES_FILE_USER%" (
		"%FINDSTR%" /I /B /R "\s*\[.*%~1.*\]" "%PINT_PACKAGES_FILE_USER%" | "%SORT%"
	)

	"%FINDSTR%" /I /B /R "\s*\[.*%~1.*\]" "%PINT_PACKAGES_FILE%" | "%SORT%"

	exit /b !ERRORLEVEL!


:subscribed
:: Show the list of databases, you are subscribed to.
	type "%PINT_SRC_FILE%"
	exit /b !ERRORLEVEL!


:subscribe :: <url>
:: Add a subscription to a package database.
:: Essentially, it has to be a direct URL of an .ini file.
	if "%~1"=="" (
		echo Enter an URL^^!
		exit /b 1
	)

	>nul "%FINDSTR%" /L /X "%~1" "%PINT_SRC_FILE%" && (
		echo This URL is already registered.
		exit /b 1
	)

	>"%PINT_TEMP_FILE%" echo %~1
	>>"%PINT_TEMP_FILE%" type "%PINT_SRC_FILE%"
	>nul move /Y "%PINT_TEMP_FILE%" "%PINT_SRC_FILE%"

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

	>nul "%FINDSTR%" /L /X "%~1" "%PINT_SRC_FILE%" || (
		echo This URL is not registered.
		exit /b 1
	)

	>"%PINT_TEMP_FILE%" "%FINDSTR%" /X /L /V "%~1" "%PINT_SRC_FILE%"
	>nul move /Y "%PINT_TEMP_FILE%" "%PINT_SRC_FILE%"

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


:pin :: <path>
:: Suppress updates for selected apps.
	if not "%~2"=="" (
		for %%x in (%*) do call :pin "%%~x"
		exit /b 0
	)
	call :_is_dir_tracked %1 || exit /b 1
	for /f "usebackq delims=" %%s in (`dir /b /ah "%PINT_APPS_DIR%\%~1\*.pint"`) do (
		set "_file=%%~ns"
		if defined _unpin (
			set "_file=!_file: pinned=!"
			echo %~1 is unpinned.
		) else (
			set "_file=!_file: pinned=! pinned"
			echo %~1 is pinned.
		)
		ren "%PINT_APPS_DIR%\%~1\%%s" "!_file!.pint"
	)
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
		rem call :_shims %1 "%PINT_APPS_DIR%\%~1" delete
		2>nul rd /S /Q "%PINT_APPS_DIR%\%~1"
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


rem "Path"
:_is_dir_tracked
	if not exist "%PINT_APPS_DIR%\%~1\*.pint" (
		echo %~1 is not tracked by Pint, try to reinstall it.
		exit /b 1
	)
	exit /b 0


rem "@ref URL" "@ref Destination file"
:_download
	echo Downloading !%~1!
	if not exist "!%~2!\.." md "!%~2!\.."
	%POWERSHELL% -command "&{ (new-object System.Net.WebClient).DownloadFile($env:%~1, $env:%~2) }"
	exit /b !ERRORLEVEL!


:self-update
:: Update Pint.
	echo Fetching %PINT_SELF_URL%

	if exist "%PINT_TEMP_FILE%" del "%PINT_TEMP_FILE%"

	call :_download PINT_SELF_URL PINT_TEMP_FILE && (
		>nul "%FINDSTR%" /L /C:"PINT - Portable INsTaller" "%PINT_TEMP_FILE%" && (
			>nul move /Y "%PINT_TEMP_FILE%" "%PINT%" && (
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

	if not exist "%PINT_SRC_FILE%" >"%PINT_SRC_FILE%" echo %PINT_PACKAGES%

	>nul copy /y NUL "%PINT_PACKAGES_FILE%"

	for /f "usebackq" %%f in ("%PINT_SRC_FILE%") do (
		set "_url=%%f"
		call :_download _url PINT_TEMP_FILE
		>>"%PINT_PACKAGES_FILE%" type "%PINT_TEMP_FILE%"
		if not errorlevel 1 (echo Fetched %%f) else (echo Failed to fetch %%f)
	)

	echo Done.

	for %%f in ("%PINT_PACKAGES_FILE%") do (
		if "%%~zf"=="0" (
			2>nul del /Q "%PINT_PACKAGES_FILE%"
			exit /b 1
		)
	)

	exit /b 0


rem Installs missing executables
rem "Executable path" "Application ID"
:_setup
	if not exist "%PINT_APPS_DIR%" md "%PINT_APPS_DIR%"

	set "_install="
rem		call :_where curl || set "_install=curl"
	call :_where 7z || set "_install=7-zip !_install!"
	call :_where xidel || set "_install=xidel !_install!"
	if not defined _install exit /b 0
	if "!_install:~-1!"==" " set "_install=!_install:~0,-1!"

	echo Pint needs to install some small dependencies in order to work (!_install!).
	set /p _confirm=Install them now? [Y/N]
	if /I not "!_confirm!"=="Y" exit /b 1

	call "%PINT%" reinstall !_install!
	exit /b !ERRORLEVEL!


:_where
	if exist "%PINT_APPS_DIR%\%~1.bat" exit /b 0
	exit /b 1


rem ============================================================================================


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
		for %%i in (id dir relpath 64 pinned version size) do set "%2[%%i]="
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
	if "%*"=="" (
		for /f "usebackq delims=" %%s in (`2^>nul dir /b /s /ah "%PINT_APPS_DIR%\*.pint"`) do (
			call :_package_outdated "%%s"
		)
	) else (
		for %%x in (%*) do call :_package_outdated "%%~x"
	)
	exit /b !ERRORLEVEL!


rem "Path"
:_package_outdated
	call :_get_app %1 app || (
		echo Unable to determine an app in %PINT_APPS_DIR%\%~1
		exit /b 1
	)

	if "!app[size]!"=="" (
		echo %~1 is not tracked by Pint, try to reinstall.
		exit /b 0
	)

	call :_get_dist_info "!app[id]!" url || (
		echo Unable to get a link for %~1.
		exit /b 1
	)

	call :_url_is_updated app url
	exit /b !ERRORLEVEL!


:upgrade :: [<path>]
:: Install updates for all or selected apps.
	if not "%*"=="" (
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

	call :_download url[url] _destfile || (
		echo Unable to download an archive with %1.
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
	call :download %1 || exit /b 1
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
	call :download "!app[id]!" || exit /b 1
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

		call :_where xidel || (
			echo Unable to find Xidel.
			exit /b 1
		)

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

		for /f "usebackq tokens=* delims=" %%i in (`2^>nul "%%PINT_APPS_DIR%%\xidel.bat" "!dist!" !follow! --quiet --extract "(!link:%%=%%%%!)[1]" --header="Referer^: !dist!" --user-agent="%%PINT_USER_AGENT%%"`) do (
			set "dist=%%i"
			SET _parsed=1
		)

		if not defined _parsed exit /b 1
	)

	if not defined dist exit /b 1

	if not "!dist!"=="!dist:fosshub.com/=!" (
		set dist=!dist:fosshub.com/=fosshub.com/genLink/!
		set dist=!dist:.html/=/!
		call :_where curl
		if errorlevel 1 (
			"%ComSpec%" /d /c %%PINT%% download-file dist PINT_TEMP_FILE
			for /f "usebackq delims=" %%i in ("%PINT_TEMP_FILE:~1,-1%") do set "dist=%%i"
			2>nul del /Q %PINT_TEMP_FILE%
		) else (
			for /f "usebackq delims=" %%i in (`%%CURL%% -s !referer! "!dist!"`) do set "dist=%%i"
		)
	)
	call :_get_url_info dist %~2
	exit /b !ERRORLEVEL!


rem "@ref URL" "@ref Result (without quotes!)"
:_get_url_info
	if "!%~1!"=="" ( echo Incorrect arguments. && exit /b 1 )
	if "%2"=="" ( echo Incorrect arguments. && exit /b 1 )
	endlocal
	for %%i in (type size name ext url protocol code) do set "%2[%%i]="

	for %%i in ("!%~1!") do (
		set "%2[name]=%%~nxi"
		set "%2[ext]=%%~xi"
		if not "!%2[ext]!"=="" set "%2[ext]=!%2[ext]:~1!"
	)

	set "%2[url]=!%~1!"
	call :_where curl
	if errorlevel 1 (
		2>nul del /Q %PINT_TEMP_FILE%
		call %PINT% get-headers "%~1"
		set "_cmd=type %PINT_TEMP_FILE%"
	) else (
		set "_cmd=%%CURL%% -s -S -I "!%~1!""
	)

	for /f "usebackq tokens=1,* delims=: " %%a in (`!_cmd!`) do (
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
					echo Unable to find 7-zip.
					exit /b 1
				)
			) else (
				>nul call "%PINT_APPS_DIR%\7z.bat" x -y -aoa -o"!%~2!" "%%~i"
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


rem "Application ID" "Directory" "delete"
:_shims
	call :_db %1 shim noshim
	call %PINT% shim %2 %3
	exit /b 0


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


goto :eof

end Batch / begin PowerShell #>

function usage
{
	write-host "PINT - Portable INsTaller" -f white
	""
	"Usage:"
	write-host "pint `<command`> `<parameters`>" -f yellow
	""
	"Available commands:"
	foreach ($line in (gc $env:PINT.Replace("`"",""))) {
		if ($line.StartsWith("::")) {
			if ($command -eq 1) {
				write-host $line.replace(":: ", "")
				$command = 0
			} else {
				write-host "".padright(19, " ") -nonewline
				write-host $line.replace(":: ", "")
			}
		} elseif ($line.StartsWith(":") -and -not $line.StartsWith(":_")) {
			write-host $line.substring(1).replace(":: ", "").padright(18, " ") -f green -nonewline
			write-host " " -nonewline
			$command = 1
		}
	}
	""
	"`<app`> refers to an ID from the database, which can be seen via the search command."
	"`<path`> refers to a relative path to an app in the 'apps' directory as shown by the list command."
}

function pint-shims([string]$dir, [string]$include, [string]$exclude, $delete)
{
	$params = @{
		recurse = $true
		force = $true
		name = $true
		exclude = $exclude -split ' ' |? {$_}
		ea = 0
	}

	if ($include) {
		$includeArr = $include -split ' '
		$params['include'] = @('*.exe') + $includeArr
	} else {
		$params['filter'] = '*.exe'
	}

	cd $env:PINT_APPS_DIR

	dir $dir @params |% {
		$exe = $_
		$relpath = join-path $dir $_

		if ([System.IO.Path]::GetExtension($_) -eq '.exe' -and (!$includeArr -or !($includeArr |? { $exe -like $_ }))) {
			$subsystem = $null
			try {
				$fs = [IO.File]::OpenRead($relpath);
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
			} catch {} finally {
				if ($br -ne $null) { $br.Close() }
				if ($fs -ne $null) { $fs.Close() }
			}
			if ($subsystem -ne 3) { return }
		}

		$baseName = [System.IO.Path]::GetFileNameWithoutExtension($_)
		$batch = join-path $env:PINT_APPS_DIR "$baseName.bat"

		if ($delete) {
			if (test-path $batch) {
				del $batch
				write-host "Removed $baseName.bat"
			}
		} else {
			$relpath = (rvpa -relative $relpath).substring(2)
			$cmd = "`@echo off`n`"%~dp0$relpath`" %*`nexit /b %ERRORLEVEL%"
			$cmd | out-file $batch -encoding ascii
			write-host "Added $baseName.bat"
		}
	}
}

function merge-hashtables
{
    $output = @{}
    foreach ($h in ($input + $args)) {
        If ($h -is [Hashtable]) {
            foreach ($k in $h.keys) {
				$output[$k] = $h[$k]
			}
        }
    }
    $output
}

function pint-get-app($p)
{
	try {
		$p = pint-dir $p

		if (test-path $p -pathtype leaf) {
			$f = $p
			$dir = [System.IO.Path]::GetDirectoryName($f)
		} else {
			$f = join-path $p (dir (join-path $p "*.pint") -name -force -ea stop | select -first 1)
			$dir = $p
		}

		$a = [System.IO.Path]::GetFileNameWithoutExtension($f).trim().split()

		$app = @{
			id = $a[0]
			dir = $dir
			arch = get-arch
			pinned = $false
			version = ""
			size = 0
		}

		$a = if ($a[1]) {$a[1..($a.count-1)]} else {@()}

		$a | % {
			switch ($_) {
				32 { $app['arch'] = 32 }
				64 { $app['arch'] = 64 }
				"pinned" { $app['pinned'] = $true }
				{$_[0] -eq "v"} { $app['version'] = $_.substring(1) }
				default { $app['size'] = [int]$_ }
			}
		}

		$app = merge-hashtables (get-app-info $app['id'] $app['arch']) $app

		$app
	} catch {
		write-host "$($MyInvocation.MyCommand): $_" -f yellow
		$null
	}
}

function pint-unpack($file, $d)
{
	try {
		if (!(test-path $file)) {
			write-host "Unable to find $file"
			return $false
		}

		if (!(test-path $d -pathtype container)) { md $d -ea stop | out-null }

		write-host "Unpacking $([System.IO.Path]::GetFileName($file))"

		$fullPath = [System.IO.Path]::GetFullPath($file)
		$sevenzip = (test-path (join-path $env:PINT_APPS_DIR "7z.bat"))

		switch ([System.IO.Path]::GetExtension($file)) {
			".msi" {
				& $env:ComSpec /d /c "msiexec /a `"$fullPath`" /norestart /qn TARGETDIR=`"$d`""
				break
			}
			{!$sevenzip -and ($_ -eq ".zip")} {
				$shell = new-object -com Shell.Application
				$zip = $shell.NameSpace($fullPath)
				$shell.Namespace($d).copyhere($zip.items(), 20)
				break
			}
			default {
				& $env:ComSpec /d /c "7z x -y -aoa -o`"$d`" `"$fullPath`"" | out-null
			}
		}

		!$lastexitcode
	} catch {
		write-host "$($MyInvocation.MyCommand): $_" -f yellow
		$false
	}
}

function pint-read-ini($ini, $term)
{
	$result = @{}
	if (!(test-path $ini)) { return $result }
	$term = '[' + $term + ']'
	$section = $false
	$file = new-object System.IO.StreamReader -Arg $ini
	while (($line = $file.ReadLine()) -ne $null) {
		if (!$section) {
			if ($line -eq $term) {
				$section = $true
			}
		} else {
			if ($line[0] -eq '[') { break }
			$key, $val = $line.split('=', 2)
			if (!$val) { $val = '' }
			$result[$key.trim()] = $val.trim()
		}
	}
	$file.close()
	$result
}

function pint-get-version($d)
{
	try {
		$v = (dir $d -recurse -filter *.exe -ea stop | sort -property length -descending | select -first 1).VersionInfo.FileVersion.trim()
		while ($v.substring($v.length-2, 2) -eq '.0') { $v = $v.substring(0, $v.length-2) }
		$v
	} catch {
		$null
	}
}

function get-arch
{
	if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') {32} else {64}
}

function get-app-info($id, $arch)
{
	if (!$arch) { $arch = get-arch }

	$ini = merge-hashtables (pint-read-ini $env:PINT_PACKAGES_FILE $id) (pint-read-ini $env:PINT_PACKAGES_FILE_USER $id)

	if ($ini.keys.count -eq 0) {
		write-host "Unable to find $id in the database"
		return $null
	}

	$res = @{}
	$ini.keys | sort | % {
		if ($_[-2]+$_[-1] -eq 64) {
			if ($arch -eq 64) {
				$res[$_.substring(0, $_.length-2)] = $ini[$_]
			}
		} else {
			$res[$_] = $ini[$_]
		}
	}

	if ($res.keys.count) { $res['arch'] = $arch }

	$res
}

function pint-make-request($url, $download)
{
	[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

	try {
		$redirects = 5
		$res = $null

		# supports redirection from HTTP to FTP
		while ($true) {
			$req = [System.Net.WebRequest]::Create($url)
			$req.set_Timeout(15000)
			$ftp = $url.StartsWith("ftp");

			if ($ftp) {
				if (!$download) {
					$req.Method = [System.Net.WebRequestMethods+Ftp]::GetFileSize
				}
			} else {
				$req.UserAgent = $env:PINT_USER_AGENT
				$req.AllowAutoRedirect = $false
  				$req.Accept = "*/*"
			}

			$res = $req.GetResponse()

			if (!$ftp -and $res.headers["Location"]) {
				$res.close()
				if ($redirects-- -eq 0) {
					write-host "Exceeded limit of redirections retrieving " $args[0] -f yellow
					return $null
				}
				$url = $res.headers["Location"]
				continue
			} else {
				break
			}
		}

		if ($res) {
			if ([string]$res.ContentType -eq "text/html") {
				$res.close()
				write-host $args[0] " responded with a HTML page." -f yellow
				return $null
			}

			if (!$res.ContentLength) {
				$res.close()
				write-host "Empty response from " $args[0] -f yellow
				return $null
			}

			if (!$download) { $res.close() }

			$res
		} else {
			$null
		}
	} catch [System.Net.WebException] {
		write-host "Unable to retrieve URL info:" $_ -f yellow
	}
}

function pint-get-dist-link($info, $verbose)
{
	if (!($info -is [Hashtable]) -or !$info['dist']) {
		write-host "Invalid application."
		return $null
	}

	$dist = $info['dist']
	$link = $info['link']

	if (!$link) {
		if ($dist.contains("portableapps.com/apps/")) {
			$link = "//a[contains(@href, '.paf.exe')]"
		}
	}

	if ($link) {
		if ($follow = $info['follow']) {
			$follow = $follow.replace("`"", "\`"").replace(" | ", "`" --follow `"")
		}

		if ($link.trimstart("/")[0] -eq "a") {
			$link += "/resolve-uri(normalize-space(@href), base-uri())"
		}

		$link = $link.replace("`"", "\`"")

		if ($verbose) {
			Write-Host "Extracting a download link from $dist"
		} else {
			$quiet = "--quiet"
		}

		$dist = & $env:ComSpec /d /c "2>nul xidel `"$dist`" $follow $quiet --extract `"($link)[1]`" --header=`"Referer: $dist`" --user-agent=`"$env:PINT_USER_AGENT`""

		if ($lastexitcode) {
			$dist = $null
		} else {
			$dist = $dist.trim()

			if ($dist.contains("fosshub.com/")) {
				$dist = $dist.replace("fosshub.com/", "fosshub.com/genLink/").replace(".html/", "/")
				$dist = (new-object System.Net.WebClient).DownloadString($dist).trim()
			}
		}

		if (!$dist) {
			write-host "Unable to extract a link from $($info['dist'])"
			return $null
		}
	}

	$dist
}

function pint-is-app-outdated($app)
{
	if (($url = pint-get-dist-link $app $verbose) -and ($res = pint-make-request $url $download)) {
		if ($res.ContentLength -eq $app['size']) { $res = $null; return $false }
		else { return $res }
	}
	$null
}

function pint-get-folder-size($path, $fso)
{
    if (!$fso) { $fso = New-Object -com  Scripting.FileSystemObject }
    ("{0:N2} MB" -f (($fso.GetFolder($path).Size) / 1MB))
}

function pint-download-file($res, $targetFile)
{
	if (!($res -is [System.Net.WebResponse])) {
		$res = pint-make-request $res $true
		if (!$res) { $false }
	}

	try {
		$totalLength = [System.Math]::Floor($res.ContentLength / 1024)

		write-host "Downloading $($res.ResponseUri) ($("{0:N2} MB" -f ($totalLength / 1024)))"

		$remoteName = pint-get-remote-name $res
		$responseStream = $res.GetResponseStream()
		$targetStream = new-object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create
		$buffer = new-object byte[] 32KB
		$count = $responseStream.Read($buffer,0,$buffer.length)
		$downloadedBytes = $count
		$progressBar = ($res.ContentLength -gt 1MB)
		while ($count -gt 0) {
			$targetStream.Write($buffer, 0, $count)
			$count = $responseStream.Read($buffer,0,$buffer.length)
			if ($progressBar) {
				$downloadedBytes += $count
				write-progress -activity "Downloading file $remoteName" -status "Downloaded ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -PercentComplete ((([System.Math]::Floor($downloadedBytes/1024)) / $totalLength)  * 100)
			}
		}
		$targetStream.Flush()
		$targetStream.Close()
		$targetStream.Dispose()
		$responseStream.Dispose()
		$res.Close()
		$targetFile
	} catch {
		write-host "Download failed: $_" -f yellow
		$false
	}
}

function pint-get-remote-name($res)
{
	if ($res.headers["Content-Disposition"] -and $res.headers["Content-Disposition"].contains("=")) {
		$res.headers["Content-Disposition"].split("=", 2)[1].replace("`"", "").trim()
	} else {
		$([string]$res.ResponseUri).split('/')[-1]
	}
}

function pint-download-app($id, $arch, $res)
{
	try {
		if (!($res -is [System.Net.WebResponse])) {
			$info = get-app-info $id $arch
			$url = pint-get-dist-link $info $true
			$res = pint-make-request $url $true
		}

		$name = pint-get-remote-name $res

		$file = join-path $env:PINT_DIST_DIR "$id--$name"

		if (test-path $file) {
			if (($file | gp).length -eq $res.ContentLength) {
				$res.close()
				write-host "The local file has the same size as the remote one, skipping redownloading."
				return $file
			}
		}

		if (pint-download-file $res $file) {
			write-host "Saved to $file"
			return $file
		}
	} catch {
		write-host "$($MyInvocation.MyCommand): $_" -f yellow
		return $null
	}
	write-host "Unable to download $id."
	$null
}

function pint-download
{
	$args | % {
		pint-download-app $_.trim() | out-null
	}
}

function pint-install
{
	$args | % { pint-installto $_ }
}

function pint-upgrade
{
	write-host "Checking for updates..."

	$args | % {
		$app = pint-get-app $_
		if (!$app) { write-host "$_ not found."; return }

		if ($res = pint-is-app-outdated $app) {
			write-host "$_ is OUTDATED."
			$file = pint-download-app $_ $null $res
			if (!$file) { return $false }
			pint-install-app $app['id'] $file $app['dir']
		} else {
			if ($res -eq $null) {
				write-host "Unable to check updates for $_"
			} else {
				write-host "$_ is up to date."
			}
		}
	}
}

function pint-installto($id, $dir)
{
	$file = pint-download-app $id
	if (!$file) { return $false }
	pint-install-app $id $file $dir | out-null
}

function pint-dir($path)
{
	if (!(split-path $path -isabsolute)) {
		$path = join-path $env:PINT_APPS_DIR $path
	}
	$path
}

function pint-install-app($id, $file, $destDir)
{
	try {
		if (!(test-path $file)) {
			throw [System.IO.FileNotFoundException] "Unable to find $file"
		}

		$id = $id.trim()
		if (!$destDir) { $destDir = $id }
		$destDir = pint-dir $destDir

		$info = pint-get-app $destDir
		if (!$info) { $info = get-app-info $id }

		if (!(test-path $destDir -pathtype container)) { md $destDir -ea stop }

		write-host "Installing $id to $destDir"

		if ($info['type'] -eq "standalone") {
			copy -LiteralPath $file (join-path $destDir "$id.exe") -force
		} else {
			$tempDir = join-path $env:TEMP "pint-$id-$(Get-Random)"
			md $tempDir | out-null
			cd $tempDir

			if ($tempDir -ne $pwd) {
				throw [System.IO.FileNotFoundException] "Unable to use the temporary directory $tempDir"
			}

			pint-unpack $file $tempDir | out-null

			if ($info['base']) {
				foreach ($p in (dir $pwd -recurse -name)) {
					if ($p.contains($info['base'])) {
						cd "$(join-path $pwd $p)\.."
						break
					}
				}
			}

			$xf = $info['xf'] + " *.pint `$R0"
			$xd = $info['xd'] + " `$PLUGINSDIR `$TEMP"

			& $env:COMSPEC /d /c "robocopy `"$pwd`" `"$destDir`" /E /PURGE /NJS /NJH /NFL /NDL /ETA /XF $xf /XD $xd" | out-null

			if ($lastexitcode -gt 7) {
				write-host "Detected errors while copying from $pwd with Robocopy ($lastexitcode)."
			}

			cd $destDir
			rd $tempDir -force -recurse
		}

		if ($version = pint-get-version $destDir) {
			write-host "Detected version $version"
		}

		$pintFile = (@($id, $version, $info['arch'], ($file | gp).length) | where {$_}) -join " "
		$pintFile = join-path $destDir "$pintFile.pint"

		del (join-path $destDir "*.pint") -force
		$pintFile = ni $pintFile -type file -force
		$pintFile.attributes = "Hidden"

		pint-shims $destDir $info['shim'] $info['noshim']

		$true

	} catch {
		write-host "$($MyInvocation.MyCommand): $_" -f yellow
		return $false
	}
}

function pint-test
{
	measure-command {
		($args[0] | gp).extension
	}

	measure-command {
		[System.IO.Path]::GetExtension($args[0])
	}
}

function pint-outdated
{
	write-host "Checking for updates..."

	$args | % {
		try {
			$app = pint-get-app $_

			if (!$app) { write-host "$_ not found."; return }
			if (!$app['size']) { write-host "Detected an app in $_, but the size data is missing."; return }

			$path = $_
			switch (pint-is-app-outdated $app) {
				$null { write-host "Unable to check updates for $path" }
				$false { write-host "$path is up to date." }
				default { write-host "$path is OUTDATED." }
			}
		} catch {
			write-host "$($MyInvocation.MyCommand): $_" -f yellow
		}
	}
}

function pint-start($cmd)
{
	if (!$cmd) { usage; exit 0 }

	$cmd = "pint-" + $cmd

	if (gcm $cmd -ea 0) {
		& $cmd @args
		exit $lastexitcode
	}

	"Unknown command"
	exit 1
}