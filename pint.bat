@echo off
@setlocal enabledelayedexpansion

rem PINT - Portable INsTaller

rem Set variables if they weren't overriden earlier
if not defined PINT_DIST_DIR set "PINT_DIST_DIR=%~dp0packages"
if not defined PINT_APPS_DIR set "PINT_APPS_DIR=%~dp0apps"
if not defined PINT_USER_AGENT set "PINT_USER_AGENT=User-Agent^: Mozilla/5.0 ^(Windows NT 6.1^; WOW64^; rv^:40.0^) Gecko/20100101 Firefox/40.1"
if not defined PINT_PACKAGES_FILE set PINT_PACKAGES_FILE="%~dp0packages.ini"
if not defined PINT_PACKAGES_FILE_USER set PINT_PACKAGES_FILE_USER="%~dp0packages.user.ini"
if not defined PINT_SRC_FILE set PINT_SRC_FILE=%~dp0sources.list
if not defined PINT_TEMP_FILE set "PINT_TEMP_FILE=%TEMP%\pint.tmp"
if not defined PINT_HISTORY_FILE set PINT_HISTORY_FILE="%~dp0local.ini"

rem Hardcoded URLs
set PINT_DEFAULT_PACKAGES=https://raw.githubusercontent.com/vensko/pint/master/packages.ini
set PINT_SELF_URL=https://raw.githubusercontent.com/vensko/pint/master/pint.bat
set PINT_EXETYPE_URL="http://smithii.com/files/exetype-1.1-win32.zip"
set PINT_WGET_URL="https://eternallybored.org/misc/wget/current/wget.exe"
set PINT_INIFILE_URL="http://www.horstmuc.de/win/inifile.zip"
set PINT_7ZA_URL="https://github.com/chocolatey/choco/raw/master/src/chocolatey.resources/tools/7za.exe"
set PINT_XIDEL_URL="http://master.dl.sourceforge.net/project/videlibri/Xidel/Xidel#200.9/xidel-0.9.win32.zip"

rem Functions accessible directly from the command line
SET PUBLIC_FUNCTIONS=usage self-update update subscribe subscribed install reinstall installed download remove purge upgrade search outdated

SET DB_LOCAL=inifile !PINT_HISTORY_FILE!

SET WGET=wget -t 2 --retry-connrefused --no-check-certificate --content-disposition

rem Create directories if needed
if not exist "!PINT_DIST_DIR!" mkdir "!PINT_DIST_DIR!"
if not exist "!PINT_APPS_DIR!" mkdir "!PINT_APPS_DIR!"
if not exist !PINT_HISTORY_FILE! copy /y NUL !PINT_HISTORY_FILE! >NUL

SET PINT="%~f0"

path !PINT_APPS_DIR!;%PATH%

rem Validate the environment and install missing tools
call :_has exetype !PINT_EXETYPE_URL! || echo Unable to find exetype && exit /b 1
call :_has inifile !PINT_INIFILE_URL! || echo Unable to find inifile && exit /b 1
call :_has wget    !PINT_WGET_URL!    || echo Unable to find Wget    && exit /b 1
call :_has 7za     !PINT_7ZA_URL!     || echo Unable to find 7za     && exit /b 1
call :_has xidel   !PINT_XIDEL_URL!   || echo Unable to find Xidel   && exit /b 1

rem Ready, steady, go
if "%~1"=="" call :usage & exit /b 0

if not %1==update if not exist !PINT_PACKAGES_FILE! call :update

