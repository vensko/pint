@echo off
@setlocal enabledelayedexpansion

rem PINT - Portable INsTaller

rem Set variables if they weren't overriden earlier
if not defined PINT_DIST_DIR set "PINT_DIST_DIR=%~dp0packages"
if not defined PINT_APPS_DIR set "PINT_APPS_DIR=%~dp0apps"

rem Hardcoded URLs
set PINT_DEFAULT_PACKAGES=https://raw.githubusercontent.com/vensko/pint/master/packages.ini
set PINT_SELF_URL=https://raw.githubusercontent.com/vensko/pint/master/pint.bat
set PINT_EXETYPE_URL="http://smithii.com/files/exetype-1.1-win32.zip"
set PINT_WGET_URL="https://eternallybored.org/misc/wget/current/wget.exe"
set PINT_INIFILE_URL="http://www.horstmuc.de/win/inifile.zip"
set PINT_7ZA_URL="https://github.com/chocolatey/choco/raw/master/src/chocolatey.resources/tools/7za.exe"
set PINT_XIDEL_URL="http://master.dl.sourceforge.net/project/videlibri/Xidel/Xidel+0.9/xidel-0.9.win32.zip"

rem Functions accessible directly from the command line
SET PUBLIC_FUNCTIONS=self-update update subscribe list install reinstall download remove purge upgrade updated_remote wget psdownload search

SET TEMP_PACKAGES="%TEMP%\pint_temp_packages.ini"
SET PACKAGES_FILE="%~dp0packages.ini"
SET PACKAGES_FILE_USER="%~dp0packages.user.ini"
SET SRC_FILE=%~dp0sources.list

SET PACKAGES_LOCAL=%~dp0local.ini
SET DB_LOCAL=inifile "!PACKAGES_LOCAL!"

rem Create directories if needed
if not exist "!PINT_DIST_DIR!" mkdir "!PINT_DIST_DIR!"
if not exist "!PINT_APPS_DIR!" mkdir "!PINT_APPS_DIR!"
if not exist "!PACKAGES_LOCAL!" copy /y NUL "!PACKAGES_LOCAL!" >NUL

if not exist "!PINT_APPS_DIR!\pint.bat" call :makeshim "%~dpnx0"

rem Change the working directory to 'bin' in order to make it available in PATH
cd /D "!PINT_APPS_DIR!"

rem Validate the environment and install missing tools
call :has exetype !PINT_EXETYPE_URL! || echo Unable to find exetype && exit /b 1
call :has inifile !PINT_INIFILE_URL! || echo Unable to find inifile && exit /b 1
call :has wget    !PINT_WGET_URL!    || echo Unable to find Wget    && exit /b 1
call :has 7za     !PINT_7ZA_URL!     || echo Unable to find 7za     && exit /b 1
call :has xidel   !PINT_XIDEL_URL!   || echo Unable to find Xidel   && exit /b 1

rem Ready, steady, go
if "%~1"=="" call :usage & exit /b 0

if not %1==update if not exist !PACKAGES_FILE! call :update

