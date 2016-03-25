@echo off
@setlocal enabledelayedexpansion

rem PINT - Portable INsTaller

if "%~1"=="" (
	call :usage
	exit /b 0
)

rem Set variables if they weren't overriden earlier
if not defined PINT_DIST_DIR set "PINT_DIST_DIR=%~dp0packages"
if not defined PINT_APPS_DIR set "PINT_APPS_DIR=%~dp0apps"
if not defined PINT_USER_AGENT set "PINT_USER_AGENT=User-Agent^: Mozilla/5.0 ^(Windows NT 6.1^; WOW64^; rv^:40.0^) Gecko/20100101 Firefox/40.1"
if not defined PINT_PACKAGES_FILE set PINT_PACKAGES_FILE="%~dp0packages.ini"
if not defined PINT_PACKAGES_FILE_USER set PINT_PACKAGES_FILE_USER="%~dp0packages.user.ini"
if not defined PINT_SRC_FILE set PINT_SRC_FILE="%~dp0sources.list"
if not defined PINT_TEMP_FILE set PINT_TEMP_FILE="%TEMP%\pint.tmp"
if not defined PINT_HISTORY_FILE set PINT_HISTORY_FILE="%~dp0local.ini"

rem Hardcoded URLs
set PINT_DEFAULT_PACKAGES=https^://raw.githubusercontent.com/vensko/pint/master/packages.ini
set PINT_SELF_URL=https^://raw.githubusercontent.com/vensko/pint/master/pint.bat
set PINT_CURL_URL="https^://bintray.com/artifact/download/vszakats/generic/curl-7.48.0-win32-mingw.7z"
set PINT_XIDEL_URL="http^://master.dl.sourceforge.net/project/videlibri/Xidel/Xidel#200.9/xidel-0.9.win32.zip"

rem Functions accessible directly from the command line
SET PUBLIC_FUNCTIONS=usage self-update update subscribe subscribed install reinstall installed download remove purge upgrade search outdated add pin unpin _write_ini _exetype

SET CURL=curl --insecure --ssl-no-revoke --ssl-allow-beast --progress-bar --remote-header-name --location --max-redirs 5 --retry 2 --retry-delay 1 -X GET
SET POWERSHELL=powershell -NonInteractive -NoLogo -NoProfile -executionpolicy bypass

rem Create directories if needed
if not exist "!PINT_APPS_DIR!" (
	mkdir "!PINT_APPS_DIR!"
)

if not exist !PINT_HISTORY_FILE! (
	copy /y NUL !PINT_HISTORY_FILE! >NUL
)

SET PINT="%~f0"
path !PINT_APPS_DIR!;%PATH%

rem Validate the environment and install missing tools
call :_has curl !PINT_CURL_URL! || (
	echo Unable to find curl
	exit /b 1
)
call :_has xidel !PINT_XIDEL_URL! || (
	echo Unable to find Xidel
	exit /b 1
)

if not %1==update (
	if not exist !PINT_PACKAGES_FILE! (
		call :update
	)
)

