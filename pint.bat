@if (true == false) @end /*
<# : Batch + JScript + PowerShell polyglot
@echo off
@setlocal enabledelayedexpansion

rem PINT - Portable INsTaller

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
SET BAT_FUNCTIONS=usage self-update update subscribe subscribed install reinstall
SET BAT_FUNCTIONS=!BAT_FUNCTIONS! download remove purge upgrade search outdated add pin unpin
SET JS_FUNCTIONS=unzip autodl
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

if not %1==update (
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
	echo pint download^|install^|reinstall^|installed^|purge^|pin^|unpin ^<package(s)^>
	echo pint search^|outdated^|upgrade^|remove^|purge^|pin^|unpin ^<package(s)^>
	echo pint add ^<package^> ^<url^>
	echo pint subscribe ^<packages-ini-url^>

	exit /b 0


:self-update
	echo Fetching !PINT_SELF_URL!

	if exist !PINT_TEMP_FILE! (
		del !PINT_TEMP_FILE!
	)

	"%ComSpec%" /d /c !CURL! -s -S -o !PINT_TEMP_FILE! "!PINT_SELF_URL!" || (
		echo Self-update failed^^!
		exit /b 1
	)

	>nul !FINDSTR! /L /C:"PINT - Portable INsTaller" !PINT_TEMP_FILE! || (
		echo Self-update failed^^!
		exit /b 1
	)
	
	>nul move /Y !PINT_TEMP_FILE! !PINT!

	echo Pint was updated to the latest version.
	exit /b 0


:update
	SET /a SRC_COUNT=0

	if not exist !PINT_SRC_FILE! (
		>!PINT_SRC_FILE! echo !PINT_PACKAGES!
	)

	>nul copy /y NUL !PINT_PACKAGES_FILE!

	for /f "usebackq tokens=* delims=" %%f in ("!PINT_SRC_FILE:~1,-1!") do (
		set /p ="Fetching %%f "<nul

		"%ComSpec%" /d /c !CURL! --compressed -s -S -o !PINT_TEMP_FILE! "%%f"

		if errorlevel 1 (
			echo - failed^^!
		) else (
			>>!PINT_PACKAGES_FILE! type !PINT_TEMP_FILE!
			SET /a SRC_COUNT+=1
			echo.
		)
	)

	set /p ="Merged !SRC_COUNT! source"<nul

	if not !SRC_COUNT!==1 (
		echo s
	)

	exit /b 0


:subscribed
	type !PINT_SRC_FILE!
	exit /b !ERRORLEVEL!


rem "Term"
:search
	if not exist !PINT_PACKAGES_FILE! (
		call :update
	)
	if exist !PINT_PACKAGES_FILE_USER! (
		!FINDSTR! /I /R "^^\[.*%~1" !PINT_PACKAGES_FILE_USER! | !SORT!
	)
	!FINDSTR! /I /R "^^\[.*%~1" !PINT_PACKAGES_FILE! | !SORT!

	if "%~1"=="" (
		exit /b 0
	)

	echo.
	echo Search results from PortableApps.com:

	set _term=%~1
	set _term=!_term:"=\"!
	set _term=!_term:'=\'!
	
	set _found=
	for /f "usebackq tokens=* delims=" %%i in (`xidel "http^://portableapps.com/apps" -e "//a[contains(@href, '/apps/') and text() [matches(.,'!_term!','i')]]/resolve-uri(normalize-space(@href), base-uri())" --quiet --user-agent="!PINT_USER_AGENT!"`) do (
		echo %%i
		set _found=1
	)
	if not defined _found (
		echo ^(No matches^)
	)

	echo.
	echo Search results from The Portable Freeware Collection:
	set _found=
	for /f "usebackq tokens=* delims=" %%i in (`xidel "http^://www.portablefreeware.com/index.php?q=!_term!" -e "//a[@class='appName']/concat(.[normalize-space()], ' [', resolve-uri(normalize-space(@href), base-uri()), ']')" --quiet --user-agent="!PINT_USER_AGENT!"`) do (
		echo %%i
		set _found=1
	)
	if not defined _found (
		echo ^(No matches^)
	)
	
	exit /b 0


rem "INI URL"
:subscribe
	SET URL="%~1"
	>nul !FINDSTR! /L /X !URL! !PINT_SRC_FILE! && (
		echo This URL is already registered.
		exit /b 1
	)
	>>!PINT_SRC_FILE! echo !URL:~1,-1!
	echo Registered !URL:~1,-1!
	exit /b 0


:installed
	if "%*"=="" (
		2>nul dir /b /ad "!PINT_APPS_DIR!"
		exit /b !ERRORLEVEL!
	)

	for %%x in (%*) do (
		call :_is_installed %%x
		if errorlevel 1 (
			echo %%x is NOT installed.
		) else (
			echo %%x is installed.
		)
	)

	exit /b 0


:outdated
	if not "%*"=="" (
		for %%x in (%*) do (
			call :_package_outdated %%x
		)
		exit /b !ERRORLEVEL!
	)
	for /f "usebackq tokens=* delims=" %%x in (`2^>nul dir /b /ad "!PINT_APPS_DIR!"`) do (
		call :_package_outdated %%x
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


:pin
	for %%x in (%*) do call :_package_pin %%x
	exit /b !ERRORLEVEL!

:unpin
	for %%x in (%*) do call :_package_unpin %%x
	exit /b !ERRORLEVEL!

:remove
	for %%x in (%*) do call :_package_remove %%x
	exit /b !ERRORLEVEL!

:download
	for %%x in (%*) do call :_package_download %%x
	exit /b !ERRORLEVEL!

:install
	for %%x in (%*) do call :_package_install %%x
	exit /b !ERRORLEVEL!

:reinstall
	for %%x in (%*) do call :_package_force_install %%x
	exit /b !ERRORLEVEL!

:upgrade
	if not "%~1"=="" (
		for %%x in (%*) do (
			call :_package_upgrade %%x
		)
		exit /b !ERRORLEVEL!
	)
	for /f "usebackq tokens=* delims=" %%x in (`2^>nul dir /b /ad "!PINT_APPS_DIR!"`) do (
		call :_package_upgrade %%x
	)
	exit /b !ERRORLEVEL!

:purge
	if "%~1"=="" (
		if exist "!PINT_DIST_DIR!" (
			rd /S /Q "!PINT_DIST_DIR!"
		)
		exit /b 0
	)

	for %%x in (%*) do (
		call :_package_purge %%x
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
	call :_shims %1 delete
	if exist "!PINT_APPS_DIR!\%~1" (
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
		echo %1 is not installed.
		exit /b 1
	)

	call :_get_dist_link %1 dist || (
		echo Unable to get a link for %1.
		exit /b 1
	)

	call :_url_is_updated %1 dist || (
		exit /b 1
	)

	echo %1 is OUTDATED.
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
			call :_package_install %%x
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
	call :_package_force_install %1
	exit /b !ERRORLEVEL!


rem "Application ID"
:_package_upgrade
	call :_is_installed %1 || (
		call :_package_install %1
		exit /b !ERRORLEVEL!
	)

	call :_is_upgradable %1 || (
		exit /b 1
	)

	call :_db %1 deps && (
		for %%x in (!deps!) do (
			call :_package_upgrade "%%x"
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

		for /f "usebackq tokens=* delims=" %%i in (`xidel "!dist!" !follow! --quiet --extract "(!link:%%=%%%%!)[1]" --header="Referer^: !dist!" --user-agent="!PINT_USER_AGENT!"`) do (
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


rem "Application ID" "Variable with file URL"
:_url_is_updated
	call :_read_log %1 size || (
		echo %1 is not tracked by Pint, try to reinstall.
		exit /b 3
	)

	set /a _outdated=1
	set /a _html=0

	for /f "usebackq tokens=1,2 delims=:; " %%a in (`!CURL! -s -S -I "!%~2!"`) do (
		if /I "%%a"=="Content-Type" (
			if "%%b"=="text/html" (
				set /a _html=1
			) else (
				set /a _html=0
			)
		) else (
			if /I "%%a"=="Content-Length" (
				if "%%b"=="!size!" (
					set /a _outdated=0
				) else (
					set /a _outdated=1
				)
			)
		)
	)

	if not defined _outdated (
		echo Unable to check updates for %~1.
		exit /b 2
	)

	if !_html!==1 (
		echo The %~1 server responded with a html page.
		exit /b 2
	) else (
		if !_outdated!==0 (
			echo %~1 is up to date.
			exit /b 1
		) else (
			exit /b 0
		)
	)


rem "Application ID" "Source directory"
:_install_app
	for /f "usebackq tokens=* delims=" %%i in (`2^>nul dir /b /s /a-d %2`) do (
		call :install_file %1 "%%i" "!PINT_APPS_DIR!\%~1"
		exit /b !ERRORLEVEL!
	)
	exit /b 1


rem "File path" "Destination directory"
:_unpack
	echo Unpacking %~nx1

	if not exist %2 md %2

	if /I "%~x1"==".msi" (
		>nul !MSIEXEC! /a %1 /norestart /qn TARGETDIR=%2
	) else (
		if /I "%~x1"==".zip" (
			call :_unzip %1 %2
		) else (
			call :_un7zip %1 %2
		)
	)

	exit /b !ERRORLEVEL!


rem "Directory" "Search string" "@var Result path"
:_get_root
	cd /D %1
	for /f "usebackq tokens=* delims=" %%i in (`dir /b /s`) do (
		set "_file=%%i"
		if not "!_file!"=="!_file:%~2=!" (
			endlocal & set "%~3=%%i"
			exit /b 0
		)
	)
	exit /b 1


rem "Application ID" "File path" "Destination directory"
:install_file
	echo Installing %~1 to %~3

	set "type="
	if /I "%~x2"==".exe" call :_db %1 type

	if /I "!type!"=="standalone" (
		if not exist %3 md %3
		>nul copy /Y %2 /B "%~3\%~nx2"
	) else (
		set "_tempdir=%TEMP%\pint\%~1%RANDOM%"
		if not exist "!_tempdir!" md "!_tempdir!"
		cd /D "!_tempdir!" || exit /b !ERRORLEVEL!

		call :_unpack %2 "!_tempdir!" || exit /b !ERRORLEVEL!

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
				cd /D "!_base_dir!\.." || exit /b !ERRORLEVEL!
			)
		)

		if defined xf set "xf=/XF !xf!"
		if defined xd set "xd=/XD !xd!"
		>nul !ROBOCOPY! "!cd!" %3 /E /PURGE /NJS /NJH /NFL /NDL /ETA !xf! !xd!
		cd /D %3
		rd /Q /S "%TEMP%\pint"
	)

	call :_get_file_properties %2 _size _filemtime
	call :_write_log %1 size !_size!
	call :_write_log %1 filemtime "!_filemtime!"

	call :_app_get_version %3 _v && (
		echo Detected version !_v!
		call :_write_log %1 version "!_v!"
	)

	call :_shims %1

	exit /b !ERRORLEVEL!


rem "File path" "@var Size" "@var File time"
:_get_file_properties
	endlocal
	set "%~2=%~z1"
	set "%~3=%~t1"
	exit /b !ERRORLEVEL!


rem "Zip file path" "Destination directory"
:_unzip
	call :_where 7z && (
		call :_un7zip %*
		exit /b !ERRORLEVEL!
	)
	>nul !JSCRIPT! unzip %*
	exit /b !ERRORLEVEL!


rem "@var 7zip file path" "@var Destination directory"
:_un7zip
	>nul 1>nul call 7z x -y -bso1 -bsp0 -aoa -o%2 %1
	exit /b !ERRORLEVEL!


rem "Application ID"
:_is_installed
	>nul 2>nul dir /b "!PINT_APPS_DIR!\%~1\*.*"
	exit /b !ERRORLEVEL!


rem "Application ID" "delete"
:_shims
	call :_db %1 shim
	call :_db %1 noshim
	call !PINT! shim "!PINT_APPS_DIR!\%~1" "!shim!" "!noshim!" %2
	exit /b 0


rem "@var Download URL" "@var Destination directory" "Download URL"
:_download
	SET "DEST_FILE="
	
	echo Downloading !%~1!
	
	if not exist "!%~2!" (
		md "!%~2!"
	) else (
		if not "%~x1"=="" (
			for /f "usebackq tokens=* delims=" %%i in (`2^>nul dir /b /s /a-d "!%~2!"`) do (
				if "%%~nxi"=="%~nx1" (
					SET DEST_FILE=%%~nxi
				)
			)
		)

		if not defined DEST_FILE (
			for /f "usebackq tokens=* delims=" %%i in (`2^>nul dir /b /s /a-d "!%~2!"`) do (
				if not defined DEST_FILE (
					SET DEST_FILE=%%~nxi
				) else (
					SET DEST_FILE=
					rd /S /Q "!%~2!"
					goto :_continue_curl
				)
			)
		)
	)

	:_continue_curl

	call :_where curl || (
		if not defined DEST_FILE (
			call :_filename "!%~1!" DEST_FILE
			set "DEST_FILE=!DEST_FILE:?=!"
			set "DEST_FILE=!DEST_FILE:;=!"
		)
		if not defined DEST_FILE set "DEST_FILE=download"
		call !PINT! download-file "!%~1!" "!%~2!\!DEST_FILE!" && exit /b 0
		echo Download FAILED. Install curl, in many cases this may help.
		exit /b 1
	)

	if defined DEST_FILE (
		"%ComSpec%" /d /c !CURL! -o "!%~2!\!DEST_FILE!" "!%~1!" || (
			echo FAILED
			exit /b 1
		)
	) else (
		pushd "!%~2!"
		"%ComSpec%" /d /c !CURL! -O -J "!%~1!" || (
			echo FAILED
			popd
			exit /b 1
		)
		popd
	)

	exit /b 0


rem "Path" "@var Filename"
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
	call :_read_ini !PINT_PACKAGES_FILE_USER! %* || (
		call :_read_ini !PINT_PACKAGES_FILE! %*
	)
	exit /b !ERRORLEVEL!


rem "Directory" "@var result"
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
	if not exist "%~1" (
		exit /b 1
	)

	SET SECTION=
	SET KEY=

	for /f "usebackq tokens=1* delims=^= " %%A in ("%~1") do (
		if not defined SECTION (
			if /I "%%A"=="[%~2]" (
				SET SECTION=1
			)
		) else (
			SET "KEY=%%A"

			if "!KEY:~0,1!"=="[" (
				exit /b 1
			)

			if not "%%B"=="" (
				if /I "%%A"=="%~3" (
					endlocal & (
						if not "%~4"=="" (
							SET "%~4=%%B"
						) else (
							SET "%%A=%%B"
						)
						exit /b 0
					)
				)
			)
		)
	)

	exit /b 1


rem "INI file path" "Section" "Key" "@var Value"
:_write_ini
	if "%~1"=="" (
		exit /b 1
	)

	set _file="%~1"

	if not "%~4"=="" (
		rem No file
		if not exist !_file! (
			>!_file! echo [%~2]
			>>!_file! echo %~3 = %~4
			exit /b !ERRORLEVEL!
		)
		rem No section
		>nul !FIND! "[%~2]" < !_file! || (
			>>!_file! echo [%~2]
			>>!_file! echo %~3 = %~4
			>nul !FIND! "[%~2]" < !_file!
			exit /b !ERRORLEVEL!
		)
	)

	SET _section=
	SET _added=
	SET _pending=
	SET _header=

	>nul copy /y NUL !PINT_TEMP_FILE!

	for /f "usebackq tokens=1* delims=^= " %%A in ("%~1") do (
		SET _header=%%A

		if "!_header:~0,1!"=="[" (
			SET _pending=%%A
		) else (
			SET _header=
		)

		if not defined _section (
			if defined _header (
				if not defined _added (
					if /I "%%A"=="[%~2]" (
						SET _section=1
					)
				)
			)
			if not defined _section (
				if not "%%B"=="" (
					if defined _pending (
						>>!PINT_TEMP_FILE! echo !_pending!
						SET _pending=
					)
					>>!PINT_TEMP_FILE! echo %%A = %%B
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
					if /I "%%A"=="%~3" (
						if not "%~4"=="" (
							if defined _pending (
								>>!PINT_TEMP_FILE! echo !_pending!
								SET _pending=
							)
							>>!PINT_TEMP_FILE! echo %~3 = %~4
							SET _added=1
						)
					) else (
						if not "%%B"=="" (
							if defined _pending (
								>>!PINT_TEMP_FILE! echo !_pending!
								SET _pending=
							)
							>>!PINT_TEMP_FILE! echo %%A = %%B
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
		if (!fso.FileExists(file + "\\" + zip.Items().Item(0))) {
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
			(new-object System.Net.WebClient).DownloadFile($env:_PARAM_1, $env:_PARAM_2)
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