for %%x in (!PUBLIC_FUNCTIONS!) do (
	if %1==%%x (
		call :%*
		exit /b %ERRORLEVEL%
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
	echo pint update^|self-update^|usage^|list
	echo pint download^|install^|reinstall^|upgrade^|remove^|purge ^<packages^>
	echo pint search ^<term^> ^(leave empty for a full list of packages^)
	echo pint subscribe ^<packages-ini-url^>
	exit /b 0


:self-update
	echo Fetching !PINT_SELF_URL!
	SET TEMP_BAT="%~dp0pint.tmp"

	if exist !TEMP_BAT! del !TEMP_BAT!

	wget -t 2 --retry-connrefused --no-check-certificate -q -O !TEMP_BAT! "!PINT_SELF_URL!"

	if errorlevel 1 (
		echo Self-update failed^^!
		if exist !TEMP_BAT! del !TEMP_BAT!
		exit /b 1
	) else (
		type !TEMP_BAT! > "%~0"
		del !TEMP_BAT!
		echo Pint was updated to the latest version.
		exit /b 0
	)


:update
	SET /a SRC_COUNT=0

	if not exist "!SRC_FILE!" echo !PINT_DEFAULT_PACKAGES!>"!SRC_FILE!"

	copy /y NUL !PACKAGES_FILE! >NUL
	for /F "tokens=* delims=" %%f in (!SRC_FILE!) do (
		set /p ="Fetching %%f "<nul
		wget -t 2 --retry-connrefused --no-check-certificate -q -O !TEMP_PACKAGES! "%%f"
		if errorlevel 1 (
			echo - failed^^!
		) else (
			type !TEMP_PACKAGES! >> !PACKAGES_FILE!
			SET /a SRC_COUNT+=1
			echo.
		)
	)

	echo.
	set /p ="Merged !SRC_COUNT! source"<nul
	if not !SRC_COUNT!==1 echo s
	
	echo.

	if exist !TEMP_PACKAGES! del !TEMP_PACKAGES!
	exit /b 0


:list
	dir /B /A:D "!PINT_APPS_DIR!"
	exit /b %ERRORLEVEL%


:remove
	for %%x in (%*) do call :package-remove %%x
	exit /b 0

:download
	for %%x in (%*) do call :package-download %%x
	exit /b 0

:install
	for %%x in (%*) do call :package-install %%x
	exit /b 0

:reinstall
	for %%x in (%*) do call :package-reinstall %%x
	exit /b 0

:upgrade
	for %%x in (%*) do call :package-upgrade %%x
	exit /b 0

:purge
	for %%x in (%*) do call :package-purge %%x
	exit /b 0


rem "Application ID"
:package-remove
	call :is_installed %1
	if errorlevel 1 echo %1 is not installed && exit /b 0

	echo Uninstalling %~1...
	call :del_shims %1
	if exist "!PINT_APPS_DIR!\%~1" rmdir /S /Q "!PINT_APPS_DIR!\%~1"
	!DB_LOCAL! [%~1] ts_setup=
	exit /b 0


rem "Application ID"
:package-purge
	if "%~1"=="" (
		if exist "!PACKAGES_LOCAL!" del "!PACKAGES_LOCAL!"
		if exist "!PINT_DIST_DIR!" rmdir /S /Q "!PINT_DIST_DIR!"
		exit /b 0
	)

	echo Removing the %~1 package...

	call :remove %1
	if exist "!PINT_DIST_DIR!\%~1" rmdir /S /Q "!PINT_DIST_DIR!\%~1"
	!DB_LOCAL! [%~1] /remove

	exit /b 0


rem "Term"
:search
	if "%~1"=="" (
		if exist "!PACKAGES_FILE_USER!" findstr /I /R "^^\[" "!PACKAGES_FILE_USER!"
		findstr /I /R "^^\[" "!PACKAGES_FILE!"
	) else (
		if exist "!PACKAGES_FILE_USER!" findstr /I /R "^^\[.*%~1" "!PACKAGES_FILE_USER!"
		findstr /I /R "^^\[.*%~1" "!PACKAGES_FILE!"
	)
	exit /b 0


rem "INI URL"
:subscribe
	SET URL="%~1"
	for /F "tokens=* delims=" %%f in (!SRC_FILE!) do if "!URL:~1,-1!"=="%%f" echo This URL is already registered. && exit /b 1
	>>"!SRC_FILE!" echo !URL:~1,-1!
	echo Registered !URL:~1,-1!
	exit /b 0


rem "Application ID" "Update"
:package-download
	if "%PROCESSOR_ARCHITECTURE%"=="x86" (
		call :read_db %1 dist
		call :read_db %1 link
	) else (
		call :read_db %1 dist64 dist || call :read_db %1 dist
		call :read_db %1 link64 link || call :read_db %1 link
	)

	if not defined dist echo No URL found. && exit /b 1

	if defined link for /f %%i in ('xidel "!dist:%%=%%%%!" -e "(!link:%%=%%%%!)[1]/resolve-uri(normalize-space(@href), base-uri())" --quiet') do set "dist=%%i"

	if "!dist:%%=%%%%!"=="" (
		echo No URL found.
		exit /b 1
	)

	if not "%~2"=="" (
		call :check_web_update %1 "!dist:%%=%%%%!" || exit /b 1
		echo Found an updated version.
	)

	call :wget "!dist:%%=%%%%!" "!PINT_DIST_DIR!\%~1"

	rem wget -N -t 2 --retry-connrefused --no-check-certificate --directory-prefix="!PINT_DIST_DIR!\%~1" !dist!
	rem for /f "skip=1 eol=: delims=" %%F in ('dir /b /s /o:d "!PINT_DIST_DIR!\%1"') do @del "%%F"

	exit /b %ERRORLEVEL%


rem "Application ID" "File URL"
:check_web_update
	call :history %1 size && ( call :check_web_size "%~2" "!size!" && exit /b %ERRORLEVEL% )
	exit /b 1

rem		call :is_installed %1
rem		if errorlevel 1 call :install_file %1 "%%i" && exit /b %ERRORLEVEL%
rem
rem		call :history %1 ts_dist
rem		if not "!ts_dist!"=="%%~ti" !DB_LOCAL! [%~1] "ts_dist=%%~ti"
rem		call :history %1 ts_setup
rem
rem		if not "!ts_setup!"=="%%~ti" call :install_file %1 "%%i" && exit /b %ERRORLEVEL%


:package-reinstall
	call :package-install %1 1
	exit /b %ERRORLEVEL%


rem "Application ID" "Force"
:package-install
	if "%~2"=="" (
		call :is_installed %~1 && echo %~1 is already installed && exit /b 0
	)

	call :read_db %1 deps && for %%x in (!deps!) do call :package-install %%x

	call :package-download %1

	for /f %%i in ('dir /b /s /a:-d "!PINT_DIST_DIR!\%~1"') do call :install_file %1 "%%i"

	exit /b %ERRORLEVEL%


rem "Application ID"
:package-upgrade
	call :is_installed %1

	if errorlevel 1 (
		call :package-install %1
		exit /b %ERRORLEVEL%
	)

	call :read_db %1 deps && for %%x in (!deps!) do call :package-upgrade "%%x"

	call :package-download %1 1

	if not errorlevel 1 (
		echo Installing the updated version...
		for /f %%i in ('dir /b /s /a:-d "!PINT_DIST_DIR!\%~1"') do (
			call :install_file %1 "%%i"
			exit /b %ERRORLEVEL%
		)
	) else (
		echo %1 is up to date.
	)

	exit /b 0


rem "URL" "File size"
:check_web_size
	SET EXISTS=0
	SET UPDATED=1
	SET LINE=

	for /f "usebackq delims=" %%i in (`wget -t 2 --retry-connrefused --no-check-certificate --spider "%~1" -O - 2^>^&1`) do (
		SET "LINE=%%i"
		if !EXISTS!==0 (
			if not "!LINE!"=="!LINE: 200 OK=!" (
				SET "EXISTS=1"
			)
		)
		if !EXISTS!==1 (
			if not !UPDATED!==0 (
				if not "!LINE!"=="!LINE: %~2 =!" (
					SET UPDATED=0
				)
			)
		)
	)

	if "!EXISTS!"=="0" (
		echo The remote file is not found.
		exit /b 2
	)

	if "!UPDATED!"=="0" exit /b 1
	exit /b 0
	

rem "Application ID" "File path"
:install_file
	set DEST="!PINT_APPS_DIR!\%~1"
	if not exist "!DEST:~1,-1!" mkdir "!DEST:~1,-1!"

	echo Installing to !DEST:~1,-1!

	if /I "%~x2"==".msi" (
		msiexec /a "%~2" /norestart /qn TARGETDIR=!DEST!
	) else (
		call :read_db %1 type || SET "type=%~x2" && SET "type=!type:~1!"

		if /I "%~1"=="7za" set "type=standalone"
		if /I "%~1"=="wget" set "type=standalone"

		if /I !type!==standalone (
			copy /Y "%~2" /B !DEST! >nul
		) else (
			if /I !type!==zip (
				call :install_zip %*
			) else (
				if /I !type!==rar (
					where /Q unrar || call :package-install unrar
					unrar x -u -inul "%~2" !DEST!
				) else (
					where /Q 7z || call :package-install 7-zip
					call :install_7z %*
				)
			)
		)
	)

	call :postinstall %*
	exit /b %ERRORLEVEL%


rem "Application ID" "File path"
:postinstall
	call :is_installed %1 || exit /b 1
	call !DB_LOCAL! [%~1] "ts_setup=%~t2"
	call !DB_LOCAL! [%~1] "size=%~z2"
	call :make_shims %1
	exit /b 0


rem "Application ID" "Zip file path"
:install_zip
	call :install_7z %1 %2
	if %ERRORLEVEL% LSS 2 exit /b 0

	where /Q unzip && unzip -u "%~2" -d "!PINT_APPS_DIR!\%~1" & exit /b %ERRORLEVEL%

	where /Q powershell || exit /b 1

	if not exist "!PINT_APPS_DIR!\%~1" mkdir "!PINT_APPS_DIR!\%~1"
	powershell -command "& { $shell = new-object -com shell.application; $zip = $shell.NameSpace($args[0]); $shell.Namespace($args[1]).copyhere($zip.items()); }" "%~2" "!PINT_APPS_DIR!\%~1"
	exit /b %ERRORLEVEL%


rem "Application ID" "Zip file path"
:install_7z
	SET "SEVENZIP=7za"
	where /Q 7z && SET "SEVENZIP=7z"
	!SEVENZIP! x -y -aoa -o"!PINT_APPS_DIR!\%~1" "%~2" > nul
	exit /b %ERRORLEVEL%


rem "Application ID"
:is_installed
	if not exist "!PINT_APPS_DIR!\%~1" exit /b 1
	for /f %%i in ('dir /b /s /a:-d "!PINT_APPS_DIR!\%~1\*.exe"') do exit /b 0
	exit /b 1


:is_console32
	if "%~nx1"=="exetype.exe" exit /b 0
	call exetype -q "%~1" 2>nul
	if %ERRORLEVEL%==3 exit /b 0
	exit /b 1


rem "Executable path"
:makeshim
	call :MakeRelative "%~1" "!PINT_APPS_DIR!" RELPATH

	>"!PINT_APPS_DIR!\%~n1.bat" (
		echo @echo off
		echo "%%~dp0!RELPATH!" %%*
		echo exit /b %%ERRORLEVEL%%
	)

	echo Added a shim for %~nx1

	exit /b 0


rem "Application ID"
:make_shims
	call :read_db %1 shim
	call :read_db %1 noshim

	for /f %%i in ('dir /b /s /a:-d "!PINT_APPS_DIR!\%~1\*.exe"') do (
		SET "PASS=1"

		call :is_console32 "%%i"
		if errorlevel 1 SET "PASS=0"

		if not "!shim!"=="" (
			for %%e in (!shim!) do (
				if /I "%%~nxi"=="%%~nxe" SET "PASS=1"
			)
		)

		if not "!noshim!"=="" (
			for %%e in (!noshim!) do (
				if /I "%%~nxi"=="%%~nxe" SET "PASS=0"
			)
		)

		if !PASS!==1 call :makeshim "%%i"
	)

	exit /b 0


rem "Application ID"
:del_shims
	for /f %%i in ('dir /b /s /a:-d "!PINT_APPS_DIR!\%~1\*.exe"') do (
		if exist "!PINT_APPS_DIR!\%%~ni.bat" del "!PINT_APPS_DIR!\%%~ni.bat"
	)
	exit /b 0


:history
	call :read_ini "!PACKAGES_LOCAL!" %*
	exit /b %ERRORLEVEL%


rem "Download URL" "Destination directory"
:wget
	SET URL="%~1"
	echo Downloading: !URL:~1,-1!
	
	wget -q -N -t 2 --retry-connrefused --no-check-certificate --directory-prefix="%~2" "!URL:~1,-1!" && exit /b 0

	if not "%~x1"=="" wget -q -N -t 2 --retry-connrefused --no-check-certificate -O "%~2\%~nx1" "!URL:~1,-1!" && exit /b 0

	echo FAILED (code %ERRORLEVEL%) && echo.
	exit /b 1


rem "Download URL" "Destination directory"
:psdownload
	SET URL="%~1"
	echo Downloading with Powershell^: && echo !URL:+=%%20!

	if not exist "%~2" mkdir "%~2"

	powershell -executionpolicy bypass -command "& { (new-object System.Net.WebClient).DownloadFile($args[0], $args[1]); }" !URL:+=%%20! "%~2\%~nx1" && exit /b 0
	echo FAILED (code %ERRORLEVEL%) && echo.
	exit /b 1


:read_db
	call :read_ini !PACKAGES_FILE_USER! %* || call :read_ini !PACKAGES_FILE! %*
	exit /b %ERRORLEVEL%


:read_ini
	if not exist "%~1" exit /b 1

	endlocal & (
		for /f "usebackq delims=" %%I in (`inifile "%~1" [%2] %3`) do %%I
		if "!%~3!"=="" exit /b 1
		if not "%~4"=="" set "%~4=!%~3!"
	)
	exit /b 0


rem Installs missing executables
rem "Application ID" "Download URL"
:has
	where /Q %1 && exit /b 0

	call :psdownload "%~2" "!PINT_DIST_DIR!\%~1"

	for /f %%i in ('dir /b /s /a:-d "!PINT_DIST_DIR!\%~1\*"') do (
		call :install_file %1 "%%i"
		goto :continue_has
	)

	:continue_has
	where /Q %1
	exit /b %ERRORLEVEL%



rem :MakeRelative file base -- makes a file name relative to a base path
rem ::                      -- file [in,out] - variable with file name to be converted, or file name itself for result in stdout
rem ::                      -- base [in,opt] - base path, leave blank for current directory
rem :$created 20060101 :$changed 20080219 :$categories Path
rem :$source http://www.dostips.com/DtCodeCmdLib.php#Function.MakeRelative

:MakeRelative
SETLOCAL ENABLEDELAYEDEXPANSION
set src=%~1
if defined %1 set "src=!%~1!"
set bas=%~2
if not defined bas set "bas=%cd%"
for /f "tokens=*" %%a in ("%src%") do set "src=%%~fa"
for /f "tokens=*" %%a in ("%bas%") do set "bas=%%~fa"
set mat=&rem variable to store matching part of the name
set upp=&rem variable to reference a parent
for /f "tokens=*" %%a in ('echo.%bas:\=^&echo.%') do (
    set "sub=!sub!%%a^\"
    call set "tmp=%%src:!sub!=%%"
    if "!tmp!" NEQ "!src!" (set mat=!sub!)ELSE (set upp=!upp!..\)
)
set src=%upp%!src:%mat%=!
( ENDLOCAL & REM RETURN VALUES
    IF defined %1 (
		SET %~1=%src%
	) ELSE (
		if not "%~3"=="" (
			SET "%~3=%src%"
		) else (
			ECHO.%src%
		)
	)
)
exit /b 0