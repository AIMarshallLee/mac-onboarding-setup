$ErrorActionPreference = 'Stop'
$env:INSTALLER_LIB_ONLY = '1'
$env:VERSION_TIMEOUT_SECONDS = '1'

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1')

$fixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) ("navigator-installer-test-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureDir | Out-Null
$slowCommand = Join-Path $fixtureDir 'slow-version.cmd'
Set-Content -LiteralPath $slowCommand -Encoding Ascii -Value "@echo off`r`nping 127.0.0.1 -n 6 >nul`r`necho slow-version 1.0`r`n"

$oldPath = $env:Path
try {
  $env:Path = "$fixtureDir;$oldPath"
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  $usable = Cmd-Usable 'slow-version'
  $watch.Stop()

  if($usable){ throw 'timed-out version command was reported as usable' }
  if($watch.Elapsed.TotalSeconds -ge 4){ throw "version timeout took too long: $($watch.Elapsed.TotalSeconds)s" }
  Write-Host 'PASS  Windows rejects a hung version command within the configured timeout'

  if(-not (Test-SpaceRequirement -FreeBytes 10GB -MinimumGB 10)){ throw '10GB should satisfy the disk requirement' }
  if(Test-SpaceRequirement -FreeBytes 9GB -MinimumGB 10){ throw '9GB should fail the disk requirement' }

  $courseRoot = Join-Path $fixtureDir '我的跨境Agent大课'
  New-Item -ItemType Directory -Path $courseRoot | Out-Null
  if(Test-CourseWorkspace -Path $courseRoot){ throw 'incomplete course workspace was reported ready' }
  foreach($dir in @('01-我的业务','02-我自己','03-数据包','04-机会卡','05-我的Agent')){
    New-Item -ItemType Directory -Path (Join-Path $courseRoot $dir) | Out-Null
  }
  if(-not (Test-CourseWorkspace -Path $courseRoot)){ throw 'complete course workspace was not reported ready' }
  if(Find-DirectionChecklist -Path $courseRoot){ throw 'missing direction checklist was reported present' }
  Set-Content -LiteralPath (Join-Path $courseRoot '01-我的业务\我的方向清单.md') -Value 'directions'
  if(-not (Find-DirectionChecklist -Path $courseRoot)){ throw 'direction checklist was not found recursively' }
  if(Test-CoursePreworkFiles -Path $courseRoot){ throw 'direction checklist alone should not complete official prework' }
  Set-Content -LiteralPath (Join-Path $courseRoot '02-我自己\人格档案.json') -Value 'profile'
  Set-Content -LiteralPath (Join-Path $courseRoot '02-我自己\AI协作说明.md') -Value 'guide'
  Set-Content -LiteralPath (Join-Path $courseRoot '01-我的业务\我的业务说明书.md') -Value 'business'
  if(-not (Test-CoursePreworkFiles -Path $courseRoot)){ throw 'all four official prework files should be detected' }
  if(Test-CourseDataPackage -Path $courseRoot){ throw 'empty course data folder should not be ready' }
  New-Item -ItemType File -Path (Join-Path $courseRoot '03-数据包\ABA_原始数据.zip') | Out-Null
  if(Test-CourseDataPackage -Path $courseRoot){ throw 'downloaded zip without extracted data should not be ready' }
  $env:COURSE_DATA_MIN_BYTES = '1'
  Set-Content -LiteralPath (Join-Path $courseRoot '03-数据包\W1.json.gz') -Value 'data'
  if(-not (Test-CourseDataPackage -Path $courseRoot)){ throw 'extracted course data should be detected' }

  $fakeFeishu = Join-Path $fixtureDir 'Feishu.exe'
  if(Test-FeishuDesktopInstalled -CandidatePaths @($fakeFeishu) -SkipPackageLookup){ throw 'missing Feishu executable was reported installed' }
  New-Item -ItemType File -Path $fakeFeishu | Out-Null
  if(-not (Test-FeishuDesktopInstalled -CandidatePaths @($fakeFeishu) -SkipPackageLookup)){ throw 'Feishu executable candidate was not detected' }

  $codexDir = Join-Path $fixtureDir 'OpenAI\Codex\bin\release-id'
  New-Item -ItemType Directory -Path $codexDir | Out-Null
  $codexPath = Join-Path $codexDir 'codex.exe'
  New-Item -ItemType File -Path $codexPath | Out-Null
  New-Item -ItemType File -Path (Join-Path $codexDir 'codex-windows-sandbox-setup.exe') | Out-Null
  if((Codex-BinDir -CommandPath $codexPath) -ne $codexDir){ throw 'Codex bin directory did not follow the discovered executable path' }
  if(-not (Codex-SandboxSetupOk -CodexPath $codexPath)){ throw 'sandbox helper beside the discovered Codex executable was not detected' }

  if((Get-ReadinessStatus -RequiredChecks @($true,$true,$true)) -ne 'ready'){ throw 'all required checks should produce ready status' }
  if((Get-ReadinessStatus -RequiredChecks @($true,$false,$true)) -ne 'action_required'){ throw 'one failed required check should block readiness' }

  function Codex-Ok { return $true }
  function Codex-SandboxSetupOk { return $false }
  $script:sandboxRepairCalls = 0
  function Repair-CodexSandboxSetup { $script:sandboxRepairCalls++; return $false }
  if(Codex-Ready){ throw 'Codex without its Windows sandbox helper was reported ready' }
  if($script:sandboxRepairCalls -ne 0){ throw 'read-only Codex readiness attempted to repair the sandbox helper' }

  function Core-PlatformSupported { return $true }
  function Codex-Ready { return $true }
  function Cmd-Usable([string]$Command) { return ($Command -ne 'lark-cli') }
  function Lark-SkillsOk { return $false }
  function Node-Ok { return $false }
  function Test-FeishuDesktopInstalled { return $true }
  function Test-CourseDiskSpace { return $true }
  function Test-CourseWorkspace { return $true }
  function Test-CoursePreworkFiles { return $true }
  function Test-CourseDataPackage { return $true }
  $script:COURSE_NETWORK_OK = $true
  if((Get-CourseReadinessStatus) -ne 'ready'){ throw 'optional Feishu CLI and Node should not block official Shenzhen readiness' }
  function Codex-Ready { return $false }
  if((Get-CourseReadinessStatus) -ne 'action_required'){ throw 'missing Codex sandbox helper did not block Windows readiness' }
  function Codex-Ready { return $true }
  Write-Host 'PASS  Windows course readiness helpers enforce required checks'

  $script:nodeInstallCalls = 0
  function Ask { return $false }
  function Install-Node { $script:nodeInstallCalls++; return $true }
  Do-Larkcli
  if($script:nodeInstallCalls -ne 0){ throw 'skipping optional Feishu CLI installed Node' }
  Write-Host 'PASS  Skipping optional Feishu CLI does not install Node on Windows'
} finally {
  $env:Path = $oldPath
  Remove-Item -LiteralPath $fixtureDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item Env:\INSTALLER_LIB_ONLY -ErrorAction SilentlyContinue
  Remove-Item Env:\VERSION_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
  Remove-Item Env:\COURSE_DATA_MIN_BYTES -ErrorAction SilentlyContinue
}
