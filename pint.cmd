<# :
@echo off
@setlocal

rem PINT - Portable INsTaller
rem https://github.com/vensko/pint

SET "PINT=%~f0"
set "PINT_SELF_URL=https://raw.githubusercontent.com/vensko/pint/master/pint.cmd"

rem Set variables if they weren't overriden earlier
if not defined PINT_DIST_DIR set "PINT_DIST_DIR=%~dp0dist"
if not defined PINT_APP_DIR set "PINT_APP_DIR=%~dp0apps"
if not defined PINT_DEPS_DIR set "PINT_DEPS_DIR=%~dp0deps"
if not defined PINT_SHIM_DIR set "PINT_SHIM_DIR=%PINT_APP_DIR%\.shims"
if not defined PINT_USER_AGENT set "PINT_USER_AGENT=PintBot/1.0 (+https://github.com/vensko/pint)"
if not defined PINT_DB set "PINT_DB=https://d.vensko.net/pint/packages.ini,%~dp0packages.user.ini"
if not defined PINT_DB_CACHE set "PINT_DB_CACHE=%TEMP%\pint_packages.ini"

path %PINT_SHIM_DIR%;%PATH%

rem Start 64bit PowerShell even from 32bit command line
SET "POWERSHELL=%SystemRoot%\sysnative\windowspowershell\v1.0\powershell.exe"
if not exist "%POWERSHELL%" set "POWERSHELL=powershell"

