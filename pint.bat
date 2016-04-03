@if (true == false) @end /*
<# : Batch + JScript + PowerShell polyglot
@echo off
@setlocal enabledelayedexpansion

rem PINT - Portable INsTaller
rem https://github.com/vensko/pint

rem Set variables if they weren't overriden earlier
if not defined PINT_DIST_DIR set "PINT_DIST_DIR=%~dp0packages"
if not defined PINT_APPS_DIR set "PINT_APPS_DIR=%~dp0apps"
if not defined PINT_PACKAGES_FILE set PINT_PACKAGES_FILE="%~dp0packages.ini"
if not defined PINT_PACKAGES_FILE_USER set PINT_PACKAGES_FILE_USER="%~dp0packages.user.ini"
if not defined PINT_SRC_FILE set PINT_SRC_FILE="%~dp0sources.list"
if not defined PINT_TEMP_FILE set PINT_TEMP_FILE="%TEMP%\pint.tmp"
if not defined PINT_HISTORY_FILE set PINT_HISTORY_FILE="%~dp0local.ini"

if not defined PINT_USER_AGENT (
	set "PINT_USER_AGENT=User-Agent^: Mozilla/5.0 ^(Windows NT 6.1^; WOW64^; rv^:40.0^) Gecko/20100101 Firefox/40.1"
)

SET PINT="%~f0"
path !PINT_APPS_DIR!;%PATH%

rem Hardcoded URLs
set "PINT_PACKAGES=https://raw.githubusercontent.com/vensko/pint/master/packages.ini"
set "PINT_SELF_URL=https://raw.githubusercontent.com/vensko/pint/master/pint.bat"

SET FINDSTR="%WINDIR%\system32\findstr.exe"
SET FIND="%WINDIR%\system32\find.exe"
SET SORT="%WINDIR%\system32\sort.exe"
SET FORFILES="%WINDIR%\system32\forfiles.exe"
SET MSIEXEC="%WINDIR%\system32\msiexec.exe"
SET ROBOCOPY="%WINDIR%\system32\robocopy.exe"

rem Functions accessible directly from the command line
SET BAT_FUNCTIONS=usage self-update update subscribe subscribed install reinstall installed unsubscribe
SET BAT_FUNCTIONS=!BAT_FUNCTIONS! download remove purge upgrade search outdated add pin unpin _get_url_info
SET JS_FUNCTIONS=unzip
SET PS_FUNCTIONS=shim download-file

SET CURL=curl --insecure --ssl-no-revoke --ssl-allow-beast --progress-bar --remote-header-name --location
SET CURL=!CURL! --create-dirs --fail --max-redirs 5 --retry 2 --retry-delay 1 -X GET
SET POWERSHELL=powershell -NonInteractive -NoLogo -NoProfile -executionpolicy bypass
SET JSCRIPT="%WINDIR%\system32\cscript.exe" //nologo //e:jscript !PINT!

if "%~1"=="" (
	call :usage
	exit /b 0
)

rem Create directories if needed
if not exist "!PINT_APPS_DIR!" (
	md "!PINT_APPS_DIR!"
)

if not exist !PINT_HISTORY_FILE! (
	>nul copy /y NUL !PINT_HISTORY_FILE!
)

if not "%~1"=="update" (
	if not exist !PINT_PACKAGES_FILE! (
		call :update
	)
)

rem JScript
for %%x in (!JS_FUNCTIONS!) do (
	if "%~1"=="%%x" (
		!JSCRIPT! %*
		exit /b !ERRORLEVEL!
	)
)

rem PowerShell
for %%x in (!PS_FUNCTIONS!) do (
	if "%~1"=="%%x" (
		SET "_COMMAND=%~1"
		if not "%~2"=="" SET "_PARAM_1=%~2"
		if not "%~3"=="" SET "_PARAM_2=%~3"
		if not "%~4"=="" SET "_PARAM_3=%~4"
		if not "%~5"=="" SET "_PARAM_4=%~5"
		!POWERSHELL! "iex ( ${!PINT:~1,-1!} | select -skip 1 | out-string)"
		exit /b !ERRORLEVEL!
	)
)

call :_has xidel || (
	echo Unable to install Xidel.
	exit /b 1
)
call :_has 7z 7-zip || (
	echo Unable to install 7-zip.
	exit /b 1
)
call :_has curl || (
	echo Unable to install curl.
	exit /b 1
)

rem Ready, steady, go
for %%x in (!BAT_FUNCTIONS!) do (
	if "%~1"=="%%x" (
		call :%*
		if exist !PINT_TEMP_FILE! del !PINT_TEMP_FILE!
		exit /b
	)
)

echo Unknown command
exit /b 1


rem *****************************************
rem  FUNCTIONS
rem *****************************************


:usage
	echo PINT - Portable INsTaller
	echo.
	echo Usage:
	echo pint update^|self-update^|usage^|subscribed^|installed^|search^|outdated^|upgrade
	echo pint download^|install^|reinstall^|installed^|purge^|pin^|unpin^|
	echo      search^|outdated^|upgrade^|remove^|purge^|pin^|unpin ^<package(s)^>
	echo pint add ^<package^> ^<url^>
	echo pint subscribe^|unsubscribe ^<packages-ini-url^>

	exit /b 0


:self-update
	echo Fetching !PINT_SELF_URL!

	if exist !PINT_TEMP_FILE! del !PINT_TEMP_FILE!

	"%ComSpec%" /d /c !CURL! -s -S -o !PINT_TEMP_FILE! "!PINT_SELF_URL!" && (
		>nul !FINDSTR! /L /C:"PINT - Portable INsTaller" !PINT_TEMP_FILE! && (
			>nul move /Y !PINT_TEMP_FILE! !PINT! && (
				echo Pint was updated to the latest version.
				exit /b 0
			)
		)
	)

	echo Self-update failed^^!
	exit /b 1


:update
	echo Updating the database...
	if not exist !PINT_SRC_FILE! (
		>!PINT_SRC_FILE! echo !PINT_PACKAGES!
	)

	>nul copy /y NUL !PINT_PACKAGES_FILE!
	SET /a _count=0

	for /f "usebackq tokens=* delims=" %%f in ("!PINT_SRC_FILE:~1,-1!") do (
		set /p ="Fetching %%f "<nul
		set /a _count+=1

		>>!PINT_PACKAGES_FILE! "%ComSpec%" /d /c !CURL! --compressed -s -S "%%f" || (
			echo - failed^^!
			set /a _count-=1
		)
	)

	echo.
	set /p ="Merged !_count! source"<nul
	if not !_count!==1 (echo s) else (echo.)
	echo.

	exit /b 0


rem "Term"
:search
	if not exist !PINT_PACKAGES_FILE! (
		echo Unable to find a package database, updating...
		call :update
	)

	if exist !PINT_PACKAGES_FILE_USER! (
		!FINDSTR! /I /B /R "\s*\[.*%~1.*\]" !PINT_PACKAGES_FILE_USER! | !SORT!
	)

	!FINDSTR! /I /B /R "\s*\[.*%~1.*\]" !PINT_PACKAGES_FILE! | !SORT!

	exit /b !ERRORLEVEL!


:subscribed
	type !PINT_SRC_FILE!
	exit /b !ERRORLEVEL!


rem "INI URL"
:subscribe
	if "%~1"=="" (
		echo Enter an URL^^!
		exit /b 1
	)

	>nul !FINDSTR! /L /X "%~1" !PINT_SRC_FILE! && (
		echo This URL is already registered.
		exit /b 1
	)

	>!PINT_TEMP_FILE! echo %~1
	>>!PINT_TEMP_FILE! type !PINT_SRC_FILE!
	>nul move /Y !PINT_TEMP_FILE! !PINT_SRC_FILE!

	echo Registered %~1
	echo.
	echo Your new source list:
	call :subscribed

	exit /b 0


rem "INI URL"
:unsubscribe
	if "%~1"=="" (
		echo Enter an URL^^!
		exit /b 1
	)

	>nul !FINDSTR! /L /X "%~1" !PINT_SRC_FILE! || (
		echo This URL is not registered.
		exit /b 1
	)

	>!PINT_TEMP_FILE! !FINDSTR! /X /L /V "%~1" !PINT_SRC_FILE!
	>nul move /Y !PINT_TEMP_FILE! !PINT_SRC_FILE!

	echo Unregistered %~1
	echo.
	echo Your new source list:
	call :subscribed

	exit /b !ERRORLEVEL!


:installed
	if "%~1"=="" (
		2>nul dir /b /ad "!PINT_APPS_DIR!"
		exit /b !ERRORLEVEL!
	)

	for %%x in (%*) do (
		call :_is_installed "%%~x"
		if "!ERRORLEVEL!"=="2" echo %%~x is NOT tracked by Pint.
		if "!ERRORLEVEL!"=="1" echo %%~x is NOT installed.
		if "!ERRORLEVEL!"=="0" echo %%~x is installed.
	)

	exit /b 0


:outdated
	if not "%~1"=="" (
		for %%x in (%*) do (
			call :_package_outdated "%%~x"
		)
		exit /b !ERRORLEVEL!
	)
	for /f "usebackq tokens=* delims=" %%x in (`2^>nul dir /b /ad "!PINT_APPS_DIR!"`) do (
		call :_package_outdated "%%x"
	)
	exit /b !ERRORLEVEL!


rem "Application ID" "File URL"
:add
	if not "%~3"=="" (
		echo Incorrect parameters.
		echo Use^: ^<package^> "^<url^>"
		exit /b 1
	)

	call :_is_upgradable || (
		exit /b 1
	)

	call :_read_ini !PINT_PACKAGES_FILE! %1 dist && (
		echo %~1 is present in a remote database.
		SET /P "CONFIRMED=Do you want to add this URL as a permanent source into the user configuration? [Y/N] "
		if /I not "!CONFIRMED!"=="Y" (
			exit /b 1
		)
	)

	call :_read_ini !PINT_PACKAGES_FILE_USER! %1 dist && (
		echo %~1 is present in the user database.
		SET /P "CONFIRMED=Do you want to set this URL as a new permanent source? [Y/N] "
		if /I not "!CONFIRMED!"=="Y" (
			exit /b 1
		)
	)

	set "_url=%~2"

	if not "!_url!"=="!_url:portableapps.com/apps/=!" (
		call :_write_ini !PINT_PACKAGES_FILE_USER! %1 dist %2
		call :_package_force_install %1
		exit /b !ERRORLEVEL!
	)

	set "_destdir=!PINT_DIST_DIR!\%~1"

	call :_download _url _destdir || (
		echo Unable to download %~1 from %~2.
		exit /b 1
	)

	call :_install_app %1 "!_destdir!" && (
		call :_write_ini !PINT_PACKAGES_FILE_USER! %1 dist %2
	)

	exit /b !ERRORLEVEL!


rem "Application ID []"
:pin
	for %%x in (%*) do call :_package_pin "%%~x"
	exit /b !ERRORLEVEL!

rem "Application ID []"
:unpin
	for %%x in (%*) do call :_package_unpin "%%~x"
	exit /b !ERRORLEVEL!

rem "Application ID []"
:remove
	for %%x in (%*) do call :_package_remove "%%~x"
	exit /b !ERRORLEVEL!

rem "Application ID []"
:download
	for %%x in (%*) do call :_package_download "%%~x"
	exit /b !ERRORLEVEL!

rem "Application ID []"
:install
	for %%x in (%*) do call :_package_install "%%~x"
	exit /b !ERRORLEVEL!

rem "Application ID []"
:reinstall
	for %%x in (%*) do call :_package_force_install "%%~x"
	exit /b !ERRORLEVEL!


rem "Application ID []"
:upgrade
	if not "%~1"=="" (
		for %%x in (%*) do (
			call :_package_upgrade "%%~x"
		)
		exit /b !ERRORLEVEL!
	)
	for /f "usebackq tokens=* delims=" %%x in (`2^>nul dir /b /ad "!PINT_APPS_DIR!"`) do (
		call :_package_upgrade "%%x"
	)
	exit /b !ERRORLEVEL!


rem "Application ID []"
:purge
	if "%~1"=="" (
		if exist "!PINT_DIST_DIR!" (
			rd /S /Q "!PINT_DIST_DIR!"
		)
		exit /b 0
	)

	for %%x in (%*) do (
		call :_package_purge "%%~x"
	)
	exit /b !ERRORLEVEL!


rem "Application ID"
:_package_pin
	call :_write_log %1 pinned 1 && (
		echo %~1 is pinned.
	)
	exit /b !ERRORLEVEL!


rem "Application ID"
:_package_unpin
	call :_write_log %1 pinned && (
		echo %~1 is unpinned.
	)
	exit /b !ERRORLEVEL!


rem "Application ID"
:_package_remove
	call :_is_installed %1 && (
		echo Uninstalling %~1...
	)
	if exist "!PINT_APPS_DIR!\%~1" (
		call :_shims %1 "!PINT_APPS_DIR!\%~1" delete
		rd /S /Q "!PINT_APPS_DIR!\%~1"
	)
	exit /b 0


rem "Application ID"
:_package_purge
	echo Removing the %~1 package...

	call :_package_remove %1

	if exist "!PINT_DIST_DIR!\%~1" (
		rd /S /Q "!PINT_DIST_DIR!\%~1"
	)

	call :_write_log %1

	exit /b 0


rem "Application ID"
:_package_outdated
	call :_is_installed %1 || (
		if "!ERRORLEVEL!"=="2" (
			echo %~1 is not tracked by Pint.
			exit /b 1
		) else (
			echo %~1 is not installed, try to reinstall.
			exit /b 1
		)
	)

	>nul call :_get_dist_link %1 dist || (
		echo Unable to get a link for %1.
		exit /b 1
	)

	call :_url_is_updated %1 dist || (
		exit /b 1
	)

	echo %~1 is OUTDATED.
	exit /b 0


rem "Application ID"
:_package_download
	call :_get_dist_link %1 _dist || (
		echo Unable to get a link for %1.
		exit /b 1
	)

	set "_destdir=!PINT_DIST_DIR!\%~1"

	call :_download _dist _destdir || (
		echo Unable to download an update for %1.
		exit /b 1
	)

	exit /b 0


rem "Application ID"
:_package_force_install
	call :_is_upgradable || (
		exit /b 1
	)

	call :_db %1 deps && (
		for %%x in (!deps!) do (
			call :_package_install "%%~x"
		)
	)

	call :_get_dist_link %1 _url || (
		echo Unable to get a link for %1.
		exit /b 1
	)

	set "_destdir=!PINT_DIST_DIR!\%~1"

	call :_download _url _destdir || (
		echo Unable to download %1.
		exit /b 1
	)

	call :_install_app %1 "!_destdir!"
	exit /b !ERRORLEVEL!


rem "Application ID"
:_package_install
	call :_is_installed %1 && (
		echo %~1 is already installed.
		exit /b 0
	)

	if errorlevel 2 (
		echo %~1 is not tracked by Pint.
		exit /b 1
	)

	call :_package_force_install %1
	exit /b !ERRORLEVEL!


rem "Application ID"
:_package_upgrade
	call :_is_installed %1 || (
		if errorlevel 2 (
			echo %~1 is not tracked by Pint.
			exit /b 1
		) else (
			call :_package_install %1
			exit /b !ERRORLEVEL!
		)
	)

	call :_is_upgradable %1 || (
		exit /b 1
	)

	call :_db %1 deps && (
		for %%x in (!deps!) do (
			call :_package_upgrade "%%~x"
		)
	)

	call :_get_dist_link %1 _url || (
		echo Unable to get a link for %1.
		exit /b 1
	)

	call :_url_is_updated %1 _url
	if !ERRORLEVEL!==1 (
		exit /b 0
	)

	set "_destdir=!PINT_DIST_DIR!\%~1"

	call :_download _url _destdir || (
		echo Unable to download an update for %1.
		exit /b 1
	)

	call :_install_app %1 "!_destdir!"
	exit /b !ERRORLEVEL!


rem "Application ID"
:_is_upgradable
	call :_read_log %1 pinned && (
		echo Updates for are suppressed. To allow this install, use pint unpin %~1
		exit /b 1
	)
	exit /b 0


rem "Application ID" "DIST Variable name"
:_get_dist_link
	endlocal & SET "%~2="

	if "%PROCESSOR_ARCHITECTURE%"=="x86" (
		call :_db %1 dist
		call :_db %1 follow
		call :_db %1 link
	) else (
		call :_db %1 dist64 dist || call :_db %1 dist
		call :_db %1 follow64 follow || call :_db %1 follow
		call :_db %1 link64 link || call :_db %1 link
	)

	if not defined dist (
		exit /b 1
	)

	if not defined link (
		if not defined link64 (
			if not "!dist!"=="!dist:portableapps.com/apps/=!" (
				set "link=//a[contains(@href, '.paf.exe')]"
			)
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

	if not defined dist (
		exit /b 1
	)

	if not "!dist!"=="!dist:fosshub.com/=!" (
		set dist=!dist:fosshub.com/=fosshub.com/genLink/!
		set dist=!dist:.html/=/!
		for /f "usebackq tokens=* delims=" %%i in (`!CURL! -s !referer! "!dist!"`) do (
			endlocal & (
				SET "%~2=%%i"
				exit /b 0
			)
		)
		exit /b 1
	)

	endlocal & (
		SET "%~2=!dist!"
		exit /b 0
	)


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


rem "Application ID" "@ref URL"
:_url_is_updated
	call :_read_log %1 size || (
		echo %~1 is not tracked by Pint, try to reinstall.
		exit /b 3
	)

	call :_get_url_info %2 _res || (
		echo Unable to check updates for %~1.
		exit /b 2
	)

	if /I "!_res[type]:~0,5!"=="text/" (
		echo The %~1 server responded with a html page.
		exit /b 2
	) else (
		if "!_res[size]!"=="!size!" (
			echo %~1 is up to date.
			exit /b 1
		) else (
			exit /b 0
		)
	)


rem "Application ID" "Source directory"
:_install_app
	set "_archive="
	for /f "usebackq tokens=* delims=" %%i in (`2^>nul dir /b /s /a-d %2`) do set "_archive=%%i"
	if not defined _archive exit /b 1
	call :install_file %1 _archive "!PINT_APPS_DIR!\%~1"
	exit /b !ERRORLEVEL!


rem "@ref File path" "@ref Destination directory"
:_unpack
	for /f "tokens=* delims=" %%i in ("!%~1!") do (
		echo Unpacking %%~nxi

		if not exist "!%~2!" md "!%~2!"

		if /I "%%~xi"==".msi" (
			>nul !MSIEXEC! /a "%%i" /norestart /qn TARGETDIR="!%~2!"
		) else (
			call :_where 7z
			if errorlevel 1 (
				if /I "%%~xi"==".zip" (
					!JSCRIPT! unzip "%%i" "!%~2!"
				) else (
					exit /b 1
				)
			) else (
				>nul "%ComSpec%" /d /c 7z x -y -aoa -o"!%~2!" "%%i"
			)
		)
	)
	exit /b !ERRORLEVEL!


rem "Directory" "Search string" "@ref Result path"
:_get_root
	endlocal & set "%~3="
	cd /D %1 || exit /b 1
	for /f "usebackq tokens=* delims=" %%i in (`dir /b /s`) do (
		set "_file=%%i"
		if not "!_file!"=="!_file:%~2=!" (
			endlocal & set "%~3=%%i"
			exit /b 0
		)
	)
	exit /b 1


rem "Application ID" "@ref File path" "Destination directory"
:install_file
	echo Installing %~1 to %~3

	set "type="
	if /I "!%~2:~-4!"==".exe" call :_db %1 type

	if /I "!type!"=="standalone" (
		if not exist %3 md %3
		call :_filename "!%~2!" _filename
		>nul copy /Y "!%~2!" /B "%~3\!_filename!"
	) else (
		set "_tempdir=%TEMP%\pint\%~1%RANDOM%"
		if not exist "!_tempdir!" md "!_tempdir!"
		cd /D "!_tempdir!" || exit /b !ERRORLEVEL!

		call :_unpack %2 _tempdir || exit /b !ERRORLEVEL!

		if "%PROCESSOR_ARCHITECTURE%"=="x86" (
			call :_db %1 base
			call :_db %1 xf
			call :_db %1 xd
		) else (
			call :_db %1 base64 base || call :_db %1 base
			call :_db %1 xf64 xf || call :_db %1 xf
			call :_db %1 xd64 xd || call :_db %1 xd
		)

		if defined base (
			call :_get_root "!_tempdir!" "!base!" _base_dir && (
				cd /D "!_base_dir!\.."
			)
		)

		set "xf=/XF !xf! $R0"
		set "xd=/XD !xd! $PLUGINSDIR $TEMP"
		>nul !ROBOCOPY! "!cd!" %3 /E /PURGE /NJS /NJH /NFL /NDL /ETA !xf! !xd!
		cd /D %3
		rd /Q /S "%TEMP%\pint"
	)

	for /f "tokens=* delims=" %%i in ("!%~2!") do (
		call :_write_log %1 size "%%~zi"
		call :_write_log %1 filemtime "%%~ti"
	)

	call :_app_get_version %3 _v && (
		echo Detected version !_v!
		call :_write_log %1 version "!_v!"
	)

	call :_shims %1 %3

	exit /b !ERRORLEVEL!


rem "Application ID"
:_is_installed
	>nul 2>nul !FINDSTR! /I /L /C:"[%~1]" !PINT_PACKAGES_FILE_USER! || (
		>nul 2>nul !FINDSTR! /I /L /C:"[%~1]" !PINT_PACKAGES_FILE! || exit /b 2
	)
	2>nul dir /b "!PINT_APPS_DIR!\%~1\*.*" | >nul 2>nul !FIND! /v "" && exit /b 0
	exit /b 1


rem "Application ID" "Directory" "delete"
:_shims
	call :_db %1 shim
	call :_db %1 noshim
	call !PINT! shim %2 "!shim!" "!noshim!" %3
	exit /b 0


rem "@ref Download URL" "@ref Destination directory" "Download URL"
:_download
	echo Downloading !%~1!

	SET "DEST_FILE="
	
	if not exist "!%~2!" md "!%~2!"
	if not "%~x3"=="" SET "DEST_FILE=%~nx3"

	call :_where curl || (
		if not defined DEST_FILE set "DEST_FILE=download.zip"
		call !PINT! download-file "%~1" "!%~2!\!DEST_FILE!" && exit /b 0
		echo Download FAILED.
		exit /b 1
	)

	if defined DEST_FILE (
		"%ComSpec%" /d /c !CURL! -o "!%~2!\!DEST_FILE!" "!%~1!" || (
			echo FAILED
			exit /b 1
		)
	) else (
		pushd "!%~2!"
		echo !CURL! -O -J "!%~1!"
		"%ComSpec%" /d /c !CURL! -O -J "!%~1!" || (
			echo FAILED
			popd
			exit /b 1
		)
		popd
	)

	exit /b 0


rem "Path" "@ref Filename"
:_filename
	endlocal & set "%~2=%~nx1"
	exit /b 0


rem "Section" "Key" "Variable name (optional)"
:_read_log
	call :_read_ini !PINT_HISTORY_FILE! %*
	exit /b !ERRORLEVEL!


rem "Section" "Key" "Variable with Value"
:_write_log
	call :_write_ini !PINT_HISTORY_FILE! %*
	exit /b !ERRORLEVEL!


rem "Section" "Key" "Variable name (optional)"
:_db
	call :_read_ini !PINT_PACKAGES_FILE_USER! %* || call :_read_ini !PINT_PACKAGES_FILE! %*
	exit /b !ERRORLEVEL!


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



rem "INI file path" "Section" "Key" "Variable name (optional)"
:_read_ini
	endlocal & (
		if not "%~3"=="" (
			SET "%~3="
		)
		if not "%~4"=="" (
			SET "%~4="
		)
	)
	if "%~3"=="" (
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
			if "!_key:~0,1!"=="[" (
				exit /b 1
			)

			if not "%%B"=="" (
				for /l %%x in (1,1,10) do if "!_key:~-1!"==" " set _key=!_key:~0,-1!

				if /I "!_key!"=="%~3" (
					endlocal & (
						for /f "tokens=*" %%M in ("%%B") do (
							if not "%~4"=="" (
								set "%~4=%%M"
							) else (
								set "!_key!=%%M"
							)
						)
						exit /b 0
					)
				)
			)
		)
	)

	exit /b 1


rem "INI file path" "Section" "Key" "@ref Value"
:_write_ini
	if "%~2"=="" exit /b 1
	if "%~1"=="" exit /b 1

	set _file="%~1"

	for /f "tokens=*" %%M in ("%~2") do set section=%%M
	for /l %%x in (1,1,10) do if "!section:~-1!"==" " set section=!section:~0,-1!

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

	>nul copy /y NUL !PINT_TEMP_FILE!

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
						>>!PINT_TEMP_FILE! echo !_pending!
						SET _pending=
					)
					>>!PINT_TEMP_FILE! echo !_key! = !_value!
				)
			)
		) else (
			rem Reached next section, but not found yet
			if defined _header (
				if not defined _added (
					if not "%~4"=="" (
						>>!PINT_TEMP_FILE! echo %~3 = %~4
						SET _added=1
						if defined _pending (
							>>!PINT_TEMP_FILE! echo !_pending!
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
								>>!PINT_TEMP_FILE! echo !_pending!
								SET _pending=
							)
							>>!PINT_TEMP_FILE! echo %~3 = %~4
							SET _added=1
						)
					) else (
						if not defined _header (
							if defined _pending (
								>>!PINT_TEMP_FILE! echo !_pending!
								SET _pending=
							)
							>>!PINT_TEMP_FILE! echo !_key! = !_value!
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
					>>!PINT_TEMP_FILE! echo !_pending!
					SET _pending=
				)
				>>!PINT_TEMP_FILE! echo %~3 = %~4
			)
		)
	)

	>nul move /Y !PINT_TEMP_FILE! !_file!

	exit /b 0


rem Installs missing executables
rem "Executable path" "Application ID"
:_has
	call :_where %1 && exit /b 0

	echo Pint depends on %1, trying to install it automatically. Please wait...

	if not "%~2"=="" (
		call :_package_force_install %2
	) else (
		call :_package_force_install %1
	)

	call :_where %1
	exit /b !ERRORLEVEL!


:_where
	if exist "!PINT_APPS_DIR!\%~1.bat" exit /b 0
	exit /b 1

goto :eof

**/

if (WScript.Arguments.length === 0) WScript.quit(0);

var app = new ActiveXObject("Shell.Application");
//var env = (new ActiveXObject("WScript.Shell")).Environment("Process");
var fso = new ActiveXObject("Scripting.FileSystemObject");

switch (WScript.Arguments(0)) {
	case "unzip":
		var file = WScript.Arguments(1);
		var dir = WScript.Arguments(2);
		if (!fso.FolderExists(dir)) fso.CreateFolder(dir);
	    var zip = app.NameSpace(WScript.Arguments(1));
	    app.NameSpace(WScript.Arguments(2)).CopyHere(zip.Items(), 4 + 16);
		if (!fso.FileExists(dir + "\\" + zip.Items().Item(0))) {
			WScript.quit(1);
		}
		WScript.quit(0);
		break;
}

WScript.quit(0);

/* end JScript / begin PowerShell #>

switch ($env:_COMMAND) {
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

# end PowerShell */