for %%x in (!PUBLIC_FUNCTIONS!) do (
	if %1==%%x (
		call :%*
		if exist "!PINT_TEMP_FILE!" del "!PINT_TEMP_FILE!"
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
	echo pint update^|self-update^|usage^|subscribed^|installed^|search^|outdated
	echo pint download^|install^|reinstall^|installed^|search^|outdated^|upgrade^|remove^|purge ^<packages^>
	echo pint subscribe ^<packages-ini-url^>
	exit /b 0


:self-update
	echo Fetching !PINT_SELF_URL!

	if exist "!PINT_TEMP_FILE!" del "!PINT_TEMP_FILE!"

	cmd /c "!WGET! -qO- "!PINT_SELF_URL!""> "!PINT_TEMP_FILE!"

	if errorlevel 1 (
		echo Self-update failed^^!
		exit /b 1
	) else (
		findstr /L /C:"PINT - Portable INsTaller" "!PINT_TEMP_FILE!" >nul

		if errorlevel 1 (
			echo Self-update failed^^!
			exit /b 1
		) else (
			type "!PINT_TEMP_FILE!" > !PINT!
			echo Pint was updated to the latest version.
			exit /b 0
		)
	)


:update
	SET /a SRC_COUNT=0

	if not exist "!PINT_SRC_FILE!" echo !PINT_DEFAULT_PACKAGES!> "!PINT_SRC_FILE!"

	copy /y NUL !PINT_PACKAGES_FILE! >NUL

	for /F "delims=" %%f in (!PINT_SRC_FILE!) do (
		set /p ="Fetching %%f "<nul

		cmd /c "!WGET! -qO- "%%f""> "!PINT_TEMP_FILE!"

		if errorlevel 1 (
			echo - failed^^!
		) else (
			type "!PINT_TEMP_FILE!" >> !PINT_PACKAGES_FILE!
			SET /a SRC_COUNT+=1
			echo.
		)
	)

	set /p ="Merged !SRC_COUNT! source"<nul
	if not !SRC_COUNT!==1 echo s

	exit /b 0


:subscribed
	type "!PINT_SRC_FILE!"
	exit /b !ERRORLEVEL!


rem "Term"
:search
	if not exist !PINT_PACKAGES_FILE! call :update
	if exist !PINT_PACKAGES_FILE_USER! findstr /I /R "^^\[.*%~1" !PINT_PACKAGES_FILE_USER! | sort
	findstr /I /R "^^\[.*%~1" !PINT_PACKAGES_FILE! | sort
	exit /b 0


rem "INI URL"
:subscribe
	SET URL="%~1"
	call findstr /L /X !URL! "!PINT_SRC_FILE!" >nul && echo This URL is already registered. && exit /b 1
	>>"!PINT_SRC_FILE!" echo !URL:~1,-1!
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
		for %%x in (%*) do call :_package_outdated %%x
		exit /b !ERRORLEVEL!
	)
	for /f "usebackq delims=" %%x in (`dir /b /ad "!PINT_APPS_DIR!" 2^>nul`) do call :_package_outdated %%x
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
	for %%x in (%*) do call :_package_upgrade %%x
	exit /b !ERRORLEVEL!

:purge
	if "%~1"=="" (
		if exist !PINT_HISTORY_FILE! del !PINT_HISTORY_FILE!
		if exist "!PINT_DIST_DIR!" rmdir /S /Q "!PINT_DIST_DIR!"
		exit /b 0
	)

	for %%x in (%*) do call :_package_purge %%x
	exit /b !ERRORLEVEL!


rem "Application ID"
:_package_remove
	call :_is_installed %1
	if not errorlevel 1 echo Uninstalling %~1...

	call :app_del_shims %1
	if exist "!PINT_APPS_DIR!\%~1" rmdir /S /Q "!PINT_APPS_DIR!\%~1"
	!DB_LOCAL! [%~1] ts_setup=

	exit /b 0


rem "Application ID"
:_package_purge
	echo Removing the %~1 package...

	call :remove %1
	if exist "!PINT_DIST_DIR!\%~1" rmdir /S /Q "!PINT_DIST_DIR!\%~1"
	!DB_LOCAL! [%~1] /remove

	exit /b 0


rem "Application ID"
:_package_outdated
	call :_is_installed %1
	if errorlevel 1 echo %1 is not installed.&& exit /b 1

	call :_get_dist_link %1 dist
	if not defined dist echo Unable to get a link for %1.&& exit /b 1

	call :_url_is_updated %1 "!dist!"
	if errorlevel 2 echo Unable to check updates for %1.&& exit /b 0
	if errorlevel 1 echo %1 is up to date.&& exit /b 0

	echo %1 is OUTDATED.
	exit /b 0


rem "Application ID" "Update"
:_package_download
	call :_get_dist_link %1 dist
	if not defined dist echo Unable to get a link for %1.&& exit /b 1

	call :_download_wget "!dist!" "!PINT_DIST_DIR!\%~1"
	if errorlevel 1 echo Unable to download an update for %1.&& exit /b 1

	exit /b !ERRORLEVEL!


:_package_force_install
	call :_db %1 deps
	if defined deps for %%x in (!deps!) do call :_package_install %%x

	call :_get_dist_link %1 dist
	if not defined dist echo Unable to get a link for %1.&& exit /b 1

	call :_download_wget "!dist!" "!PINT_DIST_DIR!\%~1"
	if errorlevel 1 echo Unable to download %1.&& exit /b 1

	call :_install_app %1
	exit /b !ERRORLEVEL!


rem "Application ID"
:_package_install
	call :_is_installed %~1 && echo %~1 is already installed.&& exit /b 0
	call :_package_force_install %1
	exit /b !ERRORLEVEL!


rem "Application ID"
:_package_upgrade
	call :_is_installed %1
	if errorlevel 1 ( call :_package_install %1 & exit /b !ERRORLEVEL! )

	call :_db %1 deps
	if defined deps for %%x in (!deps!) do call :_package_upgrade "%%x"

	call :_get_dist_link %1 dist
	if not defined dist echo Unable to get a link for %1.&& exit /b 1

	call :_url_is_updated %1 "!dist!"
	if !ERRORLEVEL!==2 echo Unable to check remote file size of %1, trying to download.
	if !ERRORLEVEL!==1 ( echo %1 is up to date.&& exit /b 0 )

	call :_download_wget "!dist!" "!PINT_DIST_DIR!\%~1"
	if errorlevel 1 (
		echo Unable to download an update for %1.
		exit /b 1
	)

	call :_install_app %1

	exit /b !ERRORLEVEL!


rem "Application ID" "Variable name"
:_get_dist_link
	@endlocal

	if "%PROCESSOR_ARCHITECTURE%"=="x86" (
		call :_db %1 dist
		call :_db %1 link
	) else (
		call :_db %1 dist64 dist || call :_db %1 dist
		call :_db %1 link64 link || call :_db %1 link
	)

	if not defined dist exit /b 1

	if defined link if not "!link!"=="!link:/a=!" set link=!link!/resolve-uri(normalize-space(@href), base-uri())
	if defined link set link=!link:^"=\"!

	if defined link for /f "usebackq delims=" %%i in (`xidel "!dist!" -e "(!link:%%=%%%%!)[1]" --quiet --user-agent="!PINT_USER_AGENT!"`) do set "dist=%%i"

	if "!dist!"=="" exit /b 1

	if not "!dist!"=="!dist:fosshub.com/=!" (
		set dist=!dist:fosshub.com/=fosshub.com/genLink/!
		set dist=!dist:.html/=/!
		for /f "usebackq delims=" %%i in (`!WGET! "!dist!" -qO-`) do set "dist=%%i"
	)

	if "!dist!"=="" exit /b 1

	SET "dist=!dist:%%=#!"

	exit /b 0


rem "Application ID" "File URL"
:_url_is_updated
	call :_history %1 size
	if not defined size exit /b 0

	call :_diff_remote_size "%~2" "!size!"
	if errorlevel 1 exit /b !ERRORLEVEL!

	exit /b 0


rem "URL" "File size"
:_diff_remote_size
	SET "EXISTS="
	SET URL=%~1
	SET URL="!URL:#=%%!"

	if not "!URL!"=="!URL:github.com/=!" (
		if not "!URL!"=="!URL:releases/download=!" (
			echo Checking updates via Github Releases is not supported ^(yet^).
			exit /b 0
		)
	)

	cmd /c "!WGET! -S -q --spider "!URL:~1,-1!" -O - 2^>^&1" > "!PINT_TEMP_FILE!"

	findstr /L /C:" 200 OK" "!PINT_TEMP_FILE!" >nul && SET EXISTS=1
	findstr /L /C:" SIZE " "!PINT_TEMP_FILE!" >nul && SET EXISTS=1
	if not defined EXISTS exit /b 2

	rem NOT UPDATED
	findstr /L /C:" %~2" "!PINT_TEMP_FILE!" >nul && exit /b 1

	rem EXISTS AND UPDATED
	exit /b 0
	

rem "Application ID"
:_install_app
	for /f "usebackq delims=" %%i in (`dir /b /s /a-d "!PINT_DIST_DIR!\%~1" 2^>nul`) do call :install_file %1 "%%i"
	exit /b !ERRORLEVEL!


rem "Application ID" "File path"
:install_file
	set "DEST=!PINT_APPS_DIR!\%~1"
	if not exist "!DEST!" mkdir "!DEST!"

	echo Installing %~1 to !DEST!

	if /I "%~x2"==".msi" (
		msiexec /a %2 /norestart /qn TARGETDIR="!DEST!"
	) else (
		call :_db %1 type || SET "type=%~x2" && SET "type=!type:~1!"

		if /I "%~1"=="7za" set "type=standalone"
		if /I "%~1"=="wget" set "type=standalone"

		if /I !type!==standalone (
			copy /Y %2 /B "!DEST!" >nul
		) else (
			if /I !type!==zip (
				call :_unzip %2 "!DEST!"
			) else (
				if /I !type!==rar (
					where /Q unrar || call :_package_install unrar
					unrar x -u -inul %2 "!DEST!"
				) else (
					where /Q 7z || call :_package_install 7-zip
					call :_un7zip %2 "!DEST!"
				)
			)
		)
	)

	call :_postinstall %1 %2 "!DEST!"
	exit /b !ERRORLEVEL!


rem "Application ID" "File path" "Destination directory"
:_postinstall
	call :_is_installed %1 || exit /b 1

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

	call !DB_LOCAL! [%~1] "ts_setup=%~t2"
	call !DB_LOCAL! [%~1] "size=%~z2"
	call :_app_make_shims %1

	exit /b 0


rem "Zip file path" "Destination directory"
:_unzip
	call :_un7zip %*
	if !ERRORLEVEL! LSS 2 exit /b 0

	where /Q unzip && unzip -u %1 -d %2 & exit /b !ERRORLEVEL!

	where /Q powershell || exit /b 1

	if not exist %2 mkdir %2
	powershell -command "& { $shell = new-object -com shell.application; $zip = $shell.NameSpace($args[0]); $shell.Namespace($args[1]).copyhere($zip.items()); }" %1 %2
	exit /b !ERRORLEVEL!


rem "7zip file path" "Destination directory"
:_un7zip
	SET "SEVENZIP=7za"
	where /Q 7z && SET "SEVENZIP=7z"
	call !SEVENZIP! x -y -aoa -o"%~2" %1 >nul
	exit /b !ERRORLEVEL!


rem "Application ID"
:_is_installed
	cmd /d /c "cd ""!PINT_APPS_DIR!\%~1"" && dir /b /s *.exe" >nul 2>nul
	exit /b !ERRORLEVEL!


rem "Application ID"
:_app_make_shims
	call :_db %1 shim
	call :_db %1 noshim

	for /f "usebackq delims=" %%i in (`dir /b /s /a-d "!PINT_APPS_DIR!\%~1\*.exe" 2^>nul`) do (
		SET "PASS=1"

		call :_is_cli "%%i"
		if errorlevel 1 SET "PASS=0"

		if defined shim (
			for %%e in (!shim!) do (
				if /I "%%~nxi"=="%%~nxe" SET "PASS=1"
			)
		)

		if defined noshim (
			for %%e in (!noshim!) do (
				if /I "%%~nxi"=="%%~nxe" SET "PASS=0"
			)
		)

		if !PASS!==1 call :_shim "!PINT_APPS_DIR!\%~1" "%%i"
	)

	exit /b 0


rem "Application ID"
:app_del_shims
	forfiles /P "!PINT_APPS_DIR!\%~1" /M "*.exe" /S /C "cmd /d /c if exist "!PINT_APPS_DIR!\@fname.bat" del "!PINT_APPS_DIR!\@fname.bat"" >nul 2>&1
	exit /b !ERRORLEVEL!


rem "Base path" "Executable file"
:_shim
	for /f "usebackq delims=" %%i in (`forfiles /S /P "%~1" /M "%~nx2" /C "cmd /c echo @relpath"`) do (
		SET RELPATH=%%i
		if "!RELPATH:~1,1!"=="." SET RELPATH="%%~dp0%~n1\!RELPATH:~3,-1!"

		>"!PINT_APPS_DIR!\%~n2.bat" (
			echo @echo off
			echo !RELPATH! %%*
			echo exit /b %%ERRORLEVEL%%
		)

		echo Added a shim for %%~nxi
	)

	exit /b !ERRORLEVEL!


rem "Executable file"
:_is_cli
	if /I "%~nx1"=="exetype.exe" exit /b 0
	call exetype -q "%~1" 2>nul
	if !ERRORLEVEL!==3 exit /b 0
	exit /b 1


rem "Download URL" "Destination directory"
:_download_wget
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
					goto :_continue_download_wget
				)
			)
		)
	)

	if not "%~x1"=="" (
		if not defined DEST_FILE (
			SET DEST_FILE=%~nx1
		)
	)

	:_continue_download_wget

	if defined DEST_FILE (
		cmd /c "!WGET! -q -N -O "%~2\!DEST_FILE!" "!URL:~1,-1!""
		if not errorlevel 1 exit /b 0
	) else (
		cmd /c "!WGET! -q --directory-prefix="%~2" "!URL:~1,-1!""
		if not errorlevel 1 exit /b 0
	)

	echo FAILED (code !ERRORLEVEL!) && echo.
	exit /b 1


