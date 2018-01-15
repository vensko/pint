<# :
@echo off
@setlocal

rem PINT - Portable INsTaller
rem https://github.com/vensko/pint

SET "PINT=%~f0"
set "PINT_SELF_URL=https://raw.githubusercontent.com/vensko/pint/master/pint.cmd"

rem Set variables if they weren't overriden
if not defined PINT_DIST_DIR set "PINT_DIST_DIR=%~dp0dist"
if not defined PINT_APP_DIR set "PINT_APP_DIR=%~dp0apps"
if not defined PINT_DEPS_DIR set "PINT_DEPS_DIR=%~dp0deps"
if not defined PINT_SHIM_DIR set "PINT_SHIM_DIR=%PINT_APP_DIR%\.shims"
if not defined PINT_USER_AGENT set "PINT_USER_AGENT=PintBot/1.0 (+https://github.com/vensko/pint)"
if not defined PINT_DB set "PINT_DB=https://d.vensko.net/pint/db/packages.ini, https://d.vensko.net/pint/db/portableapps.com.ini, %~dp0packages.user.ini"
if not defined PINT_CACHE_TTL set "PINT_CACHE_TTL=24"

rem Start 64bit PowerShell even from 32bit command line
SET "POWERSHELL=%SystemRoot%\sysnative\windowspowershell\v1.0\powershell.exe"
if not exist "%POWERSHELL%" set "POWERSHELL=powershell"