rem Ready, steady, go
for %%x in (!PUBLIC_FUNCTIONS!) do (
	if %1==%%x (
		call :%*
		if exist !PINT_TEMP_FILE! (
			del !PINT_TEMP_FILE!
		)
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
	echo Usage^:
	echo pint update^|self-update^|usage^|subscribed^|installed^|search^|outdated^|upgrade
	echo pint download^|install^|reinstall^|installed^|search^|outdated^|upgrade^|remove^|purge^|pin^|unpin ^<package(s)^>
	echo pint add ^<package^> ^<url^>
	echo pint subscribe ^<packages-ini-url^>
	exit /b 0


:self-update
	echo Fetching !PINT_SELF_URL!

	if exist !PINT_TEMP_FILE! (
		del !PINT_TEMP_FILE!
	)

	cmd /c "!CURL! -s -S -o !PINT_TEMP_FILE! "!PINT_SELF_URL!"" || (
		echo Self-update failed^^!
		exit /b 1
	)

	findstr /L /C:"PINT - Portable INsTaller" !PINT_TEMP_FILE! >nul || (
		echo Self-update failed^^!
		exit /b 1
	)

	(type !PINT_TEMP_FILE!) > !PINT!
	echo Pint was updated to the latest version.
	exit /b 0


:update
	SET /a SRC_COUNT=0

	if not exist !PINT_SRC_FILE! (
		(echo !PINT_DEFAULT_PACKAGES!) > !PINT_SRC_FILE!
	)

	copy /y NUL !PINT_PACKAGES_FILE! >nul

	for /f "usebackq delims=" %%f in ("!PINT_SRC_FILE:~1,-1!") do (
		set /p ="Fetching %%f "<nul

		cmd /c "!CURL! --compressed -s -S -o !PINT_TEMP_FILE! "%%f""

		if errorlevel 1 (
			echo - failed^^!
		) else (
			(type !PINT_TEMP_FILE!) >> !PINT_PACKAGES_FILE!
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
		findstr /I /R "^^\[.*%~1" !PINT_PACKAGES_FILE_USER! | sort
	)
	findstr /I /R "^^\[.*%~1" !PINT_PACKAGES_FILE! | sort
	exit /b 0


rem "INI URL"
:subscribe
	SET URL="%~1"
	findstr /L /X !URL! !PINT_SRC_FILE! >nul && (
		echo This URL is already registered.
		exit /b 1
	)
	(echo !URL:~1,-1!) >> !PINT_SRC_FILE!
	echo Registered !URL:~1,-1!
	exit /b 0


:installed
	if "%*"=="" (
		dir /b /ad "!PINT_APPS_DIR!" 2>nul
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
	for /f "usebackq delims=" %%x in (`dir /b /ad "!PINT_APPS_DIR!" 2^>nul`) do (
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

	call :_curl "%~2" "!PINT_DIST_DIR!\%~1" || (
		echo Unable to download %1 from %~2.
		exit /b 1
	)

	call :_install_app %1 && (
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
	for /f "usebackq delims=" %%x in (`dir /b /ad "!PINT_APPS_DIR!" 2^>nul`) do (
		call :_package_upgrade %%x
	)
	exit /b !ERRORLEVEL!

:purge
	if "%~1"=="" (
		if exist "!PINT_DIST_DIR!" (
			rmdir /S /Q "!PINT_DIST_DIR!"
		)
		exit /b 0
	)

	for %%x in (%*) do (
		call :_package_purge %%x
	)
	exit /b !ERRORLEVEL!


rem "Application ID"
:_package_pin
	call :_write_local %1 pinned 1 && (
		echo %~1 is pinned.
	)
	exit /b !ERRORLEVEL!

rem "Application ID"
:_package_unpin
	call :_write_local %1 pinned && (
		echo %~1 is unpinned.
	)
	exit /b !ERRORLEVEL!


rem "Application ID"
:_package_remove
	call :_is_installed %1 && (
		echo Uninstalling %~1...
	)
	call :_app_del_shims %1
	if exist "!PINT_APPS_DIR!\%~1" (
		rmdir /S /Q "!PINT_APPS_DIR!\%~1"
	)
	exit /b 0


rem "Application ID"
:_package_purge
	echo Removing the %~1 package...

	call :_package_remove %1
	if exist "!PINT_DIST_DIR!\%~1" (
		rmdir /S /Q "!PINT_DIST_DIR!\%~1"
	)
	call :_write_local %1

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

	call :_url_is_updated %1 "!dist!" || (
		exit /b 1
	)

	echo %1 is OUTDATED.
	exit /b 0


rem "Application ID" "Update"
:_package_download
	call :_get_dist_link %1 dist || (
		echo Unable to get a link for %1.
		exit /b 1
	)
	call :_curl "!dist!" "!PINT_DIST_DIR!\%~1" || (
		echo Unable to download an update for %1.
		exit /b 1
	)
	exit /b 0


:_package_force_install
	call :_is_upgradable || (
		exit /b 1
	)

	call :_db %1 deps && (
		for %%x in (!deps!) do (
			call :_package_install %%x
		)
	)

	call :_get_dist_link %1 dist || (
		echo Unable to get a link for %1.
		exit /b 1
	)

	call :_curl "!dist!" "!PINT_DIST_DIR!\%~1" || (
		echo Unable to download %1.
		exit /b 1
	)

	call :_install_app %1
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

	call :_get_dist_link %1 dist || (
		echo Unable to get a link for %1.
		exit /b 1
	)

	call :_url_is_updated %1 "!dist!"
	if !ERRORLEVEL!==1 (
		exit /b 0
	)

	call :_curl "!dist!" "!PINT_DIST_DIR!\%~1" || (
		echo Unable to download an update for %1.
		exit /b 1
	)

	call :_install_app %1
	exit /b !ERRORLEVEL!


rem "Application ID"
:_is_upgradable
	call :_history %1 pinned
	if defined pinned (
		echo Updates for %~1 are suppressed. To allow this install, use^: pint unpin %~1
		exit /b 1
	)
	exit /b 0


rem "Application ID" "DIST Variable name"
:_get_dist_link
	endlocal & (
		SET "%~2="
	)

	SET "link="
	SET "referer="

	if "%PROCESSOR_ARCHITECTURE%"=="x86" (
		call :_db %1 dist
		call :_db %1 link
	) else (
		call :_db %1 dist64 dist || (
			call :_db %1 dist
		)
		call :_db %1 link64 link || (
			call :_db %1 link
		)
	)

	if not defined dist (
		exit /b 1
	)

	if defined link (
		if not "!link!"=="!link:/a=!" (
			SET "link=!link!/resolve-uri(normalize-space(@href), base-uri())"
		)
		SET link=!link:^"=\"!
		SET referer=--referer "!dist!"
		for /f "usebackq delims=" %%i in (`xidel "!dist!" -e "(!link:%%=%%%%!)[1]" --quiet --header="Referer^: !dist!" --user-agent="!PINT_USER_AGENT!"`) do (
			set "dist=%%i"
		)
	)

	if not defined dist (
		exit /b 1
	)

	if not "!dist!"=="!dist:fosshub.com/=!" (
		set dist=!dist:fosshub.com/=fosshub.com/genLink/!
		set dist=!dist:.html/=/!
		for /f "usebackq delims=" %%i in (`!CURL! -s !referer! "!dist!"`) do (
			set "dist=%%i"
		)
	)

	if not defined dist (
		exit /b 1
	)

	SET "dist=!dist:%%=#!"

	endlocal & (
		SET "%~2=!dist!"
	)

	exit /b 0


rem "Application ID" "File URL"
:_url_is_updated
	call :_history %1 size

	if not defined size (
		echo %1 is not tracked by Pint, try to reinstall.
		exit /b 2
	)

	call :_diff_size %2 "!size!" %1 || (
		exit /b !ERRORLEVEL!
	)

	exit /b 0


rem "URL" "File size" "Application ID"
:_diff_size
	SET "EXISTS="
	SET URL=%~1
	SET URL="!URL:#=%%!"

	cmd /c "!CURL! -s -S -I "!URL:~1,-1!" -o !PINT_TEMP_FILE!"

	findstr /L /C^:" 200 OK" !PINT_TEMP_FILE! >nul && (
		SET EXISTS=1
	)

	findstr /L /C^:" SIZE " !PINT_TEMP_FILE! >nul && (
		SET EXISTS=1
	)

	if not defined EXISTS (
		echo Unable to check updates for %3.
		exit /b 3
	)

	findstr /L /C^:" %~2" !PINT_TEMP_FILE! >nul || (
		exit /b 0
	)

	echo %3 is up to date.
	exit /b 1
	

rem "Application ID"
:_install_app
	for /f "usebackq delims=" %%i in (`dir /b /s /a-d "!PINT_DIST_DIR!\%~1" 2^>nul`) do (
		call :install_file %1 "%%i"
	)
	exit /b !ERRORLEVEL!


rem "Application ID" "File path"
:install_file
	set "DEST=!PINT_APPS_DIR!\%~1"

	if not exist "!DEST!" (
		mkdir "!DEST!"
	)

	echo Installing %~1 to !DEST!

	if /I "%~x2"==".msi" (
		call msiexec /a %2 /norestart /qn TARGETDIR="!DEST!"
	) else (
		if /I "%~x2"==".zip" (
			call :_unzip %2 "!DEST!"
		) else (
			call :_db %1 type
			if /I !type!==standalone (
				copy /Y %2 /B "!DEST!" >nul
			) else (
				call :_un7zip %2 "!DEST!"
			)
		)
	)

	if errorlevel 1 (
		exit /b !ERRORLEVEL!
	)

	call :_postinstall %1 %2 "!DEST!"
	exit /b !ERRORLEVEL!


rem "Application ID" "File path" "Destination directory"
:_postinstall
	call :_db %1 exclude

	if defined exclude (
		for %%x in (!exclude!) do (
			if exist "%~3\%%x" (
				if exist "%~3\%%x\*" (
					rmdir /S /Q "%~3\%%x"
				) else (
					del /S /Q "%~3\%%x"
				)
			)
		)
	)

	call :_write_local %1 size %~z2
	call :_write_local %1 filemtime "%~t2"

	call :_app_get_version %1
	call :_app_make_shims %1

	exit /b 0


rem "Zip file path" "Destination directory"
:_unzip
	where /Q 7z && (
		call :_un7zip %*
		exit /b !ERRORLEVEL!
	)

	where /Q powershell || (
		call :_un7zip %*
		exit /b !ERRORLEVEL!
	)

	set "_zip=%~1"
	set "_destdir=%~2"

	if not exist %2 mkdir %2

	call !POWERSHELL! -command "^& { $shell = new-object -com shell.application; $zip = $shell.NameSpace($env^:_zip); $shell.Namespace($env^:_destdir).copyhere($zip.items(), 20); }"

	exit /b !ERRORLEVEL!


rem "7zip file path" "Destination directory"
:_un7zip
	where /Q 7z || (
		call :_package_install 7-zip
	)
	call 7z x -y -aoa -o"%~2" %1 >nul
	exit /b !ERRORLEVEL!


rem "Application ID"
:_is_installed
	dir /b /s "!PINT_APPS_DIR!\%~1\*.exe" >nul 2>nul
	exit /b !ERRORLEVEL!


rem "Application ID"
:_app_del_shims
	if not exist "!PINT_APPS_DIR!\%~1" (
		exit /b 0
	)

	for /f "usebackq delims=" %%i in (`cd "!PINT_APPS_DIR!\%~1" 2^>nul ^&^& dir /b /s /a-d *.exe *.bat *.cmd 2^>nul`) do (
		if exist "!PINT_APPS_DIR!\%%~ni.bat" (
			del "!PINT_APPS_DIR!\%%~ni.bat"
		)
	)

	exit /b !ERRORLEVEL!


rem "Application ID"
:_app_make_shims
	if not exist "!PINT_APPS_DIR!\%~1" (
		exit /b 0
	)

	call :_app_del_shims %1

	call :_db %1 shim
	call :_db %1 noshim

	for /f "usebackq delims=" %%i in (`dir /b /s /a-d "!PINT_APPS_DIR!\%~1\*.exe" 2^>nul`) do (
		SET "PASS=1"

		if defined noshim (
			for %%e in (!noshim!) do (
				if /I "%%~nxi"=="%%~nxe" (
					SET "PASS=0"
				)
			)
		)

		if not !PASS!==0 (
			call :_exetype "%%i" _subsystem
			if not !_subsystem!==3 (
				SET "PASS=0"
			)
		)

		if !PASS!==1 (
			call :_shim "!PINT_APPS_DIR!\%~1" "%%i"
		)
	)

	if not defined shim (
		exit /b 0
	)

	for /f "usebackq delims=" %%i in (`cd "!PINT_APPS_DIR!\%~1" 2^>nul ^&^& dir /b /s /a-d !shim! 2^>nul`) do (
		call :_shim "!PINT_APPS_DIR!\%~1" "%%i"
	)

	exit /b 0


rem "Base path" "Executable file"
:_shim
	for /f "usebackq delims=" %%i in (`forfiles /S /P "%~1" /M "%~nx2" /C "cmd /c echo @relpath"`) do (
		SET RELPATH=%%i

		if "!RELPATH:~1,1!"=="." (
			SET RELPATH="%%~dp0%~n1\!RELPATH:~3,-1!"
		)

		>"!PINT_APPS_DIR!\%~n2.bat" (
			echo @echo off
			echo !RELPATH! %%*
			echo exit /b %%ERRORLEVEL%%
		)

		echo Added a shim for %%~nxi
	)

	exit /b !ERRORLEVEL!


rem "Download URL" "Destination directory"
:_curl
	SET "DEST_FILE="
	SET URL="%~1"
	SET "URL=!URL:#=%%!"
	
	echo Downloading !URL:~1,-1!
	
	if not exist "%~2" (
		mkdir "%~2"
	) else (
		if not "%~x1"=="" (
			for /f "usebackq delims=" %%i in (`dir /b /s /a-d "%~2" 2^>nul`) do (
				if "%%~nxi"=="%~nx1" (
					SET DEST_FILE=%%~nxi
				)
			)
		)

		if not defined DEST_FILE (
			for /f "usebackq delims=" %%i in (`dir /b /s /a-d "%~2" 2^>nul`) do (
				if not defined DEST_FILE (
					SET DEST_FILE=%%~nxi
				) else (
					SET DEST_FILE=
					rmdir /S /Q "%~2"
					goto :_continue_curl
				)
			)
		)
	)

	if not "%~x1"=="" (
		if not defined DEST_FILE (
			SET DEST_FILE=%~nx1
		)
	)

	:_continue_curl

	if defined DEST_FILE (
		cmd /c "!CURL! -o "%~2\!DEST_FILE!" "!URL:~1,-1!"" && (
			exit /b 0
		)
		if not errorlevel 1 exit /b 0
	) else (
		if not exist "%~2" (
			mkdir "%~2"
		)
		cmd /c "cd /D ^"%~2^" ^&^& !CURL! -O -J ^"!URL:~1,-1!^"" && (
			exit /b 0
		)
	)

	echo FAILED (code !ERRORLEVEL!)
	echo.
	exit /b 1


rem "Download URL" "Destination directory"
:_download_ps
	SET URL="%~1"
	SET "URL=!URL:#=%%!"

	echo Downloading: !URL:~1,-1!

	if not exist "%~2" (
		mkdir "%~2"
	)

	set "_url=!URL:~1,-1!"
	set "_destfile=%~2\%~nx1"

	call !POWERSHELL! -command "^& { (new-object System.Net.WebClient).DownloadFile($env^:_url, $env^:_destfile); }" && (
		exit /b 0
	)

	echo FAILED (code !ERRORLEVEL!)
	echo.
	exit /b 1


rem "Section" "Key" "Variable name (optional)"
:_history
	call :_read_ini !PINT_HISTORY_FILE! %*
	exit /b !ERRORLEVEL!


rem "Section" "Key" "Value"
:_write_local
	call :_write_ini !PINT_HISTORY_FILE! %*
	exit /b !ERRORLEVEL!


rem "Section" "Key" "Variable name (optional)"
:_db
	call :_read_ini !PINT_PACKAGES_FILE_USER! %* || (
		call :_read_ini !PINT_PACKAGES_FILE! %*
	)
	exit /b !ERRORLEVEL!


rem "Application ID"
:_app_get_version
	for /f "usebackq delims=" %%i in (`dir /b /s /a-d /o-s "!PINT_APPS_DIR!\%~1\*.exe" 2^>nul`) do (
		call :_filever "%%i" _ver
		if defined _ver (
			call :_write_local %1 version !_ver!
			exit /b 0
		)
		exit /b 1
	)
	exit /b 1


rem "Executable path" "Variable name"
:_filever
	if "%~2"=="" (
		exit /b 1
	)

	endlocal & (
		SET "%~2="
	)

	if /I not "%~x1"==".exe" (
		exit /b 1
	)

	if not exist "%~1" (
		exit /b 1
	)

	SET "_exefile=%~1"
	SET "_exefile=!_exefile:\=\\!"

	for /f "usebackq skip=1" %%a in (`wmic datafile where name^="!_exefile!" get version 2^>nul`) do (
		SET _ver=%%a

		for %%x in (1 2 3 4) do (
			if "!_ver:~-2!"==".0" set _ver=!_ver:~0,-2!
		)

		endlocal
		SET "%~2=!_ver!"
		exit /b 0
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


rem "INI file path" "Section" "Key" "Value"
:_write_ini
	if "%~1"=="" (
		exit /b 1
	)

	set _file="%~1"

	if not "%~4"=="" (
		rem No file
		if not exist !_file! (
			>!_file! (
				echo [%~2]
				echo %~3 = %~4
			)
			exit /b !ERRORLEVEL!
		)
		rem No section
		find "[%~2]" < !_file! > nul || (
			(echo [%~2]) >> !_file!
			(echo %~3 = %~4) >> !_file!
			find "[%~2]" < !_file! > nul
			exit /b !ERRORLEVEL!
		)
	)

	SET _section=
	SET _added=
	SET _pending=
	SET _header=

	copy /y NUL !PINT_TEMP_FILE! >NUL

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
						(echo !_pending!) >> !PINT_TEMP_FILE!
						SET _pending=
					)
					(echo %%A = %%B) >> !PINT_TEMP_FILE!
				)
			)
		) else (
			rem Reached next section, but not found yet
			if defined _header (
				if not defined _added (
					if not "%~4"=="" (
						(echo %~3 = %~4) >> !PINT_TEMP_FILE!
						SET _added=1
						if defined _pending (
							(echo !_pending!) >> !PINT_TEMP_FILE!
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
								(echo !_pending!) >> !PINT_TEMP_FILE!
								SET _pending=
							)
							(echo %%A = %~4) >> !PINT_TEMP_FILE!
							SET _added=1
						)
					) else (
						if not "%%B"=="" (
							if defined _pending (
								(echo !_pending!) >> !PINT_TEMP_FILE!
								SET _pending=
							)
							(echo %%A = %%B) >> !PINT_TEMP_FILE!
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
					(echo !_pending!) >> !PINT_TEMP_FILE!
					SET _pending=
				)
				(echo %~3 = %~4) >> !PINT_TEMP_FILE!
			)
		)
	)

	(type !PINT_TEMP_FILE!) > !_file!
	del !PINT_TEMP_FILE!

	exit /b 0


rem "Executable path" "Subsystem variable" "Arch variable"
:_exetype
	endlocal & (
		if not "%~2"=="" (
			SET "%~2="
		)
		if not "%~3"=="" (
			SET "%~3="
		)
	)

	if /I "%~x1"==".cmd" (
		exit /b 0
	)
	if /I "%~x1"==".bat" (
		exit /b 0
	)
	if /I not "%~x1"==".exe" (
		exit /b 1
	)

	set _subsystem=
	set _arch=
	set "_file=%~1"
	set "_command=!POWERSHELL! -command ^"^& { try { $fs = [IO.File]^:^:OpenRead((Convert-Path ^"$env^:_file^")); $br = New-Object IO.BinaryReader($fs); if ($br.ReadUInt16() -ne 23117) { exit 1 } $fs.Position = 0x3C; $fs.Position = $br.ReadUInt32(); $offset = $fs.Position; if ($br.ReadUInt32() -ne 17744) { exit 1 } $fs.Position += 0x14; $bit = 0; switch ($br.ReadUInt16()) { 0x10B { ^"SET _arch^=32^" } 0x20B { ^"SET _arch^=64^" } } $fs.Position = $offset + 4 + 20 + 68; $subsystem = $br.ReadUInt16(); ^"SET _subsystem^=$subsystem^"; exit 0 } catch { $_.Exception; exit 65535 } finally { if ($br  -ne $null) { $br.Close() } if ($fs  -ne $null) { $fs.Close() } } }^""

	for /f "usebackq delims=" %%i in (`!_command!`) do %%i

	endlocal & (
		if not "%~2"=="" (
			SET "%~2=!_subsystem!"
		)
		if not "%~3"=="" (
			SET "%~3=!_arch!"
		)
	)

	if !ERRORLEVEL!==3 (
		exit /b 0
	)

	exit /b 1


rem Installs missing executables
rem "Application ID" "Download URL"
:_has
	where /Q %1 && (
		exit /b 0
	)

	if exist "!PINT_DIST_DIR!\%~1" (
		rmdir /S /Q "!PINT_DIST_DIR!\%~1"
	)

	call :_download_ps "%~2" "!PINT_DIST_DIR!\%~1"

	for /f "usebackq delims=" %%i in (`dir /b /s /a-d "!PINT_DIST_DIR!\%~1\*" 2^>nul`) do (
		call :install_file %1 "%%i"
		goto :continue_has
	)

	:continue_has
	where /Q %1
	exit /b !ERRORLEVEL!