rem "Download URL" "Destination directory"
:_download_ps
	SET URL="%~1"
	SET "URL=!URL:#=%%!"

	echo Downloading: !URL:~1,-1!

	if not exist "%~2" mkdir "%~2"

	powershell -executionpolicy bypass -command "& { (new-object System.Net.WebClient).DownloadFile($args[0], $args[1]); }" "!URL:~1,-1!" "%~2\%~nx1" && exit /b 0
	echo FAILED (code !ERRORLEVEL!) && echo.
	exit /b 1


rem "[Section]" "Key" "Variable name (optional)"
:_history
	call :_read_ini !PINT_HISTORY_FILE! %*
	exit /b !ERRORLEVEL!


rem "[Section]" "Key" "Variable name (optional)"
:_db
	call :_read_ini !PINT_PACKAGES_FILE_USER! %* || call :_read_ini !PINT_PACKAGES_FILE! %*
	exit /b !ERRORLEVEL!


rem "INI file path" "[Section]" "Key" "Variable name (optional)"
:_read_ini
	if not exist "%~1" exit /b 1

	endlocal & (
		for /f "usebackq delims=" %%I in (`inifile "%~1" [%2] %3`) do %%I
		if "!%~3!"=="" exit /b 1
		if not "%~4"=="" set "%~4=!%~3!"
	)

	exit /b 0


rem Installs missing executables
rem "Application ID" "Download URL"
:_has
	where /Q %1 && exit /b 0

	if exist "!PINT_DIST_DIR!\%~1" rmdir /S /Q "!PINT_DIST_DIR!\%~1"

	call :_download_ps "%~2" "!PINT_DIST_DIR!\%~1"

	for /f "usebackq delims=" %%i in (`dir /b /s /a-d "!PINT_DIST_DIR!\%~1\*" 2^>nul`) do (
		call :install_file %1 "%%i"
		goto :continue_has
	)

	:continue_has
	where /Q %1
	exit /b !ERRORLEVEL!