set "_args=%*"
if defined _args set "_args=%_args:"=""""""%"
%POWERSHELL% -NoLogo -NoProfile -executionpolicy bypass "$s = ${%PINT%} | out-string; $s += """pint-start %_args%"""; iex($s)" || exit /b 1
exit /b 0

end Batch / begin PowerShell #>

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

$global:httpMaxRedirects = 5
$global:httpTimeout = 15000
$global:arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') {32} else {64}
$global:db = ''

$global:dependencies = @"
[xidel]
dist = https://master.dl.sourceforge.net/project/videlibri/Xidel/Xidel%200.9.6/xidel-0.9.6.win32.zip
[innoextract]
dist = https://github.com/dscharrer/innoextract/releases/latest
link = win, .zip
[7z]
dist = http://www.7-zip.org/download.html
link = .msi, !x64
only = 7z.exe, 7z.dll
[shimgen]
dist = https://github.com/chocolatey/choco/raw/master/src/chocolatey.resources/tools/shimgen.exe
type = standalone
"@ + "`n"

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
	if (!(is-dir $p)) { md $p -ea 1 | out-null }
}

function clist([string]$str)
{
	[array]($str -split ',' |% trim |? {$_})
}

function get-pad($list)
{
	$max = $list | sort length -desc | select -first 1
	$max.length + 2
}

function string-to-xpath([string]$str, [bool]$rss)
{
	$exts = @('.7z', '.zip', '.rar', '.paf.exe')

	(
		clist $str.ToLower() |% {
			$p = $_
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

function ini-get-sections([string]$ini, [string]$search)
{
	[regex]::Matches($ini, "(?:^|\n)\[(.*?$search.*?)\]", 'IgnoreCase') |% {$_.groups[1].value} | get-unique
}

function pint-info([string]$section)
{
	$m = [regex]::Matches((pint-db), "(?:^|\n)\[$section\](((?!\n\[).)+)", 'Singleline,IgnoreCase')

	if (!$m.count) {
		throw "Unable to find '$section' in the database."
	}

	$res = @{}
	[regex]::Matches($m[$m.count-1].groups[1].value, "^\s*(\w+?)\s*=\s*(.+)\s*$", 'm') |% {
		$res[$_.groups[1].value] = $_.groups[2].value.trim()
	}
	$res
}

function get-text($src)
{
	$client = new-object Net.WebClient
	$client.Headers['User-Agent'] = $env:PINT_USER_AGENT
	$client.DownloadString($src)
}

function pint-make-ftp-request([string]$url, [bool]$download)
{
	$req = [Net.WebResponse]::Create($url)
	$req.Timeout = $global:httpTimeout
	if (!$download) { $req.Method = [Net.WebRequestMethods+Ftp]::GetFileSize }
	$req.GetResponse()
}

function pint-make-http-request([string]$url, [bool]$download)
{
	try {
		$req = [Net.WebRequest]::Create($url)
		$req.Timeout = $global:httpTimeout
		$req.UserAgent = $env:PINT_USER_AGENT
		$req.AllowAutoRedirect = $true
		$req.MaximumAutomaticRedirections = $global:httpMaxRedirects
		$req.Accept = '*/*'
		if (!$url.contains('sourceforge.net')) {
			$req.Referer = $url
		}
		$req.GetResponse()
	} catch [Management.Automation.MethodInvocationException] {
		$e = $_.Exception.InnerException
		$headers = $e.Response.Headers

		if ($headers -and ([string]$headers['Location']).StartsWith('ftp:')) {
			return pint-make-ftp-request $headers['Location'] $download
		}

		throw $e
	}
}

function pint-make-request([string]$url, [bool]$download)
{
	if ($url.StartsWith('ftp:')) {
		$res = pint-make-ftp-request $url $download
	} else {
		$res = pint-make-http-request $url $download

		if (([string]$res.ContentType).contains('text/html')) {
			$res.close()
			throw "$url responded with a HTML page."
		}
	}

	if (!$download) { $res.close() }

	$res
}

function download-file([Net.WebResponse]$res, [string]$targetFile)
{
	ensure-dir (split-path $targetFile)

	$totalLength = [Math]::Floor($res.ContentLength / 1024)

	write-host "Downloading $($res.ResponseUri) ($("{0:N2} MB" -f ($totalLength / 1024)))"

	$remoteName = get-remote-name $res
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

	if ($res.ContentLength -lt 1 -or $res.ContentLength -eq (gi $targetFile).length) {
		write-host 'Saved to' $targetFile
		$targetFile
	} else {
		del $targetFile -force
		throw "Unable to complete download from $($res.ResponseUri)"
	}
}

function get-remote-name([Net.WebResponse]$res)
{
	$name = if (($h = $res.Headers['Content-Disposition']) -and $h.contains('=')) {
		($h -split '=', 2)[1].replace('"', '').trim()
	} else {
		($res.ResponseUri -split '/')[-1]
	}

	($name -split '\?', 2)[0]
}

function get-dependency([string]$id)
{
	if (!(has-dependency $id)) {
		write-host "Pint requires $id for this operation, installing automatically..."
		pint-force-install $id (join-path $env:PINT_DEPS_DIR $id) 32
	}

	join-path $env:PINT_DEPS_DIR "$id\$id.exe"
}

function has-dependency([string]$id)
{
	is-file (join-path $env:PINT_DEPS_DIR "$id\$id.exe")
}

function pint-unpack([string]$file, [string]$dir, [string]$type)
{
	$item = gi $file
	$file = $item.fullname
	write-host 'Unpacking' $item.name
	ensure-dir $dir

	switch ($item.extension) {
		'.msi' {
			& $env:ComSpec /d /c "msiexec /a `"$file`" /norestart /qn TARGETDIR=`"$dir`""
			break
		}
		{($type -eq 'inno') -or (($_ -eq '.exe') -and (select-string -path $file -pattern 'Inno Setup'))} {
			& (get-dependency 'innoextract') -s -c -p -d $dir $file
			break
		}
		{($_ -eq '.zip') -and !(has-dependency '7z')} {
			try {
				$shell = new-object -com Shell.Application
				$zip = $shell.NameSpace($file)
				$items = $zip.items()
				if ($items.item(0)) {
					$shell.Namespace($dir).copyhere($items, 20)
					break
				}
			} catch {}
		}
		{$true} {
			$type = if ($type) {"-t$type"} else {''}
			& $env:ComSpec /d /c "`"$(get-dependency '7z')`" x $type -y -bd -bso0 -bsp0 -aoa -o`"$dir`" `"$file`""
		}
	}
}

function pint-get-version([string]$dir)
{
	try {
		$files = dir $dir -filter *.exe -exclude *portable.exe -ea 0
		if (!$files) { $files = dir $dir -r -filter *.exe -exclude *portable.exe -ea 1 }
		$v = ($files | sort length -desc | select -first 1).VersionInfo.ProductVersion.trim()
		$v = $v.replace(', ', '.').replace(',', '.')
		$v = ($v -split '[- ]+', 2)[0]
		if (!($v -match "^[0-9\.]+$")) { return }
		while ($v.endswith('.0')) { $v = $v.substring(0, $v.length-2) }
		$v
	} catch {}
}

function distdir([string]$file)
{
	join-path $env:PINT_DIST_DIR $file
}

function appdir([string]$path)
{
	if (![IO.Path]::isPathRooted($path)) {
		$path = join-path $env:PINT_APP_DIR $path
	}
	$path
}

function get-pint([string]$dir, [int]$ea = 1)
{
	gi ((appdir $dir) + "\*.pint") -force -ea $ea
}

function pint-get-installed-app([string]$p)
{
	$app = @{
		dir = appdir $p
		arch = $global:arch
		pinned = $false
		version = ""
		size = 0
	}

	$file = get-pint $app.dir 0
	if (!$file) { return }

	$app.id, $a = $file.basename.trim() -split '[ ]+'

	$a |% {
		switch ($_) {
			'pinned' { $app[$_] = $true }
			{@(32,64) -contains $_} { $app.arch = $_ }
			{$_ -match "^v[\d\.]+$"} { $app.version = $_.substring(1) }
			{$_ -match "^\d+$"} { $app.size = [int]$_ }
		}
	}

	$app
}

function pint-get-app-meta([string]$id, [string]$arch = $global:arch)
{
	$ini = pint-info $id

	$res = @{}
	$ini.keys | sort |% {
		if ($_.endswith(64)) {
			if ($arch -eq 64) {
				$res[$_.substring(0, $_.length-2)] = $ini[$_]
			}
		} else {
			$res[$_] = $ini[$_]
		}
	}

	if (!$res.dist) {
		throw "No 'dist' key found in '$id' metadata."
	}

	$res
}

function get-dist-link([Hashtable]$meta, [bool]$verbose)
{
	$dist = $meta.dist
	$link = $meta.link
	$follow = $meta.follow

	$rss = $dist.contains('/rss')

	if (!$link) {
		if ($rss) {
			$link = '//item/link'
		} elseif ($dist.EndsWith('.xml') -or $dist.EndsWith('/pad.php')) {
			if ($verbose) { write-host 'PAD file detected.' }
			$link = "//Primary_Download_URL"
		}
	}

	if ($link) {
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
					'--follow "(//a[' + (string-to-xpath $_).replace('"', "\`"") + '])[1]"'
				}) -join ' '
			} else {
				$follow = $follow.replace('"', "\`"") -replace '\s*\|\s*','" --follow "'
				$follow = " --follow `"$follow`""
			}
		}

		if ($verbose) {
			write-host 'Extracting download link from' $dist
			$out = ''
		} else {
			$silent = '--silent'
			$out = '2>nul'
		}

		$method = if ($meta.method) {'-d "'+$meta.data+'" --method '+$meta.method} else {''}

		$proxy = ''
		$proxyConfig = get-itemproperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
		if ($proxyConfig.ProxyEnable) {
			$proxyAddr = $proxyConfig.ProxyServer -replace "^http://", ""
			$proxy = "--proxy=`"$proxyAddr`""
		}

		$xidel = get-dependency 'xidel'
		$dist = & $env:ComSpec /d /c "$out `"$xidel`" $method $proxy --header=`"Referer: $dist`" --user-agent=`"$($env:PINT_USER_AGENT)`" `"$dist`" $follow $silent --extract `"($link)[1]`""

		if ($lastexitcode -or !$dist -or !$dist.contains('://')) {
			$dist = $null
		} else {
			$dist = $dist.trim()
		}
	}

	if (!$dist) {
		throw "Unable to extract the link from $($meta.dist)"
	}

	$dist
}

function make-app-request([string]$id, [string]$arch, [bool]$download, [bool]$verbose)
{
	$meta = pint-get-app-meta $id $arch
	$url = get-dist-link $meta $verbose
	pint-make-request $url $download
}

function pint-download-app([string]$id, [string]$arch = $global:arch, $res = $null)
{
	if ($res -isnot [Net.WebResponse]) {
		$res = make-app-request $id $arch $true $true
	}

	$name = get-remote-name $res

	$file = distdir "$id--$arch--$name"

	if ((is-file $file) -and (gi $file).length -eq $res.ContentLength) {
		$res.close()
		write-host 'The local file has the same size as the remote one, skipping redownloading.'
		return $file
	}

	download-file $res $file
}

function pint-force-install([string]$id, [string]$dir, [string]$arch = $global:arch)
{
	$file = pint-download-app $id $arch
	pint-file-install $id $file $dir $arch
}

function pint-file-install([string]$id, [string]$file, [string]$destDir, [string]$arch = $global:arch)
{
	if (!$destDir) { $destDir = $id }

	$item = gi $file
	$destDir = appdir $destDir
	$meta = pint-get-app-meta $id $arch

	write-host 'Installing' $id 'to' $destDir

	ensure-dir $destDir

	if ($meta.type -eq 'standalone') {
		copy -literalpath $file (join-path $destDir "$id.exe") -force
	} else {
		$tempDir = join-path $env:TEMP "pint-$id-$(get-random)"
		ensure-dir $tempDir

		pint-unpack $file $tempDir $meta.type

		cd $tempDir

		if ($tempDir -ne $pwd) {
			throw "Unable to use $tempDir as a temporary directory."
		}

		$base = if ($meta.base) {$meta.base} else {'.exe'}

		foreach ($p in (dir $pwd -r -n)) {
			if ($p.contains($base)) {
				cd "$p\.."
				break
			}
		}

		$keep = if ($meta.keep) {
			clist $meta.keep
		} else {
			@('*.ini','*.db')
		}

		if ($meta.create) {
			$keep += clist $meta.create
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
				ensure-dir (split-path "$pwd\$_")
				copy $p "$pwd\$_" -force
			}
		}

		if ($meta.only) {
			$params = @{
				include = clist $meta.only
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
					ensure-dir (split-path "$destDir\$_")
					copy $p "$destDir\$_" -force
				}
			}
		} else {
			$purge = if ($meta.purge -eq 'false') {''} else {'/PURGE'}
			$xf = ([string]$meta.xf).replace(',', ' ') + ' *.pint $R0'
			$xd = ([string]$meta.xd).replace(',', ' ') + ' $0 $PLUGINSDIR $TEMP $_OUTDIR'

			& $env:COMSPEC /d /c "robocopy `"$pwd`" `"$destDir`" /E /NJS /NJH /NFL /NDL /NC /NP /NS /R:1 /W:1 /XO /FFT $purge /XF $xf /XD $xd" | out-null

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

	if ($meta.create) {
		clist $meta.create |% {
			$createfile = join-path $destDir $_
			if (!(is-file $createfile)) {
				if ($createdir = split-path $_) {
					ensure-dir $createdir
				}
				ni $createfile -type file -force | out-null
			}
		}
	}

	$pintFile = (@($id, $version, $arch, $item.length) |? {$_}) -join ' '
	$pintFile = join-path $destDir "$pintFile.pint"

	del (join-path $destDir '*.pint') -force
	$pintFile = ni $pintFile -type file -force
	$pintFile.attributes = 'Hidden'

	if ($destDir.StartsWith($env:PINT_APP_DIR)) {
		pint-shims $destDir $meta.shim $meta.noshim | out-null
	}
}

function pint-db
{
	if ($global:db) {
		return $global:db
	}

	$db = $global:dependencies
	$timespan = new-timespan -hours $env:PINT_CACHE_TTL

	clist $env:PINT_DB |% {
		try {
			$url = $file = $_

			if ($file.contains('://')) {
				if ($env:PINT_CACHE_TTL -gt 0) {
					$cache = $_ -replace '[^\w]', ''
					$file = join-path $env:TEMP "pint-cache-$cache.ini"

					if (!(is-file $file) -or (get-date) - (gi $file).LastWriteTime -gt $timespan) {
						$text = get-text $_
						$text | out-file $file -encoding ascii
					}
				}
			} elseif (!(is-file $file)) {
				return
			}

			$db += "`n" + (get-text $file)
		} catch {
			write-host $_.Exception.InnerException.Message ' ' $url -f red
			return
		}
	}

	($global:db = $db)
}

function pint-reinstall
{
	if (!$args.count) {
		write-host 'Specify a directory to reinstall.'
		return
	}

	$args |% {
		try {
			if ($app = pint-get-installed-app $_) {
				if ($app.pinned) {
					throw "$_ is pinned, use unpin to allow this action."
				}
				pint-force-install $app.id $app.dir $app.arch
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
		write-warning 'Specify an ID to download.'
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
		write-warning 'Specify an ID to install.'
		return
	}

	$args |% { pint-installto $_ $_ }
}

function pint-installto([string]$id, [string]$dir, [string]$arch = $global:arch)
{
	try {
		if (!$id -or !$dir) {
			write-host 'Specify an ID and a destination directory.'
			return
		}

		if ((dir (appdir $dir) -name -force -ea 0)) {
			write-host (appdir $dir) 'is not empty.'
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
		write-warning 'Specify a directory to purge.'
		return
	}

	$args |% {
		if ($app = pint-get-installed-app $_) {
			del (distdir "$($app.id)--*.*") -force
		}
	}

	pint-remove @args
}

function pint-remove
{
	if (!$args.count) {
		write-warning 'Specify a directory to remove.'
		return
	}

	$args |% {
		try {
			$app = pint-get-installed-app $_

			if (!$app) {
				throw "$_ is not installed."
			}

			write-host "Uninstalling $_..."

			$meta = pint-get-app-meta $app.id $app.arch
			pint-shims $app.dir $meta.shim $meta.noshim $true

			rd -literalpath $app.dir -recurse -force
			write-host $_ 'is removed.'
		} catch {
			write-warning $_
		}
	}
}

function pint-outdated
{
	write-host 'Checking for updates...'

	if (!$args.count) { $args = pint-l }
	$pad = get-pad $args
	$download = [bool]$global:upgrade

	$args |% {
		write-host $_.padright($pad, ' ') -nonewline

		try {
			$app = pint-get-installed-app $_

			if (!$app) {
				write-host 'NOT FOUND' -f red
				return
			}

			if ($download -and $app.pinned) {
				write-host 'PINNED' -f yellow
				return
			}

			if (!$app.size) {
				write-host 'NO SIZE DATA' -f darkyellow
				return
			}

			$res = make-app-request $app.id $app.arch $download $false

			if ($res.ContentLength -eq $app.size) {
				write-host 'UP TO DATE' -f green
				return
			}

			write-host 'OUTDATED' -f yellow

			if ($download) {
				$file = pint-download-app $app.id $app.arch $res
				pint-file-install $app.id $file $app.dir $app.arch
			}
		} catch {
			write-host $_ -f red
		}
	}
}

function pint-upgrade
{
	$global:upgrade = $true
	pint-outdated @args
}

function pint-l
{
	dir $env:PINT_APP_DIR -n -r -force -filter *.pint | split-path
}

function pint-list
{
	$table = @()
	$fso = new-object -com Scripting.FileSystemObject

	pint-l |% {
		$app = pint-get-installed-app $_

		$table += new-object -TypeName PSObject -Prop @{
			ID = $app.id
			Directory = $_ + '  '
			Size = '{0:N2} MB' -f (($fso.GetFolder($app.dir).Size) / 1MB)
			Version = (pint-get-version $app.dir) + $(if ($app.pinned) {' (pinned)'})
			Arch = $app.arch
		}
	}

	$table | ft Directory,ID,Version,Size,Arch -autosize
}

function pint-self-update
{
	write-host 'Fetching' $env:PINT_SELF_URL

	$res = get-text $env:PINT_SELF_URL

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
			get-pint $_ | ren -NewName { $_.name -replace ' pinned','' -replace '.pint$',' pinned.pint' }
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
			get-pint $_ | ren -NewName { $_.name -replace ' pinned','' }
			write-host $_ 'is unpinned.'
		} catch {
			write-warning $_
		}
	}
}

function pint-search([string]$term)
{
	ini-get-sections (pint-db) $term | sort
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
	$shimdir = $env:PINT_SHIM_DIR

	if (!$dir) {
		del (join-path $shimdir '*') -force
		$dir = $env:PINT_APP_DIR
	}

	$params = @{
		recurse = $true
		force = $true
		exclude = clist $exclude
		ea = 0
	}

	if ($include) {
		$includeArr = clist $include
		$params.include = @('*.exe') + $includeArr
	} else {
		$params.filter = '*.exe'
	}

	ensure-dir $shimdir
	cd $shimdir

	dir $dir @params |% {
		$name = $_.name

		if ($_.extension -eq '.exe' -and (!$includeArr -or !($includeArr |? { $name -like $_ }))) {
			$subsystem = $null
			try {
				$fs = [IO.File]::OpenRead($_.fullname)
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
				if ($br) { $br.Close() }
				if ($fs) { $fs.Close() }
			}
			if ($subsystem -ne 3) { return }
		}

		$shim = join-path $shimdir $name

		if ($delete) {
			if (is-file $shim) {
				del $shim
				write-host 'Removed' $name
			}
		} else {
			$relpath = rvpa -relative -literalpath $_.fullname
			& (get-dependency 'shimgen') -p $relpath -o $shim -i $relpath | out-null
			write-host 'Added' $name
		}
	}
}

function pint-test([string]$subject, [string]$arch = $global:arch)
{
	$env:PINT_CACHE_TTL = 0

	$list = if ($subject -match '[:\.]') {
		$global:db = get-text $subject
		ini-get-sections $global:db
	} else {
		pint-search $subject
	}

	$pad = get-pad $list

	$list |% {
		write-host $_.padright($pad, ' ') -nonewline

		try {
			$res = make-app-request $_ $arch
			write-host $res.ContentType ('(' + $res.ContentLength + ')') -f green
		} catch {
			write-host $_ -f red
		}
	}
}

function pint-help
{
	write-host "PINT - Portable INsTaller`n" -f white
	write-host "Usage:"
	write-host "pint `<command`> `<parameters`>`n" -f yellow
	write-host "Available commands:"

	@(
		@('self-update', 'Update Pint.'),
		@('search [<term>]', 'Search for an app in the database, or show all items.'),
		@('installto <app> <dir> [32|64] ', 'Install the app to the given directory.'),
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
		@('test [<app>|<file.ini>] [32|64] ', 'Test app definitions.'),
		@('info <app>', 'Show package configuration.'),
		@('db', 'Output all database entries.'),
		@('unpack <file> <path>', 'Extract a file to a specified directory.')
	) |% {
		write-host $_[0].padright(24, ' ') -f green -nonewline
		write-host $_[1]
	}

	write-host "`n`<app`> is a database ID, which can be seen via the search command."
	write-host "`<dir`> is a path, relative to the 'apps' directory, as shown via 'list' command."
}

function pint-start($cmd)
{
	if (!$cmd) { pint-help; exit 0 }

	$cmd = 'pint-' + $cmd

	if (gcm $cmd -ea 0) {
		& $cmd @args
		exit $lastexitcode
	}

	write-host 'Unknown command'
	exit 1
}
