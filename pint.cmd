<# :
@echo off
@setlocal

rem PINT - Portable INsTaller
rem https://github.com/vensko/pint

SET "PINT=%~f0"

rem Set variables if they weren't overriden earlier
if not defined PINT_DIST_DIR set "PINT_DIST_DIR=%~dp0dist"
if not defined PINT_APP_DIR set "PINT_APP_DIR=%~dp0apps"
if not defined PINT_PACKAGES_FILE set "PINT_PACKAGES_FILE=%~dp0packages.ini"
if not defined PINT_PACKAGES_FILE_USER set "PINT_PACKAGES_FILE_USER=%~dp0packages.user.ini"
if not defined PINT_SRC_FILE set "PINT_SRC_FILE=%~dp0sources.list"
if not defined PINT_TEMP_FILE set "PINT_TEMP_FILE=%TEMP%\pint.tmp"
if not defined PINT_USER_AGENT set "PINT_USER_AGENT=PintBot/1.0 (+https://github.com/vensko/pint)"

SET "FINDSTR=%WINDIR%\system32\findstr.exe"
SET "FIND=%WINDIR%\system32\find.exe"
SET "SORT=%WINDIR%\system32\sort.exe"
SET "FORFILES=%WINDIR%\system32\forfiles.exe"
SET "MSIEXEC=%WINDIR%\system32\msiexec.exe"
SET "ROBOCOPY=%WINDIR%\system32\robocopy.exe"
SET "POWERSHELL=powershell -NoLogo -NoProfile -executionpolicy bypass"

path %PINT_APP_DIR%;%PATH%

rem Hardcoded URLs
set "PINT_PACKAGES=https://raw.githubusercontent.com/vensko/pint/master/packages.ini"
set "PINT_SELF_URL=https://raw.githubusercontent.com/vensko/pint/master/pint.bat"

rem Functions accessible directly from the command line
SET BATCH=search subscribed subscribe unsubscribe pin unpin forget

for %%x in (%BATCH%) do (
	if "%~1"=="%%x" (
		call :%* || exit /b 1
		exit /b 0
	)
)