set "_args=%*"
if defined _args set "_args=%_args:"=""""""%"
%POWERSHELL% -NoLogo -NoProfile -executionpolicy bypass "$s = ${%PINT%} | out-string; $s += """pint-start %_args%"""; iex($s)" || exit /b 1
exit /b 0

end Batch / begin PowerShell #>

$DebugPreference = 'Continue'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

$global:httpMaxRedirects = 5
$global:httpTimeout = 10000
$global:arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') {32} else {64}

$global:dependencies = @"
[shimgen]
dist = https://github.com/chocolatey/choco/raw/master/src/chocolatey.resources/tools/shimgen.exe
type = standalone
[xidel]
dist = https://master.dl.sourceforge.net/project/videlibri/Xidel/Xidel%200.9.6/xidel-0.9.6.win32.zip
[innoextract]
dist = http://constexpr.org/innoextract/
link = .zip
[7z]
dist = http://www.7-zip.org/download.html
link = .msi, !x64
link64 = x64.msi
"@

function get-dependency([string]$id)
{
	join-path $env:PINT_DEPS_DIR "$id\$id.exe"
}

function has-dependency([string]$id)
{
	is-file (get-dependency $id)
}

function install-dependency([string]$id)
{
	pint-force-install $id (join-path $env:PINT_DEPS_DIR $id) 32
}

function get-ini-sections([string]$ini, [string]$term)
{
	[regex]::Matches($ini, "(^|\n)\[(.*?$term.*?)\]", [Text.RegularExpressions.RegexOptions]::IgnoreCase) |% {$_.groups[2].value}
}

function basename([string]$f)
{
	[IO.Path]::GetFileNameWithoutExtension($f)
}

function dirname([string]$f)
{
	[IO.Path]::GetDirectoryName($f)
}

function get-pad($array)
{
	$max = $array | sort length -desc | select -first 1
	$max.length + 2
}

function web-client
{
	$client = new-object Net.WebClient
	$client.Headers['User-Agent'] = $env:PINT_USER_AGENT
	$client
}

function is-file([string]$p)
{
	test-path $p -pathtype leaf
}

function is-dir([string]$p)
{
	test-path $p -pathtype container
}

function ensure-dir([string]$p)
{
	if (!(is-dir $p)) { md $p -ea stop | out-null }
}

function string-to-xpath-simple([string]$str, [bool]$rss)
{
	$exts = @('.7z', '.zip', '.rar', '.paf.exe')

	(
		$str.ToLower() -split ',' |% {
			$p = $_.trim()
			$not = ($p[0] -eq '!')
			$attr = if ($rss -or ($p[-1] -eq '"')) { '.' } else { '@href' }
			$p = $p.trimstart('!').trim('"')

			switch ($p) {
				{@('.arch', '.any') -contains $_} {
					$e = if ($_ -eq '.any') { $exts + @('.exe') } else { $exts }
					$p = $e |% { "contains(lower-case($attr), `"$_`")" }
					$p = '(' + ($p -join ' or ') + ')'
					break
				}
				default {
					$p = "contains(lower-case($attr), `"$p`")"
				}
			}

			if ($not) { $p = "not($p)" }

			$p
		}
	) -join ' and '
}

function string-to-xpath([string]$str, [bool]$rss)
{
	($str -split '\|' |% {
		'(' + (string-to-xpath-simple $_ $rss) + ')'
	}) -join ' or '
}

function get-pint([string]$dir)
{
	dir (pint-dir $dir) -ea 1 -force -filter *.pint | select -first 1
}

function pint-get-app([string]$p)
{
	$p = pint-dir $p
	if (is-file $p) {
		$f = $p
		$dir = dirname $f
	} else {
		$f = dir (join-path $p '*.pint') -n -force -ea 0 | select -first 1
		if (!$f) { return }
		$f = join-path $p $f
		$dir = $p
	}

	$a = (basename $f).trim() -split ' '

	$app = @{
		id = $a[0]
		dir = $dir
		arch = $global:arch
		pinned = $false
		version = ""
		size = 0
	}

	$a = if ($a[1]) {$a[1..($a.count-1)]} else {@()}

	if ($a) {
		$a |% {
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
	$app.keys |% { $ini[$_] = $app[$_] }
	$ini
}

function pint-unpack([string]$file, [string]$dir)
{
	if (!(is-file $file)) {
		throw "Unable to find $file"
	}

	ensure-dir $dir

	$filename = [IO.Path]::GetFileName($file)

	write-host 'Unpacking' $filename

	$fullPath = [IO.Path]::GetFullPath($file)
	$sevenzip = get-dependency '7z'

	switch ([IO.Path]::GetExtension($file).ToLower()) {
		'.msi' {
			& $env:ComSpec /d /c "msiexec /a `"$fullPath`" /norestart /qn TARGETDIR=`"$dir`""
			break
		}
		{!(is-file $sevenzip) -and ($_ -eq '.zip')} {
			try {
				$shell = new-object -com Shell.Application
				$zip = $shell.NameSpace($fullPath)
				$shell.Namespace($dir).copyhere($zip.items(), 20)
			} catch {
				write-host "Pint needs 7-zip to unpack $filename, installing automatically..." -f white
				install-dependency '7z'
				& $env:ComSpec /d /c "`"$sevenzip`" x -y -aoa -o`"$dir`" `"$fullPath`"" | out-null
			}
			break
		}
		default {
			if (($_ -eq '.exe') -and (select-string -path $file -pattern 'Inno Setup')) {
				if (!(has-dependency 'innoextract')) {
					write-host "Pint needs innoextract to unpack $filename, installing automatically..." -f white
					install-dependency 'innoextract'
				}
				& (get-dependency 'innoextract') -s -c -p -d $dir $fullPath
				break
			}

			if (!(is-file $sevenzip)) {
				write-host "Pint needs 7-zip to unpack $filename, installing automatically..." -f white
				install-dependency '7z'
			}

			& $env:ComSpec /d /c "`"$sevenzip`" x -y -aoa -o`"$dir`" `"$fullPath`"" | out-null
		}
	}

	!$lastexitcode
}

function pint-read-ini([string]$term)
{
	$result = @{}
	$db = pint-db

	if (!$db.contains('[' + $term + ']')) {
		return $null
	}

	$text = ($db -split '\[' + $term + '\]')[-1]

	if ($text) {
		$lines = ($text -split "`n\[", 2)[0] -split "`n"

		$lines |% {
			$key, $val = $_ -split '=', 2

			if ($val -ne $null) {
				$key = $key.trim()
				if ($key[0] -ne ';') {
					$result[$key] = $val.trim()
				}
			}
		}
	}

	if ($result.keys.count) {$result} else {$null}
}

function pint-get-version([string]$dir)
{
	try {
		$v = (dir $dir -r -filter *.exe -ea stop | sort -property length -descending | select -first 1).VersionInfo.ProductVersion.trim()
		if ($v.contains(',')) { $v = $v.replace(',', '.') }
		if ($v.contains('-')) { $v = ($v -split '-', 2)[0] }
		if (!($v -match "^[0-9\.]+$")) { return }
		while ($v.substring($v.length-2, 2) -eq '.0') { $v = $v.substring(0, $v.length-2) }
		$v
	} catch {}
}

function pint-get-app-info([string]$id, [string]$arch)
{
	if (!$arch) { $arch = $global:arch }

	$ini = pint-read-ini $id
	if (!$ini) { return }

	$res = @{}
	$ini.keys | sort |% {
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

function pint-make-ftp-request([string]$url, [bool]$download)
{
	$req = [Net.WebRequest]::Create($url)
	$req.Timeout = $global:httpTimeout
	if (!$download) { $req.Method = [Net.WebRequestMethods+Ftp]::GetFileSize }
	$req.GetResponse()
}

function pint-make-http-request([string]$url, [bool]$download, [bool]$disableAutoRedirect)
{
	try {
		$req = [Net.WebRequest]::Create($url)
		$req.Timeout = $global:httpTimeout
		$req.UserAgent = $env:PINT_USER_AGENT
		$req.AllowAutoRedirect = !$disableAutoRedirect
		$req.MaximumAutomaticRedirections = $global:httpMaxRedirects
		$req.Accept = '*/*'
		if (!$url.contains('sourceforge.net')) {
			$req.Referer = $url
		}
		$req.GetResponse()
	} catch [Management.Automation.MethodInvocationException] {
		if ($_.Exception.Message -match '\((4|5)[\d]{2}\)') {
			throw $_.Exception.Message
		}

		$maxRedirects = $global:httpMaxRedirects
		while ($true) {
			if ($url.StartsWith('ftp:')) {
				return pint-make-ftp-request $url $download
			} else {
				$res = pint-make-http-request $url $download $true
				if ($res.headers['Location']) {
					$res.close()
					if ($maxRedirects-- -eq 0) {
						throw "Exceeded limit of redirections retrieving $url"
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

function pint-make-request([string]$url, [bool]$download)
{
	if ($url.StartsWith('ftp:')) {
		$res = pint-make-ftp-request $url $download
	} else {
		$res = pint-make-http-request $url $download
	}

	if (!$res) {
		throw "Failed to connect to $url"
	}

	if (([string]$res.ContentType).contains('text/html')) {
		$res.close()
		throw "$url responded with a HTML page."
	}

	if (!$download) { $res.close() }

	$res
}

function pint-get-dist-link([Hashtable]$info, [bool]$verbose)
{
	if (!$info['dist']) {
		throw "No dist key."
	}

	$dist = $info['dist']
	$link = $info['link']
	$follow = $info['follow']

	$rss = $dist.contains('/rss')

	if (!$link) {
		if ($dist.contains('portableapps.com/apps/')) {
			$link = "//a[contains(@href, '.paf.exe')]"
		} elseif ($dist.contains('filehippo.com/')) {
			$follow = "(//a[contains(@class, 'program-header-download-link')])[1]"
			$link = '//meta[@http-equiv="Refresh"]/@content'
		} elseif ($rss) {
			$link = '//item/link'
		} elseif ($dist.EndsWith('.xml') -or $dist.EndsWith('/pad.php')) {
			if ($verbose) { write-host 'PAD file detected.' }
			$link = "//Primary_Download_URL"
		}
	}

	if ($link) {
		if (!(has-dependency 'xidel')) {
			write-host "Pint needs Xidel to be able to extract links, installing automatically..." -f white
			install-dependency 'xidel'
		}

		if (!$link.contains('$json') -and !($link.contains('json('))) {
			if (!$link.contains('//')) {
				$link = string-to-xpath $link $rss
				$link = if ($rss) {"//link[$link]"} else {"//a[$link]"}
			}

			if ($link.contains('/a')) {
				$link += '/resolve-uri(normalize-space(@href), base-uri())'
			}
		}

		$link = $link.replace('"', "\`"")

		if ($follow) {
			if (!$follow.contains('//')) {
				$follow = ($follow -split '\|' |% {
					'--follow "(//a[' + (string-to-xpath-simple $_).replace('"', "\`"") + '])[1]"'
				}) -join ' '
			} else {
				$follow = $follow.replace('"', "\`"").replace(' | ', '" --follow "')
				$follow = " --follow `"$follow`""
			}
		}

		if ($verbose) {
			write-host 'Extracting a download link from' $dist
			$out = ''
		} else {
			$quiet = '--quiet'
			$out = '2>nul'
		}

		$method = if ($info['method']) {'-d "'+$info['data']+'" --method '+$info['method']} else {''}

		$proxy = ''
		$proxyConfig = get-itemproperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
		if ($proxyConfig.ProxyEnable) {
			$proxyAddr = $proxyConfig.ProxyServer -replace "^http://", ""
			$proxy = "--proxy=`"$proxyAddr`""
		}

		$dist = & $env:ComSpec /d /c "$out `"$(get-dependency 'xidel')`" $method $proxy --header=`"Referer: $dist`" --user-agent=`"$($env:PINT_USER_AGENT)`" `"$dist`" $follow $quiet --extract `"($link)[1]`""

		if ($lastexitcode -or !$dist -or !$dist.contains('://')) {
			$dist = $null
		} else {
			$dist = $dist.trim()

			if ($info['dist'].contains('filehippo.com/')) {
				$dist = 'http://filehippo.com' + ($dist -split '=', 2)[1]
			}
		}
	}

	if (!$dist) {
		throw "Unable to extract a link from $($info['dist'])"
	}

	$dist
}

function pint-is-app-outdated([Hashtable]$app, [bool]$download)
{
	if (($url = pint-get-dist-link $app) -and ($res = pint-make-request $url $download)) {
		if ($res.ContentLength -eq $app['size']) {
			if ($download) {
				$res.close()
			}
			return $false
		}
		$res
	}
}

function pint-download-file([Net.WebResponse]$res, [string]$targetFile)
{
	ensure-dir (dirname $targetFile)

	$totalLength = [Math]::Floor($res.ContentLength / 1024)

	write-host "Downloading $($res.ResponseUri) ($("{0:N2} MB" -f ($totalLength / 1024)))"

	$remoteName = pint-get-remote-name $res
	$rs = $res.GetResponseStream()
	$fs = new-object IO.FileStream $targetFile, 'Create'
	$buffer = new-object byte[] 512KB
	$count = $rs.Read($buffer, 0, $buffer.length)
	$downloaded = $count
	$progressBar = ($res.ContentLength -gt 1MB)

	while ($count -gt 0) {
		$fs.Write($buffer, 0, $count)
		$count = $rs.Read($buffer, 0, $buffer.length)
		if ($progressBar) {
			$downloaded += $count
			write-progress -activity "Downloading file $remoteName" -status "Downloaded ($([Math]::Floor($downloaded / 1024))K of $($totalLength)K): " -PercentComplete ((([Math]::Floor($downloaded / 1024)) / $totalLength)  * 100)
		}
	}

	write-progress -completed -activity "Downloading file $remoteName" -status "Done"

	$fs.Flush()
	$fs.Close()

	if ($fs.Dispose -ne $null) {
		$fs.Dispose()
		$rs.Dispose()
	}

	$res.Close()

	if (!$res.ContentLength -or $res.ContentLength -eq (new-object IO.FileInfo $targetFile).length) {
		$targetFile
	} else {
		del $targetFile -force
		throw "Unable to complete download from $($res.ResponseUri)"
	}
}

function pint-get-remote-name([Net.WebResponse]$res)
{
	if (($h = $res.headers['Content-Disposition']) -and $h.contains('=')) {
		$name = ($h -split '=', 2)[1].replace('"', '').trim()
	} else {
		$name = ([string]$res.ResponseUri -split '/')[-1]
	}

	($name -split '\?', 2)[0]
}

function distdir([string]$file)
{
	join-path $env:PINT_DIST_DIR $file
}

function pint-dir([string]$path)
{
	if (![IO.Path]::isPathRooted($path)) {
		$path = join-path $env:PINT_APP_DIR $path
	}
	$path
}

function pint-download-app([string]$id, [string]$arch, $res)
{
	if ($res -isnot [Net.WebResponse]) {
		if (!($info = pint-get-app-info $id $arch) -or !($url = pint-get-dist-link $info $true)) {
			throw "Unable to find $id in the database."
		}

		$arch = $info['arch']
		$res = pint-make-request $url $true
	}

	if (!$arch) { $arch = $global:arch }
	$name = pint-get-remote-name $res

	$file = distdir "$id--$arch--$name"

	if (is-file $file) {
		if ((new-object IO.FileInfo $file).length -eq $res.ContentLength) {
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

function pint-force-install([string]$id, [string]$dir, [string]$arch)
{
	$file = pint-download-app $id $arch
	if (!$file) { return }
	pint-file-install $id $file $dir $arch
}

function pint-file-install([string]$id, [string]$file, [string]$destDir, [string]$arch)
{
	if (!(is-file $file)) {
		throw [IO.FileNotFoundException] "Unable to find $file"
	}

	if (!$destDir) { $destDir = $id }
	$destDir = pint-dir $destDir

	if (!($info = pint-get-app $destDir) -and !($info = pint-get-app-info $id)) {
		throw "Unable to find $id in the database."
	}

	ensure-dir $destDir

	write-host 'Installing' $id 'to' $destDir

	if ($info['type'] -eq 'standalone') {
		copy -literalpath $file (join-path $destDir "$id.exe") -force
	} else {
		$tempDir = join-path $env:TEMP "pint-$id-$(get-random)"
		ensure-dir $tempDir

		pint-unpack $file $tempDir | out-null

		cd $tempDir

		if ($tempDir -ne $pwd) {
			throw "Unable to use $tempDir as a temporary directory."
		}

		$base = if ($info['base']) {$info['base']} else {'.exe'}

		foreach ($p in (dir $pwd -r -n)) {
			if ($p.contains($base)) {
				cd "$p\.."
				break
			}
		}

		$keep = if ($info['keep'] -ne $null) {
			$info['keep'] -split ',' |% {$_.trim()} |? {$_}
		} else {
			@('*.ini','*.db')
		}

		$params = @{
			include = $keep
			recurse = $true
			force = $true
			name = $true
			ea = 0
		}

		dir $destDir @params |% {
			$p = join-path $destDir $_
			if (is-dir $p) {
				ensure-dir "$pwd\$_"
				copy "$p\*" "$pwd\$_" -recurse -force
			} else {
				ensure-dir (dirname "$pwd\$_")
				copy $p "$pwd\$_" -force
			}
		}

		if ($info['only']) {
			$only = $info['only'] -split ',' |% {$_.trim()}  |? {$_}

			$params = @{
				include = $only
				recurse = $false
				force = $true
				name = $true
				ea = 0
			}

			dir $destDir @params |% { del "$destDir\$_" -force -recurse }

			dir $pwd @params |% {
				$p = join-path $pwd $_
				if (is-dir $p) {
					ensure-dir "$destDir\$_"
					copy "$p\*" "$destDir\$_" -recurse -force
				} else {
					ensure-dir (dirname "$destDir\$_")
					copy $p "$destDir\$_" -force
				}
			}
		} else {
			$xf = $info['xf'] + ' *.pint $R0'
			$xd = $info['xd'] + ' $0 $PLUGINSDIR $TEMP $_OUTDIR'

			& $env:COMSPEC /d /c "robocopy `"$pwd`" `"$destDir`" /E /PURGE /NJS /NJH /NFL /NDL /NC /NP /NS /R:2 /W:2 /XO /FFT /XF $xf /XD $xd" | out-null

			if ($lastexitcode -gt 7) {
				write-host "Detected errors while copying from $pwd with Robocopy (code $lastexitcode)."
			}
		}

		cd $destDir
		rd $tempDir -force -recurse
	}

	if ($version = pint-get-version $destDir) {
		write-host 'Detected version' $version
		$version = "v$version"
	}

	if (($arch -eq 32) -or ($arch -eq 64)) {
		$info['arch'] = $arch
	}

	$pintFile = (@($id, $version, $info['arch'], (new-object IO.FileInfo $file).length) |? {$_}) -join ' '
	$pintFile = join-path $destDir "$pintFile.pint"

	del (join-path $destDir '*.pint') -force
	$pintFile = ni $pintFile -type file -force
	$pintFile.attributes = 'Hidden'

	if ($destDir.StartsWith($env:PINT_APP_DIR)) {
		pint-shims $destDir $info['shim'] $info['noshim'] | out-null
	}
}

function pint-db
{
	$db = $global:dependencies

	if (!($env:PINT_DB).contains('://')) {
		$env:PINT_DB -split ',' |% {
			$db += "`n" + [IO.File]::ReadAllText($_.trim())
		}
		return $db
	}

	$cache = $env:PINT_DB_CACHE
	$timespan = new-timespan -days 1

	if ($env:PINT_DEV -or !(is-file $cache) -or (get-date) - (get-item $cache).LastWriteTime -gt $timespan) {
		$env:PINT_DB -split ',' |% {
			$db += "`n"
			$src = $_.trim()
			if ($src.contains('://')) {
				$db += (web-client).DownloadString($src)
			} elseif (is-file $src) {
				$db += [IO.File]::ReadAllText($src)
			}
		}
		$db | out-file $cache
		return $db
	}

	[IO.File]::ReadAllText($cache)
}

function pint-reinstall
{
	if (!$args.count) {
		write-host 'Set a directory to reinstall.'
		return
	}

	$args |% {
		try {
			if ($app = pint-get-app $_) {
				if ($app['pinned']) {
					throw "$_ is pinned, use unpin to allow this action."
				}
				pint-force-install $app['id'] $app['dir'] $app['arch']
			} else {
				pint-force-install $_ $_
			}
		} catch {
			write-warning $_
		}
	}
}

function pint-download
{
	if (!$args.count) {
		write-warning 'Set an ID to download.'
		return
	}

	$args |% {
		try {
			pint-download-app $_ | out-null
		} catch {
			write-warning $_
		}
	}
}

function pint-install
{
	if (!$args.count) {
		write-warning 'Set an ID to install.'
		return
	}

	$args |% { pint-installto $_ $_ }
}

function pint-installto([string]$id, [string]$dir, $arch)
{
	try {
		if (!$id -or !$dir) {
			write-host 'Set an ID and a destination directory.'
			return
		}

		if ((dir (pint-dir $dir) -name -force -ea 0)) {
			write-host (pint-dir $dir) 'is not empty.'
			$confirm = read-host -prompt 'Do you want to REPLACE its contents? [Y/N] '
			if ($confirm.trim().ToUpper() -ne 'Y') { return }
		}

		pint-force-install $id $dir $arch
	} catch {
		write-warning $_
	}
}

function pint-purge
{
	if (!$args.count) {
		write-warning 'Set a directory to purge.'
		return
	}
	pint-remove @args
	$args |% { del (distdir "$_--*.*") -force }
}

function pint-remove
{
	if (!$args.count) {
		write-warning 'Set a directory to remove.'
		return
	}

	$args |% {
		$dir = pint-dir $_

		if (is-dir $dir) {
			write-host "Uninstalling $_..."
			$app = pint-get-app $_
			if ($app) { pint-shims $dir $app['shim'] $app['noshim'] $true }
			rd -literalpath $dir -recurse -force
			write-host $_ 'is removed.'
		} else {
			write-host $_ 'is not installed.'
		}
	}
}

function pint-outdated
{
	write-host 'Checking for updates...'

	if (!$args.count) { $args = pint-l }
	$pad = get-pad $args

	$args |% {
		write-host $_.padright($pad, ' ') -nonewline

		try {
			$app = pint-get-app $_

			if (!$app) {
				write-host 'NOT FOUND' -f red
				return
			}

			if (!$app['size']) {
				write-host 'NO SIZE DATA' -f darkyellow
				return
			}

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
	$pad = get-pad $args

	$args |% {
		write-host $_.padright($pad, ' ') -nonewline

		try {
			$app = pint-get-app $_

			if (!$app) {
				write-host 'NOT FOUND' -f red
				return
			}

			if ($app['pinned']) {
				write-host 'PINNED' -f yellow
				return
			}

			if (!$app['size']) {
				write-host 'NO SIZE DATA' -f darkyellow
				return
			}

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
	dir $env:PINT_APP_DIR -n -r -force -filter *.pint |% { dirname $_ }
}

function pint-list
{
	$table = @()
	$fso = new-object -com Scripting.FileSystemObject

	dir $env:PINT_APP_DIR -n -r -force -filter *.pint |% {
		$dir = dirname $_
		$name = basename $_
		$id = ($name -split ' ', 2)[0]
		$arch = if ($name.contains(' 32 ')) { 32 } else { 64 }
		$fullpath = pint-dir $dir

		$table += new-object -TypeName PSObject -Prop @{
			ID = $id
			Directory = $dir + '  '
			Size = '{0:N2} MB' -f (($fso.GetFolder($fullpath).Size) / 1MB)
			Version = (pint-get-version $fullpath) + $(if ($name.contains(' pinned')) {' (pinned)'})
			Arch = $arch
		}
	}
	$table | ft Directory,ID,Version,Size,Arch -autosize
}

function pint-self-update
{
	write-host 'Fetching' $env:PINT_SELF_URL

	$res = (web-client).DownloadString($env:PINT_SELF_URL)

	if ($res -and $res.contains('PINT - Portable INsTaller')) {
		$res | out-file $env:PINT -encoding ascii
		write-host 'Pint was updated to the latest version.' -f green
	} else {
		write-host 'Self-update failed!' -f red
		exit 1
	}
}

function pint-forget
{
	$args |% {
		try {
			get-pint $_ | del -force
			write-host $_ 'is no longer managed by Pint.'
		} catch {
			write-warning $_
		}
	}
}

function pint-pin
{
	$args |% {
		try {
			get-pint $_ | ren -NewName { $_.Name -replace ' pinned','' -replace '.pint$',' pinned.pint' }
			write-host $_ 'is pinned.'
		} catch {
			write-warning $_
		}
	}
}

function pint-unpin
{
	$args |% {
		try {
			get-pint $_ | ren -NewName { $_.Name -replace ' pinned','' }
			write-host $_ 'is unpinned.'
		} catch {
			write-warning $_
		}
	}
}

function pint-search([string]$term)
{
	get-ini-sections (pint-db) $term
}

function pint-cleanup
{
	dir (distdir '*') |% {
		write-host 'Removing' $_.Name
		del -r $_
	}
}

function pint-shims([string]$dir, [string]$include, [string]$exclude, [bool]$delete)
{
	if (!(has-dependency 'shimgen')) {
		install-dependency 'shimgen'
	}

	if (!$dir) {
		del (join-path $env:PINT_SHIM_DIR '*') -force
		$dir = $env:PINT_APP_DIR
	}

	$params = @{
		recurse = $true
		force = $true
		name = $true
		exclude = $exclude -split ',' |% {$_.trim()} |? {$_}
		ea = 0
	}

	if ($include) {
		$includeArr = $include -split ',' |% {$_.trim()} |? {$_}
		$params['include'] = @('*.exe') + $includeArr
	} else {
		$params['filter'] = '*.exe'
	}

	ensure-dir $env:PINT_SHIM_DIR
	cd $env:PINT_SHIM_DIR

	dir $dir @params |% {
		$exe = $_
		$relpath = join-path $dir $_

		if ([IO.Path]::GetExtension($_) -eq '.exe' -and (!$includeArr -or !($includeArr |? { $exe -like $_ }))) {
			$subsystem = $null
			try {
				$fs = [IO.File]::OpenRead($relpath)
				$br = new-object IO.BinaryReader $fs
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

		$baseName = [IO.Path]::GetFileName($_)
		$shim = join-path $env:PINT_SHIM_DIR $baseName

		if ($delete) {
			if (is-file $shim) {
				del $shim
				write-host "Removed" $baseName
			}
		} else {
			$relpath = rvpa -relative -literalpath $relpath
			& (get-dependency 'shimgen') -p $relpath -o $shim -i $relpath | out-null
			write-host "Added" $baseName
		}
	}
}

function pint-test([string]$subject)
{
	$env:PINT_DEV = $true

	if ($subject) {
		if ($subject.contains('://')) {
			$list = get-ini-sections (web-client).DownloadString($subject)
		} elseif ($subject.contains('.ini')) {
			if (!$subject.contains(':')) { $subject = "$env:PINT\..\$subject" }
			$list = get-ini-sections [IO.File]::ReadAllText($subject)
		} else {
			$list = pint search $subject
		}
	} else {
		$list = pint search
	}

	$list = $list -split "`n"
	$pad = get-pad $list

	$list |% {
		$id = $_.trim()
		write-host $id.padright($pad, ' ') -nonewline

		try {
			$info = pint-get-app-info $id
			$url = pint-get-dist-link $info
			$res = pint-make-request $url $false
			write-host $res.Headers['Content-Type'] ('(' + $res.Headers['Content-Length'] + ')') -f green
		} catch {
			write-host $_ -f red
		}
	}
}

function pint-usage
{
	write-host "PINT - Portable INsTaller`n" -f white
	write-host "Usage:"
	write-host "pint `<command`> `<parameters`>`n" -f yellow
	write-host "Available commands:"

	@(
		@('self-update', 'Update Pint.'),
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
		@('purge <dir>', 'Delete selected apps AND their archives.'),
		@('cleanup', 'Delete archives from dist.'),
		@('forget <dir>', 'Stop tracking of selected apps.'),
		@('download <app>', 'Only download selected installers without unpacking them.'),
		@('shims', 'Recreate all shim files.'),
		@('test [<app>|<file.ini>]', 'Test app definitions.')
	) |% {
		write-host $_[0].padright(24, ' ') -f green -nonewline
		write-host $_[1]
	}

	write-host "`n`<app`> is a database ID, which can be seen via the search command."
	write-host "`<dir`> is a path, relative to the 'apps' directory, as shown via 'list' command."
}

function pint-start($in)
{
	if (!$in) { pint-usage; exit 0 }

	$cmd = 'pint-' + $in

	try {
		& (gcm $cmd -ea 1) @args
		exit $lastexitcode
	} catch {
		write-host 'Unknown command' -f red
		exit 1
	}
}