set "_args=%*"
if defined _args set "_args=%_args:"=""""""%"
%POWERSHELL% "$s = ${%PINT%} | out-string; $s += """pint-start %_args%"""; iex($s)" || exit /b 1
exit /b 0


rem *****************************************
rem  FUNCTIONS
rem *****************************************


:search
	if not exist "%PINT_PACKAGES_FILE%" call "%PINT%" update

	if exist "%PINT_PACKAGES_FILE_USER%" (
		"%FINDSTR%" /I /B /R "\s*\[.*%~1.*\]" "%PINT_PACKAGES_FILE_USER%" | "%SORT%"
	)
	"%FINDSTR%" /I /B /R "\s*\[.*%~1.*\]" "%PINT_PACKAGES_FILE%" | "%SORT%"
	exit /b


:subscribed
	type "%PINT_SRC_FILE%" || exit /b 1
	exit /b 0


:subscribe
	if "%~1"=="" (
		echo Enter an URL!
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


:unsubscribe
	if "%~1"=="" (
		echo Enter an URL!
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

	exit /b


:pin
	@setlocal enabledelayedexpansion
	if not "%~2"=="" (
		for %%x in (%*) do call :pin "%%~x"
		exit /b 0
	)
	if not exist "%PINT_APP_DIR%\%~1\*.pint" (
		echo %~1 is not tracked by Pint, try to reinstall it.
		exit /b 1
	)
	for /f "usebackq delims=" %%s in (`dir /b /ah "%PINT_APP_DIR%\%~1\*.pint"`) do (
		set "_file=%%~ns"
		if defined _unpin (
			set "_file=!_file: pinned=!"
			echo %~1 is unpinned.
		) else (
			set "_file=!_file: pinned=! pinned"
			echo %~1 is pinned.
		)
		ren "%PINT_APP_DIR%\%~1\%%s" "!_file!.pint"
	)
	exit /b


:unpin
	set "_unpin=1"
	call :pin %*
	exit /b


:forget
	if "%~1"=="" (
		echo Choose a path!
		exit /b 1
	)
	if not "%~2"=="" (
		for %%x in (%*) do call :forget "%%~x"
		exit /b 0
	)
	2>nul del /Q /S /AH "%PINT_APP_DIR%\%~1\*.pint"
	echo %~1 is no longer managed by Pint.
	exit /b


goto :eof

end Batch / begin PowerShell #>

$global:httpMaxRedirects = 5
$global:httpTimeout = 10000
$DebugPreference = 'Continue'
$global:ini = @{}

function pint-usage
{
	write-host "PINT - Portable INsTaller`n" -f white
	write-host "Usage:"
	write-host "pint `<command`> `<parameters`>`n" -f yellow
	write-host "Available commands:"

	$commands = @(
		@('self-update', 'Update Pint.'),
		@('update', 'Download package databases and combine them into packages.ini.'),
		@('search [<term>]', 'Search for an app in the database, or show all items.'),
		@('installto <app> <dir> [<arch>] ', 'Install the app to the given directory.'),
		@('install <app>', 'Install one or more apps to directories with the same names.'),
		@('reinstall <dir>', 'Force reinstallation of the package.'),
		@('list', 'Show all applications installed via Pint.'),
		@('l', 'Show only names of installed applications.'),
		@('outdated [<dir>]', 'Check for updates for all or some packages by your choice.'),
		@('upgrade [<dir>]', 'Install updates for all or selected apps.'),
		@('pin <dir>', 'Suppress updates for selected apps.'),
		@('unpin <dir>', 'Allow updates for selected apps (undoes the pin command).'),
		@('remove <dir>', 'Delete selected apps (this is equivalent to manual deletion).'),
		@('purge <dir>', 'Delete selected apps AND their installers.'),
		@('forget <dir>', 'Stop tracking of selected apps.'),
		@('download <app>', 'Only download selected installers without unpacking them.'),
		@('subscribed', 'Show the list of databases, you are subscribed to.'),
		@('subscribe <url>', 'Add a subscription to a package database.'),
		@('unsubscribe <url>', 'Remove the URL from the list of subscriptions.')
	)

	foreach ($cmd in $commands) {
		write-host $cmd[0].padright(23, ' ') -f green -nonewline
		write-host $cmd[1]
	}

	write-host "`n`<app`> is a database ID, which can be seen via the search command."
	write-host "`<dir`> is a path, relative to the 'apps' directory, as shown by the list command."
}

function pint-shims([string]$dir, [string]$include, [string]$exclude, $delete)
{
	$params = @{
		recurse = $true
		force = $true
		name = $true
		exclude = $exclude -split ',', $null, 'SimpleMatch' |% {$_.trim()}  |? {$_}
		ea = 0
	}

	if ($include) {
		$includeArr = $include -split ',', $null, 'SimpleMatch' |% {$_.trim()}  |? {$_}
		$params['include'] = @('*.exe') + $includeArr
	} else {
		$params['filter'] = '*.exe'
	}

	cd $env:PINT_APP_DIR

	dir $dir @params |% {
		$exe = $_
		$relpath = join-path $dir $_

		if ([System.IO.Path]::GetExtension($_) -eq '.exe' -and (!$includeArr -or !($includeArr |? { $exe -like $_ }))) {
			$subsystem = $null
			try {
				$fs = [IO.File]::OpenRead($relpath)
				$br = New-Object IO.BinaryReader($fs)
				if ($br.ReadUInt16() -ne 23117) { return }
				$fs.Position = 0x3C
				$fs.Position = $br.ReadUInt32()
				$offset = $fs.Position
				if ($br.ReadUInt32() -ne 17744) { return }
				# $fs.Position += 0x14
				# switch ($br.ReadUInt16()) { 0x10B { $arch = 32 } 0x20B { $arch = 64 } }
				$fs.Position = $offset + 4 + 20 + 68
				$subsystem = $br.ReadUInt16()
			} catch {} finally {
				if ($br -ne $null) { $br.Close() }
				if ($fs -ne $null) { $fs.Close() }
			}
			if ($subsystem -ne 3) { return }
		}

		$baseName = [System.IO.Path]::GetFileNameWithoutExtension($_)
		$batch = pint-dir "$baseName.bat"

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
        if ($h -is [Hashtable]) {
            foreach ($k in $h.keys) {
				$output[$k] = $h[$k]
			}
        }
    }
    $output
}

function pint-get-app([string]$p)
{
	$p = pint-dir $p
	if (test-path $p -pathtype leaf) {
		$f = $p
		$dir = [System.IO.Path]::GetDirectoryName($f)
	} else {
		$f = dir (join-path $p '*.pint') -n -force -ea 0 | select -first 1
		if (!$f) { return }
		$f = join-path $p $f
		$dir = $p
	}

	$a = [System.IO.Path]::GetFileNameWithoutExtension($f).trim() -split ' ', $null, 'SimpleMatch'

	$app = @{
		id = $a[0]
		dir = $dir
		arch = get-arch
		pinned = $false
		version = ""
		size = 0
	}

	$a = if ($a[1]) {$a[1..($a.count-1)]} else {@()}

	if ($a) {
		$a | % {
			switch ($_) {
				32 { $app['arch'] = 32 }
				64 { $app['arch'] = 64 }
				'pinned' { $app['pinned'] = $true }
				{$_[0] -eq 'v' -and $_ -match "^v[0-9\.]+$"} { $app['version'] = $_.substring(1) }
				default { if ($_ -match "^[0-9\.]+$") { $app['size'] = [int]$_ } }
			}
		}
	}

	$ini = pint-get-app-info $app['id'] $app['arch']
	if (!$ini) { return }
	$app = merge-hashtables $ini $app
	$app
}

function pint-has($exe)
{
	test-path (pint-dir "$exe.bat") -pathtype leaf
}

function pint-unpack([string]$file, [string]$dir)
{
	if (!(test-path $file)) {
		write-host 'Unable to find' $file
		return
	}

	if (!(test-path $dir -pathtype container)) { md $dir -ea stop | out-null }

	$filename = [System.IO.Path]::GetFileName($file)

	write-host 'Unpacking' $filename

	$fullPath = [System.IO.Path]::GetFullPath($file)
	$sevenzip = (test-path (pint-dir '7z.bat'))

	switch ([System.IO.Path]::GetExtension($file)) {
		".msi" {
			& $env:ComSpec /d /c "msiexec /a `"$fullPath`" /norestart /qn TARGETDIR=`"$dir`""
			break
		}
		{!$sevenzip -and ($_ -eq '.zip')} {
			$shell = new-object -com Shell.Application
			$zip = $shell.NameSpace($fullPath)
			$shell.Namespace($dir).copyhere($zip.items(), 20)
			break
		}
		default {
			if (($_ -eq '.exe') -and (& $env:FINDSTR /m /c:"Inno Setup" $file)) {
				if (!(pint-has 'innoextract')) {
					write-host "Pint needs innoextract to unpack $filename, installing automatically..."
					pint-reinstall @('innoextract')
				}
				& innoextract -s -c -p -d $dir $fullPath
				break
			}

			if (!(pint-has '7z')) {
				write-host "Pint needs 7-zip to unpack $filename, installing automatically..."
				pint-reinstall @('7-zip')
			}

			& $env:ComSpec /d /c "7z x -y -aoa -o`"$dir`" `"$fullPath`"" | out-null
		}
	}

	!$lastexitcode
}

function pint-read-ini([string]$file, [string]$term)
{
	$result = @{}
	if (!(test-path $file)) { return $result }

	if (!$global:ini[$file]) {
		$stream = new-object System.IO.StreamReader($file)
		$global:ini[$file] = $stream.readToEnd()
		$stream.close()
	}

	$section = '[' + $term + ']'
	$text = ($global:ini[$file] -split $section, 2, 'SimpleMatch')[1]

	if ($text) {
		$lines = ($text -split "`n[", 2, 'SimpleMatch')[0] -split "`n", $null, 'SimpleMatch'
		foreach ($line in $lines) {
			$key, $val = $line -split '=', 2, 'SimpleMatch'
			if ($val -ne $null) {
				$key = $key.trim()
				if ($key[0] -ne ';') {
					$result[$key] = $val.trim()
				}
			}
		}
	}

	$result
}

function pint-get-version([string]$dir)
{
	try {
		$v = (dir $dir -recurse -filter *.exe -ea stop | sort -property length -descending | select -first 1).VersionInfo.ProductVersion.trim()
		if ($v.contains(',')) { $v = $v.replace(',', '.') }
		if ($v.contains('-')) { $v = ($v -split '-', 2, 'SimpleMatch')[0] }
		if (!($v -match "^[0-9\.]+$")) { return }
		while ($v.substring($v.length-2, 2) -eq '.0') { $v = $v.substring(0, $v.length-2) }
		$v
	} catch {}
}

function get-arch
{
	if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') {32} else {64}
}

function pint-get-app-info([string]$id, $arch)
{
	if (!$arch) { $arch = get-arch }

	if (!(test-path $env:PINT_PACKAGES_FILE)) { pint-update }

	$ini = merge-hashtables (pint-read-ini $env:PINT_PACKAGES_FILE $id) (pint-read-ini $env:PINT_PACKAGES_FILE_USER $id)

	if (!$ini.keys.count) {
		write-host 'Unable to find' $id 'in the database'
		return
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
	if (!$res['dist']) { return }
	$res
}

function pint-make-ftp-request([string]$url, $download)
{
	$req = [System.Net.WebRequest]::Create($url)
	$req.Timeout = $global:httpTimeout
	if (!$download) { $req.Method = [System.Net.WebRequestMethods+Ftp]::GetFileSize }
	$req.GetResponse()
}

function pint-make-http-request([string]$url, $download, $disableAutoRedirect)
{
	try {
		$req = [System.Net.WebRequest]::Create($url)
		$req.Timeout = $global:httpTimeout
		$req.UserAgent = $env:PINT_USER_AGENT
		$req.AllowAutoRedirect = !$disableAutoRedirect
		$req.MaximumAutomaticRedirections = $global:httpMaxRedirects
		$req.Accept = '*/*'
		$req.AuthenticationLevel = 'None'
		$req.GetResponse()
	} catch [System.Management.Automation.MethodInvocationException] {
		$maxRedirects = $global:httpMaxRedirects
		while ($true) {
			if ($url.StartsWith('ftp:')) {
				return pint-make-ftp-request $url $download
			} else {
				$res = pint-make-http-request $url $download $true
				if ($res.headers['Location']) {
					$res.close()
					if ($maxRedirects-- -eq 0) {
						write-host 'Exceeded limit of redirections retrieving' $url -f yellow
						return
					}
					$url = $res.headers['Location']
					continue
				} else {
					return $res
				}
			}
		}
	}
}

function pint-make-request([string]$url, $download)
{
	[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

	if ($url.StartsWith('ftp:')) {
		$res = pint-make-ftp-request $url $download
	} else {
		$res = pint-make-http-request $url $download
	}

	if (!$res) {
		write-host 'Failed to connect to' $url -f yellow
		return
	}

	if ([string]$res.ContentType -eq 'text/html') {
		$res.close()
		write-host $url 'responded with a HTML page.' -f yellow
		return
	}

	if ($res.ContentLength -lt 1) {
		$res.close()
		write-host 'Empty response from' $url -f yellow
		return
	}

	if (!$download) { $res.close() }

	$res
}

function pint-get-dist-link([Hashtable]$info, $verbose)
{
	if (!$info['dist']) {
		return
	}

	$dist = $info['dist']
	$link = $info['link']
	$follow = $info['follow']

	if (!$link) {
		if ($dist.contains('portableapps.com/apps/')) {
			$link = "//a[contains(@href, '.paf.exe')]"
		} elseif ($dist.contains('filehippo.com/')) {
			$follow = "(//a[contains(@class, 'program-header-download-link')])[1]"
			$link = '//meta[@http-equiv="Refresh"]/@content'
		} elseif ($dist.contains('/rss')) {
			$link = '//item/link'
		} elseif ($dist.EndsWith('.xml') -or $dist.EndsWith('/pad.php')) {
			if ($verbose) { write-host 'PAD file detected.' }
			$link = "//Primary_Download_URL"
		}
	}

	if ($link) {
		if (!(pint-has 'xidel')) {
			write-host "Pint needs Xidel to be able to extract links, installing automatically..."
			pint-reinstall @('xidel')
		}

		if (!$link.contains('$json') -and $link.trimstart('/')[0] -eq 'a') {
			$link += '/resolve-uri(normalize-space(@href), base-uri())'
		}

		$link = $link.replace('"', "\`"")

		if ($follow) {
			$follow = $follow.replace('"', "\`"").replace(' | ', '" --follow "')
			$follow = " --follow `"$follow`""
		}

		if ($verbose) {
			write-host 'Extracting a download link from' $dist
			$out = ''
		} else {
			$quiet = '--quiet'
			$out = '2>nul'
		}

		$method = if ($info['method']) {'-d "'+$info['data']+'" --method '+$info['method']} else {''}

		$dist = & $env:ComSpec /d /c "$out xidel $method --header=`"Referer: $dist`" --user-agent=`"$($env:PINT_USER_AGENT)`" `"$dist`" $follow $quiet --extract `"($link)[1]`""

		if ($lastexitcode -or !$dist) {
			$dist = $null
		} else {
			$dist = $dist.trim()

			if ($dist.contains('fosshub.com/')) {
				$dist = $dist.replace('fosshub.com/', 'fosshub.com/genLink/').replace('.html/', '/')
				$dist = (get-web-client).DownloadString($dist).trim()
			} elseif ($info['dist'].contains('filehippo.com/')) {
				$dist = 'http://filehippo.com' + ($dist -split '=', 2, 'SimpleMatch')[1]
			}
		}

		if (!$dist) {
			write-host 'Unable to extract a link from' $info['dist']
			return
		}
	}

	$dist
}

function pint-is-app-outdated([Hashtable]$app, $download)
{
	if (($url = pint-get-dist-link $app $verbose) -and ($res = pint-make-request $url $download)) {
		if ($res.ContentLength -eq $app['size']) {
			if ($download) { $res.close() }
			return $false
		}
		$res
	}
}

function pint-get-folder-size([string]$path, $fso)
{
    if (!$fso) { $fso = new-object -com Scripting.FileSystemObject }
    ('{0:N2} MB' -f (($fso.GetFolder($path).Size) / 1MB))
}

function pint-download-file([System.Net.WebResponse]$res, [string]$targetFile)
{
	$dir = [System.IO.Path]::GetDirectoryName($targetFile)
	if (!(test-path $dir)) { md $dir -ea stop | out-null }

	pint-test $res.ResponseUri $targetFile
	return

	$totalLength = [System.Math]::Floor($res.ContentLength / 1024)

	write-host "Downloading $($res.ResponseUri) ($("{0:N2} MB" -f ($totalLength / 1024)))"

	$remoteName = pint-get-remote-name $res
	$responseStream = $res.GetResponseStream()
	$targetStream = new-object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create
	$buffer = new-object byte[] 32KB
	$count = $responseStream.Read($buffer, 0, $buffer.length)
	$downloaded = $count
	$progressBar = ($res.ContentLength -gt 1MB)
	while ($count -gt 0) {
		$targetStream.Write($buffer, 0, $count)
		$count = $responseStream.Read($buffer, 0, $buffer.length)
		if ($progressBar) {
			$downloaded += $count
			write-progress -activity "Downloading file $remoteName" -status "Downloaded ($([System.Math]::Floor($downloaded / 1024))K of $($totalLength)K): " -PercentComplete ((([System.Math]::Floor($downloaded / 1024)) / $totalLength)  * 100)
		}
	}
	write-progress -completed -activity "Downloading file $remoteName" -status "Done"
	$targetStream.Flush()
	$targetStream.Close()
	if ($targetStream.Dispose -ne $null) {
		$targetStream.Dispose()
		$responseStream.Dispose()
	}
	$res.Close()

	$targetFile
}

function pint-get-remote-name([System.Net.WebResponse]$res)
{
	if (($h = $res.headers['Content-Disposition']) -and $h.contains('=')) {
		$name = ($h -split '=', 2, 'SimpleMatch')[1].replace('"', '').trim()
	} else {
		$name = ([string]$res.ResponseUri -split '/', $null, 'SimpleMatch')[-1]
	}
	($name -split '?', 2, 'SimpleMatch')[0]
}

function pint-download-app([string]$id, $arch, $res)
{
	if (!($res -is [System.Net.WebResponse])) {
		if (!($info = pint-get-app-info $id $arch) -or !($url = pint-get-dist-link $info $true) -or !($res = pint-make-request $url $true)) {
			return
		}
	}

	$name = pint-get-remote-name $res

	$file = join-path $env:PINT_DIST_DIR "$id--$($info['arch'])--$name"

	if (test-path $file) {
		if ((new-object System.IO.FileInfo($file)).length -eq $res.ContentLength) {
			$res.close()
			write-host 'The local file has the same size as the remote one, skipping redownloading.'
			return $file
		}
	}

	if (pint-download-file $res $file) {
		write-host 'Saved to' $file
		return $file
	}
}

function pint-force-install([string]$id, [string]$dir, $arch)
{
	$file = pint-download-app $id $arch
	if (!$file) { return }
	pint-file-install $id $file $dir $arch
}

function pint-dir([string]$path)
{
	if (![System.IO.Path]::isPathRooted($path)) {
		$path = join-path $env:PINT_APP_DIR $path
	}
	$path
}

function pint-dir-empty([string]$path)
{
	!(dir (pint-dir $path) -name -force -ea 0)
}

function pint-dir-upgradable([string]$path)
{
	if ([bool](dir (pint-dir $path) -n -force -ea 0 -filter *pinned*.pint)) {
		write-host $path 'is pinned, use unpin to allow this action.'
		return
	}
	$true
}

function pint-dir-tracked([string]$path)
{
	[bool](dir (pint-dir $path) -n -force -ea 0 -filter *.pint)
}

function pint-file-install([string]$id, [string]$file, [string]$destDir, $arch)
{
	if (!(test-path $file)) {
		throw [System.IO.FileNotFoundException] "Unable to find $file"
	}

	if (!$destDir) { $destDir = $id }
	$destDir = pint-dir $destDir

	if (!($info = pint-get-app $destDir) -and !($info = pint-get-app-info $id)) {
		throw [System.IO.FileNotFoundException] "Unable to find $id in the database."
	}

	if (!(test-path $destDir -pathtype container)) { md $destDir -ea stop | out-null }

	write-host 'Installing' $id 'to' $destDir

	if ($info['type'] -eq 'standalone') {
		copy -LiteralPath $file (join-path $destDir "$id.exe") -force
	} else {
		$tempDir = join-path $env:TEMP "pint-$id-$(get-random)"
		md $tempDir -ea stop | out-null

		pint-unpack $file $tempDir | out-null

		cd $tempDir

		if ($tempDir -ne $pwd) {
			throw [System.IO.FileNotFoundException] "Unable to use the temporary directory $tempDir"
		}

		$base = if ($info['base']) {$info['base']} else {'.exe'}

		foreach ($p in (dir $pwd -r -n)) {
			if ($p.contains($base)) {
				cd "$p\.."
				break
			}
		}

		$keep = if ($info['keep'] -ne $null) {$info['keep'] -split ',', $null, 'SimpleMatch' |% {$_.trim()}  |? {$_} } else {@('*.ini','*.db')}

		$params = @{
			include = $keep
			recurse = $true
			force = $true
			name = $true
			ea = 0
		}

		dir $destDir @params | % {
			$p = join-path $destDir $_
			if (test-path $p -pathtype container) {
				if (!(test-path "$pwd\$_")) { md "$pwd\$_" | out-null }
				copy "$p\*" "$pwd\$_" -recurse -force
			} else {
				$dir = [System.IO.Path]::GetDirectoryName("$pwd\$_")
				if (!(test-path $dir)) { md $dir | out-null }
				copy $p "$pwd\$_" -force
			}
		}

		if ($info['only']) {
			$only = $info['only'] -split ',', $null, 'SimpleMatch' |% {$_.trim()}  |? {$_}

			$params = @{
				include = $only
				recurse = $true
				force = $true
				name = $true
				ea = 0
			}

			dir $destDir @params | % { del "$destDir\$_" -force -recurse }

			dir $pwd @params | % {
				$p = join-path $pwd $_
				if (test-path $p -pathtype container) {
					if (!(test-path "$destDir\$_")) { md "$destDir\$_" | out-null }
					copy "$p\*" "$destDir\$_" -recurse -force
				} else {
					$dir = [System.IO.Path]::GetDirectoryName("$destDir\$_")
					if (!(test-path $dir)) { md $dir | out-null }
					copy $p "$destDir\$_" -force
				}
			}
		} else {
			$xf = $info['xf'] + ' *.pint $R0'
			$xd = $info['xd'] + ' $0 $PLUGINSDIR $TEMP'

			& $env:COMSPEC /d /c "robocopy `"$pwd`" `"$destDir`" /E /PURGE /NJS /NJH /NFL /NDL /NC /NP /NS /R:2 /W:2 /XO /FFT /XF $xf /XD $xd"

			if ($lastexitcode -gt 7) {
				write-host "Detected errors while copying from $pwd with Robocopy ($lastexitcode)."
			}
		}

		cd $destDir
		rd $tempDir -force -recurse
	}

	if ($version = pint-get-version $destDir) {
		write-host 'Detected version' $version
		$version = "v$version"
	}

	if (($arch -eq 32) -or ($arch -eq 64)) { $info['arch'] = $arch }

	$pintFile = (@($id, $version, $info['arch'], (new-object System.IO.FileInfo($file)).length) | where {$_}) -join " "
	$pintFile = join-path $destDir "$pintFile.pint"

	del (join-path $destDir '*.pint') -force
	$pintFile = ni $pintFile -type file -force
	$pintFile.attributes = 'Hidden'

	pint-shims $destDir $info['shim'] $info['noshim'] | out-null
}

function pint-test()
{

}


############## Controllers


function pint-reinstall
{
	if (!$args.count) { write-host 'Set a directory to reinstall.'; return }

	$args | % {
		try {
			if (!(pint-dir-upgradable $_)) { return }

			if ($app = pint-get-app $_) {
				pint-force-install $app['id'] $app['dir'] $app['arch']
			} else {
				pint-force-install $_ $_
			}
		} catch {
			write-host $_ -f yellow
		}
	}
}

function pint-download
{
	if (!$args.count) { write-host 'Set an ID to download.'; return }

	$args | % {
		try {
			pint-download-app $_ | out-null
		} catch {
			write-host $_ -f yellow
		}
	}
}

function pint-install
{
	if (!$args.count) { write-host 'Set an ID to install.'; return }
	$args | % { pint-installto $_ $_ }
}

function pint-installto([string]$id, [string]$dir, $arch)
{
	if (!$id -or !$dir) { write-host 'Set an ID and a destination directory.'; return }

	if (!(pint-dir-empty $dir)) {
		write-host (pint-dir $dir) 'is not empty.'
		$confirm = read-host -prompt 'Do you want to REPLACE its contents? [Y/N] '
		if ($confirm.trim() -ne 'Y') { return }
	}

	pint-force-install $id $dir $arch
}

function pint-purge
{
	if (!$args.count) { write-host 'Set a directory to purge.'; return }
	pint-remove @args
	$args | % { del (join-path $env:PINT_DIST_DIR "$_--*.*") -force }
}

function pint-remove
{
	if (!$args.count) { write-host 'Set a directory to remove.'; return }

	$args | % {
		$dir = pint-dir $_

		if (test-path $dir) {
			write-host "Uninstalling $_..."
			$app = pint-get-app $_
			if ($app) { pint-shims $dir $app['shim'] $app['noshim'] 'delete' }
			rd -literalpath $dir -recurse -force
			write-host $_ 'is removed.'
		} else {
			write-host "$_ is not installed."
		}
	}
}

function max-length($array)
{
	$max = 0
	$array | % { if ($_.length -gt $max) { $max = $_.length } }
	$max
}

function pint-outdated
{
	write-host 'Checking for updates...'

	if (!$args.count) { $args = pint-l }
	$pad = (max-length $args) + 2

	$args | % {
		write-host $_.padright($pad, ' ') -nonewline

		try {
			$app = pint-get-app $_

			if (!$app) { write-host 'NOT FOUND' -f red; return }
			if (!$app['size']) { write-host 'NO SIZE DATA' -f darkyellow; return }

			switch (pint-is-app-outdated $app) {
				$null { write-host 'REQUEST FAILED' -f red }
				$false { write-host 'UP TO DATE' -f green }
				default { write-host 'OUTDATED' -f yellow }
			}
		} catch {
			write-host $_ -f red
		}
	}
}

function pint-upgrade
{
	write-host 'Checking for updates...'

	if (!$args.count) { $args = pint-l }
	$pad = (max-length $args) + 2

	$args | % {
		write-host $_.padright($pad, ' ') -nonewline

		try {
			$app = pint-get-app $_
			if (!$app) { write-host 'NOT FOUND' -f red; return }
			if (!$app['size']) { write-host 'NO SIZE DATA' -f darkyellow; return }

			if ($res = pint-is-app-outdated $app $true) {
				write-host 'OUTDATED' -f yellow
				$file = pint-download-app $_ $null $res
				if (!$file) { return }
				pint-file-install $app['id'] $file $app['dir']
			} else {
				if ($res -eq $null) {
					write-host 'REQUEST FAILED' -f red
				} else {
					write-host 'UP TO DATE' -f green
				}
			}
		} catch {
			write-host $_ -f red
		}
	}
}

function pint-l
{
	dir $env:PINT_APP_DIR -n -r -force -filter *.pint | % { [System.IO.Path]::GetDirectoryName($_) }
}

function pint-list($detailed)
{
	$table = @()
	$fso = new-object -com Scripting.FileSystemObject
	dir $env:PINT_APP_DIR -n -r -force -filter *.pint | % {
		$dir = [System.IO.Path]::GetDirectoryName($_)
		$name = [System.IO.Path]::GetFileNameWithoutExtension($_)
		$id = ($name -split ' ', 2, 'SimpleMatch')[0]
		$arch = if ($name.contains(' 32 ')) {32} else {64}
		$fullpath = pint-dir $dir
		$table += new-object �TypeName PSObject �Prop @{
			ID = $id
			Directory = $dir + '  '
			Size = pint-get-folder-size $fullpath $fso
			Version = (pint-get-version $fullpath) + $(if ($name.contains(' pinned')) {' (pinned)'})
			Arch = $arch
		}
	}
	$table | ft Directory,ID,Version,Size,Arch -autosize
}

function get-web-client
{
	$client = new-object System.Net.WebClient
	$client.Headers["User-Agent"] = $env:PINT_USER_AGENT
#	$client.Timeout = $global:httpTimeout
	$client
}

function pint-self-update
{
	write-host 'Fetching' $env:PINT_SELF_URL
	$res = (get-web-client).DownloadString($env:PINT_SELF_URL)
	if ($res -and $res.contains('PINT - Portable INsTaller')) {
		$res | out-file $env:PINT -encoding ascii
		write-host 'Pint was updated to the latest version.'
	} else {
		write-host 'Self-update failed!'
		exit 1
	}
}

function pint-update
{
	write-host 'Updating the database...'
	$client = get-web-client;
	$result = ''
	cat -LiteralPath $env:PINT_SRC_FILE | % {
		$res = $client.DownloadString($_.trim())
		if ($res) {
			write-host 'Fetched' $_
			$result += $res
		} else {
			write-host 'Failed to fetch' $_
		}
	}
	$result | out-file $env:PINT_PACKAGES_FILE -encoding ascii
}

function pint-start($cmd)
{
	if (!$cmd) { pint-usage; exit 0 }

	$cmd = 'pint-' + $cmd

	if (gcm $cmd -ea 0) {
		& $cmd @args
		exit $lastexitcode
	}

	write-host 'Unknown command'
	exit 1
}