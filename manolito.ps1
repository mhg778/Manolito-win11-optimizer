<#
.SYNOPSIS
    Manolito Engine v2.8.0 - Bare-Metal Tweaking & Sysadmin Toolkit (GitHub Release)
.DESCRIPTION
    Motor de ejecución guiado por base de datos (manolito.json) con interfaz interactiva.
.AUTHOR
    Xciter
#>

#Requires -RunAsAdministrator
Add-Type -AssemblyName PresentationFramework

# ========================================================================
# 1. BOOTSTRAP Y CARGA DE DATOS
# ========================================================================
$DOCS_MANOLITO = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Manolito"
$JSON_PATH     = Join-Path $PSScriptRoot "manolito.json"

# Mutex (instancia única)
$_mutex = [System.Threading.Mutex]::new($false, "Global\ManolitoOptimizer")
try { $acquired = $_mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
if(-not $acquired) { Write-Error "Manolito ya está en ejecución"; exit 1 }

# Transcript
if(-not (Test-Path $DOCS_MANOLITO)) { New-Item $DOCS_MANOLITO -ItemType Directory | Out-Null }
try { Start-Transcript -Path (Join-Path $DOCS_MANOLITO "transcript_$(Get-Date -f 'yyyyMMdd_HHmmss').txt") -Append } catch {}

# Cargar y Validar JSON
$script:Config = $null
if(-not (Test-Path $JSON_PATH)) { [System.Windows.MessageBox]::Show("Falta manolito.json", "Error", 0, 16); exit 1 }
$raw = Get-Content $JSON_PATH -Raw -Encoding UTF8
$raw = $raw -replace '(?m)^\s*//.*$', ''
$script:Config = $raw | ConvertFrom-Json

if ($script:Config.Manifest.Version -notmatch '^2\.[78](\.\d+)?$') {
    [System.Windows.MessageBox]::Show('JSON Version incompatible (Se requiere v2.7.x o v2.8.x)','Error',0,16)
    exit 1
}

$script:SystemCaps = [PSCustomObject]@{
    IsVM           = (Get-CimInstance Win32_ComputerSystem).Model -match 'Virtual|VMware|Hyper-V'
    IsDomain       = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
    HasPhysicalNIC = (Get-NetAdapter | Where-Object { !$_.Virtual -and $_.Status -eq 'Up' }).Count -gt 0
    WinBuild       = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
    HasNvidia      = (Get-CimInstance Win32_VideoController -EA SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' }).Count -gt 0
    HasNVMe        = (Get-PhysicalDisk -EA SilentlyContinue | Where-Object { $_.BusType -eq 'NVMe' -or $_.MediaType -eq 'NVMe' }).Count -gt 0
    HasBattery     = (Get-CimInstance Win32_Battery -EA SilentlyContinue).Count -gt 0
	CanUseWinget   = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    IsSafeMode     = ((Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue).BootupState -ne 'Normal boot')
    PendingReboot  = (
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
        ($null -ne (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -EA SilentlyContinue))
    )
    HasPrinter     = (Get-CimInstance Win32_Printer -EA SilentlyContinue | Where-Object { $_.Name -notmatch 'Microsoft|XPS|OneNote|Fax|PDF|Send To' -and $_.WorkOffline -eq $false }).Count -gt 0
    HasOffice      = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Office\16.0') -or (Test-Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0')
    HasOneDrive    = (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe") -or [bool](Get-ItemProperty 'HKCU:\Software\Microsoft\OneDrive' -EA SilentlyContinue)
    HasHAGS        = (& {
        $gpuRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        $maxVram = 0L
        foreach ($k in Get-ChildItem -LiteralPath $gpuRoot -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' }) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -EA SilentlyContinue
            if ($p -and $null -ne $p.PSObject.Properties['HardwareInformation.MemorySize']) {
                $v = [long]$p.'HardwareInformation.MemorySize'
                if ($v -gt $maxVram) { $maxVram = $v }
            }
        }
        $maxVram -ge 8GB
    })
}

$script:ctx = [PSCustomObject]@{
    Runtime  = [PSCustomObject]@{ IsDryRun = $true; IsRollback = $false; IsManifestRestore = $false; Runlevel = $null }
    Options  = [PSCustomObject]@{ Skip = @(); Verify = $false }
    State    = [PSCustomObject]@{ PendingReboot = $false; StepsOk = 0; StepsFail = 0 }
    Tracking = [PSCustomObject]@{ RegDiff = @(); PayloadsExecuted = @(); IrreversibleActions = @() }
    Backups  = [PSCustomObject]@{ 
        ServicesStartup = @{}
        TasksState      = @{}
        DNS             = @{}
        Hosts           = $null
        ActiveSetup     = @{}
        BCD             = @{}
        WindowsFeatures = @{}
    }
    Results  = [PSCustomObject]@{ Modules = @() }
}

$script:MemoriaPayloads = @{}
$script:logQueue    = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$script:rsHandle    = $null
$script:rsStateJson = $null

# ========================================================================
# 2. MOTOR DE AUDIO Y HELPERS
# ========================================================================
function global:Beep-UI($tipo) {
    try {
        switch ($tipo) {
            "boot"   { [Console]::Beep(800, 30); [Console]::Beep(1200, 50) }
            "action" { [Console]::Beep(1000, 20); [Console]::Beep(1500, 40) }
            "check"  { [Console]::Beep(1200, 15) }
            "close"  { [Console]::Beep(1000, 30); [Console]::Beep(700, 50) }
        }
    } catch {}
}

function Test-AVInterference {
    $edrProcs    = @(Get-Process csagent, falconctl, carbonblack, SentinelAgent, cb -EA SilentlyContinue)
    $edrServices = @(Get-Service CSFalconService, CarbonBlack, SentinelAgent -EA SilentlyContinue | Where-Object { $_.Status -eq 'Running' })
    return ($edrProcs.Count -gt 0 -or $edrServices.Count -gt 0)
}

function Resolve-DnsBackup {
    param($Backup)
    if ($null -eq $Backup) { return 'DHCP' }
    $arr = @($Backup | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })
    if ($arr.Count -eq 0)                               { return 'DHCP' }
    if ($arr.Count -eq 1 -and $arr[0] -eq 'DHCP')      { return 'DHCP' }
    return $arr
}

function Invoke-ExternalCommand {
    param(
        [string]$Command,
        [int]$TimeoutSec  = 30,
        [int]$MaxRetries  = 2
    )
    $parts = $Command -split '\s+', 2
    $exe   = $parts[0]
    $args  = if ($parts.Count -gt 1) { $parts[1] } else { '' }

    for ($i = 0; $i -le $MaxRetries; $i++) {
        $stdoutFile = [System.IO.Path]::GetTempFileName()
        $stderrFile = [System.IO.Path]::GetTempFileName()
        try {
            $psi                        = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName               = $exe
            $psi.Arguments              = $args
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.UseShellExecute        = $false
            $psi.CreateNoWindow         = $true

            $proc = [System.Diagnostics.Process]::Start($psi)
            $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
            $stderrTask = $proc.StandardError.ReadToEndAsync()
            $completed = $proc.WaitForExit($TimeoutSec * 1000)

            $stdout = $stdoutTask.Result
            $stderr = $stderrTask.Result

            if (-not $completed) {
                try { $proc.Kill() } catch {}
                if ($i -lt $MaxRetries) { continue }
                return @{ Success = $false; Stdout = $stdout; Stderr = $stderr; ExitCode = -1; Error = "Timeout tras $($TimeoutSec)s" }
            }

            $exitCode = $proc.ExitCode
            return @{
                Success  = ($exitCode -eq 0)
                Stdout   = $stdout
                Stderr   = $stderr
                ExitCode = $exitCode
                Error    = if ($exitCode -ne 0) { "ExitCode $exitCode — $stderr" } else { $null }
            }
        } catch {
            if ($i -lt $MaxRetries) { continue }
            return @{ Success = $false; Stdout = ''; Stderr = $_.Exception.Message; ExitCode = -1; Error = "Excepción: $($_.Exception.Message)" }
        } finally {
            Remove-Item $stdoutFile, $stderrFile -EA SilentlyContinue
        }
    }
    return @{ Success = $false; Error = "Reintentos agotados"; ExitCode = -1 }
}

function Set-ManolitoReg {
    param([string]$Path, [string]$Name, $Value, [string]$Type="DWord")
    $Type = switch ($Type.ToLower()) {
        'dword'       { 'DWord'       }
        'qword'       { 'QWord'       }
        'string'      { 'String'      }
        'expandstring'{ 'ExpandString' }
        'binary'      { 'Binary'      }
        'multistring' { 'MultiString'  }
        default       { $Type }
    }
    $before = try { (Get-ItemProperty $Path -Name $Name -EA Stop).$Name } catch { $null }
    if ($null -ne $before -and $before -is [string]) { $before = $before.ToString() }
    if($script:ctx.Runtime.IsDryRun) { return @{ Success=$true; Changes=1; DryRun=$true; Msg="[DRY] $Name -> $Value" } }
    if ($null -ne $before -and "$before" -eq "$Value") { return @{ Success=$true; Changes=0; Msg="    [SKIP] $Name (sin cambio)" } }
    try {
        if(!(Test-Path $Path)) { New-Item $Path -Force | Out-Null }
        Set-ItemProperty $Path -Name $Name -Value $Value -Type $Type -Force -EA Stop
        $after = (Get-ItemProperty $Path -Name $Name -EA SilentlyContinue).$Name
        if ($null -ne $after -and $after -is [string]) { $after = $after.ToString() }
        $script:ctx.Tracking.RegDiff += [PSCustomObject]@{ Path=$Path; Name=$Name; Type=$Type; Before=$before; After=$after }
        return @{ Success=$true; Changes=1; Msg="[OK] $Name" }
    } catch {
        return @{ Success=$false; Changes=0; Msg="[FAIL] $($Name): $($_.Exception.Message)" }
    }
}

function Restore-ManolitoReg {
    param([string]$Path, [string]$Name, $Before, [string]$Type="DWord")
    if ($null -eq $Before) {
        if ($script:ctx.Runtime.IsDryRun) { return @{ Success=$true; Changes=1; Msg="[DRY] $Name -> (eliminar)" } }
        if (Test-Path $Path) {
            try { 
                Remove-ItemProperty -Path $Path -Name $Name -EA Stop
                return @{ Success=$true; Changes=1; Msg="[OK] $Name eliminado (restaurando original)" } 
            } catch { return @{ Success=$false; Changes=0; Msg="[FAIL] Eliminar $($Name): $($_.Exception.Message)" } }
        }
        return @{ Success=$true; Changes=0; Msg="    [SKIP] $Name (no existia)" }
    } else {
        return Set-ManolitoReg -Path $Path -Name $Name -Value $Before -Type $Type
    }
}

# ========================================================================
# 3. MODULOS PAYLOAD (BACKEND)
# ========================================================================
function Invoke-PayloadWindowsFeatures {
    param([array]$Features)
    $r = @{ Success = $true; Changes = 0; Logs = @() }
    if ($script:SystemCaps.IsVM) { $r.Logs += "    [SKIP] WindowsFeatures — VM detectada"; return $r }
    foreach ($feat in $Features) {
        $current = Get-WindowsOptionalFeature -Online -FeatureName $feat.Name -EA SilentlyContinue
        if ($null -eq $current) { $r.Logs += "    [SKIP] $($feat.Name) — no disponible en este sistema"; continue }

        if (-not $script:ctx.Backups.WindowsFeatures.ContainsKey($feat.Name)) {
            $script:ctx.Backups.WindowsFeatures[$feat.Name] = $current.State.ToString()
        }

        if ($script:ctx.Runtime.IsManifestRestore) {
            $action = if ($script:ctx.Backups.WindowsFeatures.ContainsKey($feat.Name)) {
                if ($script:ctx.Backups.WindowsFeatures[$feat.Name] -eq 'Enabled') { 'Enable' } else { 'Disable' }
            } else { $feat.RestoreState }
        } else {
            $action = if ($script:ctx.Runtime.IsRollback) { $feat.RestoreState } else { $feat.TargetState }
        }

        if ($script:ctx.Runtime.IsDryRun) { $r.Changes++; $r.Logs += "    [DRY] DISM Feature $($feat.Name) -> $action"; continue }

        try {
            if ($action -eq 'Enable' -and $current.State -ne 'Enabled') {
                Enable-WindowsOptionalFeature -Online -FeatureName $feat.Name -All -NoRestart -EA Stop | Out-Null
                $post = Get-WindowsOptionalFeature -Online -FeatureName $feat.Name -EA SilentlyContinue
                if ($post.State -eq 'Enabled') {
                    $r.Changes++; $r.Logs += "    [OK]  $($feat.Name) habilitado"
                    $script:ctx.State.PendingReboot = $true
                } else { $r.Logs += "    [WARN] $($feat.Name) — estado post: $($post.State)" }
            } elseif ($action -eq 'Disable' -and $current.State -eq 'Enabled') {
                Disable-WindowsOptionalFeature -Online -FeatureName $feat.Name -NoRestart -EA Stop | Out-Null
                $post = Get-WindowsOptionalFeature -Online -FeatureName $feat.Name -EA SilentlyContinue
                if ($post.State -ne 'Enabled') {
                    $r.Changes++; $r.Logs += "    [OK]  $($feat.Name) deshabilitado (estado: $($post.State))"
                    $script:ctx.State.PendingReboot = $true
                } else { $r.Logs += "    [WARN] $($feat.Name) — estado post: $($post.State)" }
            } else {
                $r.Logs += "    [SKIP] $($feat.Name) — ya en estado correcto ($($current.State))"
            }
        } catch { $r.Success = $false; $r.Logs += "    [FAIL] $($feat.Name): $($_.Exception.Message)" }
    }
    return $r
}

function Invoke-PayloadCleanup {
    param([bool]$IncludeDism = $false)
    $r = @{ Success = $true; Changes = 0; Logs = @() }
    
    if ($script:ctx.Runtime.IsRollback -or $script:ctx.Runtime.IsManifestRestore) {
        $r.Logs += "    [SKIP] Cleanup — no aplica en Rollback/ManifestRestore"
        return $r
    }

    if (-not $IncludeDism) {
        if (-not $script:ctx.Runtime.IsDryRun) {
            foreach ($tp in @($env:TEMP, $env:TMP, "$env:SystemRoot\Temp")) {
                if (-not (Test-Path $tp)) { continue }
                $removed = 0
                Get-ChildItem -Path $tp -Recurse -Force -EA SilentlyContinue |
                    Where-Object { -not $_.PSIsContainer } |
                    ForEach-Object { try { Remove-Item $_.FullName -Force -EA Stop; $removed++ } catch {} }
                $r.Changes += $removed
                $r.Logs += "    [OK]  Temp $tp — $removed archivos eliminados"
            }
        } else {
            $r.Changes = 1; $r.Logs += "    [DRY] Limpieza de %TEMP%, %TMP%, C:\WINDOWS\Temp"
        }
    } else {
        # Guard de PendingReboot va ANTES del DryRun (Aporte del Prof. Claudio)
        if ($script:ctx.State.PendingReboot) {
            $r.Logs += "    [WARN] DISM /ResetBase omitido — reinicio pendiente (puede fallar con 0x800F0A82)"
            return $r
        }
        
        if ($script:ctx.Runtime.IsDryRun) { 
            $r.Changes++
            $r.Logs += "    [DRY] DISM /StartComponentCleanup /ResetBase"
            return $r 
        }
        
        $res = Invoke-ExternalCommand -Command "dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase" -TimeoutSec 300
        if ($res.Success) {
            $r.Changes++; $r.Logs += "    [OK]  DISM /ResetBase completado"
            $script:ctx.Tracking.IrreversibleActions += "DismResetBase"
        } else {
            $r.Logs += "    [WARN] DISM /ResetBase — ExitCode: $($res.ExitCode)"
            if ($res.Stderr) { $r.Logs += "    [STDERR] $($res.Stderr)" }
        }
    }
    return $r
}

function Invoke-PayloadAppx($packages) {
    $r = @{ Success=$true; Changes=0; Logs=@() }
    foreach($pkg in $packages) {
        if($script:ctx.Runtime.IsDryRun) { $r.Changes++; $r.Logs += "    [DRY] Remove-Appx: $($pkg.FriendlyName)"; continue }
        try {
            $before         = @(Get-AppxPackage -Name $pkg.Pattern -AllUsers -EA SilentlyContinue).Count
            $wasProvisioned = $false
            if ($pkg.Pattern -like '*XboxIdentityProvider*') {
                try {
                    Get-AppxPackage -Name $pkg.Pattern -AllUsers -EA SilentlyContinue | Remove-AppxPackage -AllUsers -EA SilentlyContinue
                    $provPkg = Get-AppxProvisionedPackage -Online -EA SilentlyContinue | Where-Object { $_.DisplayName -like $pkg.Pattern }
                    if ($provPkg) {
                        Remove-AppxProvisionedPackage -Online -PackageName $provPkg.PackageName -EA SilentlyContinue | Out-Null
                        $wasProvisioned = $true
                    }
                } catch {
                    $r.Logs += "    [WARN] XboxIdentityProvider: error no crítico — $($_.Exception.Message)"
                    continue
                }
            } else {
                Get-AppxPackage -Name $pkg.Pattern -AllUsers -EA SilentlyContinue | Remove-AppxPackage -AllUsers -EA SilentlyContinue
                $provPkg = Get-AppxProvisionedPackage -Online -EA SilentlyContinue | Where-Object { $_.DisplayName -like $pkg.Pattern }
                if ($provPkg) {
                    Remove-AppxProvisionedPackage -Online -PackageName $provPkg.PackageName -EA SilentlyContinue | Out-Null
                    $wasProvisioned = $true
                }
            }
            $after = @(Get-AppxPackage -Name $pkg.Pattern -AllUsers -EA SilentlyContinue).Count
            if ($before -gt $after) {
                $r.Changes++; $r.Logs += "    [OK] Purgado (activo): $($pkg.FriendlyName)"
            } elseif ($wasProvisioned) {
                $r.Changes++; $r.Logs += "    [OK] Desaprovisionado: $($pkg.FriendlyName)"
            } else {
                $r.Logs += "    [SKIP] $($pkg.FriendlyName): no estaba instalado ni provisionado"
            }
        } catch {
            $r.Success = $false
            $r.Logs   += "    [FAIL] Error purgado: $($pkg.FriendlyName) — $($_.Exception.Message)"
        }
    }
    return $r
}

function Invoke-PayloadServices($services) {
    $r = @{ Success=$true; Changes=0; Logs=@() }
    foreach($svc in $services) {
        if ($script:ctx.Runtime.IsManifestRestore) {
            $state = if ($script:ctx.Backups.ServicesStartup.ContainsKey($svc.Name)) { $script:ctx.Backups.ServicesStartup[$svc.Name] } else { $svc.RestoreState }
        } else {
            $state = if ($script:ctx.Runtime.IsRollback) { $svc.RestoreState } else { $svc.TargetState }
        }
        if($script:ctx.Runtime.IsDryRun) { $r.Changes++; $r.Logs += "    [DRY] Servicio $($svc.Name) -> $state"; continue }
        
        $current = Get-Service $svc.Name -EA SilentlyContinue
        if(-not $current) { $r.Logs += "    [SKIP] $($svc.Name) no existe"; continue }
        if(-not $script:ctx.Backups.ServicesStartup.ContainsKey($svc.Name)) { $script:ctx.Backups.ServicesStartup[$svc.Name] = $current.StartType.ToString() }
        
        Set-Service $svc.Name -StartupType $state -EA SilentlyContinue
        if     ($state -eq 'Disabled')  { Stop-Service  $svc.Name -Force -EA SilentlyContinue }
        elseif ($state -eq 'Automatic') { Start-Service $svc.Name        -EA SilentlyContinue }
        
        $r.Changes++
        
        $post           = Get-Service $svc.Name -EA SilentlyContinue
        $expectedStatus = switch ($state) { 'Disabled' { 'Stopped' } 'Automatic' { 'Running' } default { $null } }
        
        if ($expectedStatus -and $post -and $post.Status -ne $expectedStatus) {
            $r.Logs += "    [WARN] $($svc.Name) modificado a $state pero status=$($post.Status)"
        } else {
            $r.Logs += "    [OK]  Servicio $($svc.Name) → $state"
        }
    }
    return $r
}

function Invoke-PayloadTasks($tasks) {
    $r = @{ Success=$true; Changes=0; Logs=@() }
    foreach($task in $tasks) {
        if ($script:ctx.Runtime.IsManifestRestore) {
            $taskKey = "$($task.Path)|$($task.Name)"
            $saved   = $script:ctx.Backups.TasksState[$taskKey]
            $state   = if ($saved) { if ($saved -eq 'Disabled') { 'Disable' } else { 'Enable' } } else { $task.RestoreState }
        } else {
            $state = if ($script:ctx.Runtime.IsRollback) { $task.RestoreState } else { $task.TargetState }
        }
        if ($task.MinBuild -and $script:SystemCaps.WinBuild -lt [int]$task.MinBuild) {
            $r.Logs += "    [SKIP] $($task.Name) — requiere build $($task.MinBuild), actual $($script:SystemCaps.WinBuild)"; continue
        }
        if ($script:ctx.Runtime.IsDryRun) {
            $r.Changes++; $r.Logs += "    [DRY] Tarea $($task.Name) -> $state"; continue
        }
        if ([string]::IsNullOrWhiteSpace($task.Path) -or $task.Path -eq '\') {
            $schTask = Get-ScheduledTask -TaskName $task.Name -EA SilentlyContinue | Select-Object -First 1
        } else {
            $schTask = Get-ScheduledTask -TaskPath $task.Path -TaskName $task.Name -EA SilentlyContinue
        }
        if(-not $schTask) { $r.Logs += "    [SKIP] $($task.Name) no existe"; continue }
        
        $taskKey = "$($task.Path)|$($task.Name)"
        if (-not $script:ctx.Backups.TasksState.ContainsKey($taskKey)) { $script:ctx.Backups.TasksState[$taskKey] = $schTask.State.ToString() }
        
        if($state -eq "Disable") { $schTask | Disable-ScheduledTask -EA SilentlyContinue | Out-Null } else { $schTask | Enable-ScheduledTask -EA SilentlyContinue | Out-Null }
        $r.Changes++; $r.Logs += "    [OK] Tarea $($task.Name) -> $state"
    }
    return $r
}

function Invoke-PayloadRegistry($registry) {
    $r = @{ Success=$true; Changes=0; Logs=@() }
    foreach($reg in $registry) {
        if ($script:ctx.Runtime.IsManifestRestore) {
            $diff = $script:ctx.Tracking.RegDiff | Where-Object { $_.Path -eq $reg.Path -and $_.Name -eq $reg.Name } | Select-Object -First 1
            if ($diff) { $res = Restore-ManolitoReg -Path $reg.Path -Name $reg.Name -Before $diff.Before -Type $reg.Type }
            else       { $res = Set-ManolitoReg -Path $reg.Path -Name $reg.Name -Value $reg.RestoreValue -Type $reg.Type }
        } else {
            $val = if ($script:ctx.Runtime.IsRollback) { $reg.RestoreValue } else { $reg.TargetValue }
            $res = Set-ManolitoReg -Path $reg.Path -Name $reg.Name -Value $val -Type $reg.Type
        }
        $r.Changes += $res.Changes; $r.Logs += $res.Msg; if(-not $res.Success){$r.Success=$false}
    }
    return $r
}

function Invoke-PayloadRegistryKeys {
    param([array]$Keys)
    $r = @{ Success = $true; Changes = 0; Logs = @() }
    foreach ($key in $Keys) {
        $action = if ($script:ctx.Runtime.IsRollback -or $script:ctx.Runtime.IsManifestRestore) { $key.RestoreAction } else { $key.Action }
        if ($script:ctx.Runtime.IsDryRun) {
            $r.Changes++; $r.Logs += "    [DRY] RegistryKey $action : $($key.Path)"; continue
        }
        switch ($action) {
            'Create' {
                try {
                    if (-not (Test-Path $key.Path)) {
                        New-Item $key.Path -Force -EA Stop | Out-Null
                        $r.Changes++; $r.Logs += "    [OK]  Clave creada: $($key.Path)"
                    } else { $r.Logs += "    [SKIP] Clave ya existe: $($key.Path)" }
                } catch { $r.Success = $false; $r.Logs += "    [FAIL] Crear clave: $($_.Exception.Message)" }
            }
            'Delete' {
                try {
                    if (Test-Path $key.Path) {
                        Remove-Item $key.Path -Recurse -Force -EA Stop
                        $r.Changes++; $r.Logs += "    [OK]  Clave eliminada: $($key.Path)"
                    } else { $r.Logs += "    [SKIP] Clave no existe: $($key.Path)" }
                } catch { $r.Success = $false; $r.Logs += "    [FAIL] Eliminar clave: $($_.Exception.Message)" }
            }
            default { $r.Logs += "    [WARN] Acción desconocida en RegistryKeys: $action" }
        }
    }
    return $r
}

function Invoke-PayloadNagle($template) {
    $r = @{ Success=$true; Changes=0; Logs=@() }
    $adapters = @(Get-NetAdapter | Where-Object { !$_.Virtual -and $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'TAP|Tunnel|VPN|WireGuard|Loopback|Hyper-V|vEthernet' })
    if($adapters.Count -eq 0) { $r.Logs += "    [SKIP] Sin NIC fisica activa"; return $r }
    $ifaceRoot = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    foreach($adapter in $adapters) {
        $nicIPs = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -EA SilentlyContinue | Where-Object { $_.IPAddress -ne "0.0.0.0" } | Select-Object -ExpandProperty IPAddress)
        if($nicIPs.Count -eq 0) { continue }
        foreach($guid in @(Get-ChildItem $ifaceRoot -EA SilentlyContinue)) {
            $props = Get-ItemProperty $guid.PSPath -EA SilentlyContinue
            $allIPs = @($props.DhcpIPAddress) + @($props.IPAddress) | Where-Object { $_ -and $_ -ne "0.0.0.0" }
            if($allIPs | Where-Object { $_ -in $nicIPs }) {
                foreach($entry in $template) {
                    if ($script:ctx.Runtime.IsManifestRestore) {
                        $diff = $script:ctx.Tracking.RegDiff | Where-Object { $_.Name -eq $entry.Name -and $_.Path -like "*$($guid.PSChildName)*" } | Select-Object -First 1
                        if ($diff) { $res = Restore-ManolitoReg -Path $guid.PSPath -Name $entry.Name -Before $diff.Before -Type $entry.Type }
                        else       { $res = Restore-ManolitoReg -Path $guid.PSPath -Name $entry.Name -Before $null -Type $entry.Type }
                    } else {
                        $val = if($script:ctx.Runtime.IsRollback){ $entry.RestoreValue } else { $entry.TargetValue }
                        $res = Set-ManolitoReg -Path $guid.PSPath -Name $entry.Name -Value $val -Type $entry.Type
                    }
                    $r.Changes += $res.Changes; $r.Logs += $res.Msg
                }
                break
            }
        }
    }
    return $r
}

function Invoke-PayloadDNS($dns) {
    $r = @{ Success=$true; Changes=0; Logs=@() }
    $adapters = @(Get-NetAdapter | Where-Object { !$_.Virtual -and $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'TAP|Tunnel|VPN|WireGuard|Loopback|Hyper-V|vEthernet' })
    foreach($adapter in $adapters) {
        if($script:ctx.Runtime.IsDryRun) { $r.Changes++; $r.Logs += "    [DRY] DNS $($adapter.Name) -> $($dns.Primary.TargetValue)"; continue }
        try {
            if(-not $script:ctx.Backups.DNS.ContainsKey($adapter.Name)) {
                $currentDNS = (Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -EA SilentlyContinue).ServerAddresses
                $script:ctx.Backups.DNS[$adapter.Name] = if($currentDNS){ @($currentDNS | ForEach-Object { "$_" }) } else { @("DHCP") }
            }
            if ($script:ctx.Runtime.IsManifestRestore -or $script:ctx.Runtime.IsRollback) {
                $resolved = Resolve-DnsBackup $script:ctx.Backups.DNS[$adapter.Name]
                if ($resolved -eq 'DHCP') {
                    Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses -EA Stop
                } else {
                    Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $resolved -EA Stop
                }
            } else {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dns.Primary.TargetValue,$dns.Secondary.TargetValue -EA Stop
            }
            $r.Changes++; $r.Logs += "    [OK] DNS $($adapter.Name) configurado"
        } catch { $r.Success=$false; $r.Logs += "    [FAIL] DNS $($adapter.Name): $($_.Exception.Message)" }
    }
    return $r
}

function Invoke-PayloadBCD($bcd) {
    $r = @{ Success=$true; Changes=0; Logs=@() }
    foreach ($entry in $bcd) {
        if ($script:ctx.Runtime.IsManifestRestore) {
            $val = if ($script:ctx.Backups.BCD.ContainsKey($entry.Setting)) { $script:ctx.Backups.BCD[$entry.Setting] } else { $entry.RestoreValue }
        } else {
            $val = if ($script:ctx.Runtime.IsRollback) { $entry.RestoreValue } else { $entry.TargetValue }
        }
        if ($script:ctx.Runtime.IsDryRun) { $r.Changes++; $r.Logs += "    [DRY] bcdedit /set $($entry.Setting) $val"; continue }
        if (-not $script:ctx.Runtime.IsRollback -and -not $script:ctx.Backups.BCD.ContainsKey($entry.Setting)) {
            $bcdEnum = Invoke-ExternalCommand -Command "bcdedit /enum `{current`}" -TimeoutSec 10
            $bcdBefore = if ($bcdEnum.Success -and $bcdEnum.Stdout) {
                $bcdEnum.Stdout | Select-String $entry.Setting
            } else { $null }
            $script:ctx.Backups.BCD[$entry.Setting] = if ($bcdBefore) {
                ($bcdBefore.Line -split '\s+', 2)[1].Trim()
            } else { $entry.RestoreValue }
        }
        $cmd = "bcdedit /set $($entry.Setting) $val"
        $res = Invoke-ExternalCommand -Command $cmd -TimeoutSec 15
        if ($res.Success) {
            $r.Changes++; $r.Logs += "    [OK] BCD $($entry.Setting) -> $val"
        } else {
            $r.Success = $false
            $r.Logs   += "    [FAIL] BCD $($entry.Setting) — ExitCode: $($res.ExitCode)"
            if ($res.Stderr) { $r.Logs += "    [STDERR] $($res.Stderr)" }
            if ($res.Error -and $res.Error -like "Timeout*") { $r.Logs += "    [FAIL] Timeout esperando bcdedit" }
        }
    }
    return $r
}

function Invoke-PayloadMSITuning($payload) {
    $r = @{ Success=$true; Changes=0; Logs=@() }
    foreach($class in $payload.DeviceClasses) {
        $devices = Get-CimInstance Win32_PnPEntity -EA SilentlyContinue | Where-Object {
            $_.Status -eq "OK" -and $_.DeviceID -like "PCI*" -and (
                ($class -eq "Display" -and $_.PNPClass -eq "Display") -or
                ($class -eq "NVMe"    -and $_.Name -match "NVM|NVMe|Non-Volatile")
            )
        }
        foreach($dev in $devices) {
            $msiPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.DeviceID)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            $r.Logs += "    [MSI] Dispositivo: $($dev.Name)"
            foreach($reg in $payload.RegistryTemplate) {
                $val = if($script:ctx.Runtime.IsRollback -or $script:ctx.Runtime.IsManifestRestore){ $reg.RestoreValue } else { $reg.TargetValue }
                $res = Set-ManolitoReg -Path $msiPath -Name $reg.Name -Value $val -Type $reg.Type
                $r.Changes += $res.Changes; $r.Logs += $res.Msg
            }
        }
        if(-not $devices) { $r.Logs += "    [SKIP] MSI: ningún dispositivo $class encontrado" }
    }
    return $r
}

function Invoke-PayloadActiveSetup {
    param([array]$Entries)
    $r        = @{ Success = $true; Changes = 0; Logs = @() }
    $basePath = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components'
    foreach ($guid in $Entries) {
        $keyPath = Join-Path $basePath $guid
        if ($script:ctx.Runtime.IsDryRun) {
            $r.Logs += "    [DRY] ActiveSetup: Remove $guid"; $r.Changes++; continue
        }
        if ($script:ctx.Runtime.IsRollback) {
            $backup = $script:ctx.Backups.ActiveSetup[$guid]
            if (-not $backup) { $r.Logs += "    [SKIP] ActiveSetup $guid — sin backup de sesión"; continue }
            try {
                New-Item $keyPath -Force -EA Stop | Out-Null
                foreach ($val in $backup) { Set-ItemProperty $keyPath -Name $val.Name -Value $val.Value -Type $val.Type -Force -EA Stop }
                $r.Logs += "    [OK]  ActiveSetup restaurado: $guid"; $r.Changes++
            } catch { $r.Logs += "    [FAIL] ActiveSetup restore $($guid): $($_.Exception.Message)"; $r.Success = $false }
            continue
        }
        if (Test-Path $keyPath) {
            try {
                $props  = Get-Item $keyPath -EA Stop
                $backup = @()
                foreach ($v in $props.GetValueNames()) {
                    $val = $props.GetValue($v)
                    if ($null -ne $val -and $val -is [string]) { $val = $val.ToString() }
                    $backup += @{ Name = "$v"; Value = $val; Type = "" + $props.GetValueKind($v).ToString() }
                }
                $script:ctx.Backups.ActiveSetup[$guid] = $backup
                Remove-Item $keyPath -Recurse -Force -EA Stop
                $r.Logs += "    [OK]  ActiveSetup eliminado: $guid"; $r.Changes++
            } catch { $r.Logs += "    [FAIL] ActiveSetup $($guid): $($_.Exception.Message)"; $r.Success = $false }
        } else { $r.Logs += "    [SKIP] ActiveSetup $guid — no existe en este sistema" }
    }
    return $r
}

function Invoke-PayloadHosts {
    param([array]$Domains)
    $r         = @{ Success = $true; Changes = 0; Logs = @() }
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $header    = "# === Manolito Engine $($script:Config.Manifest.Version) — Telemetry Block ==="
    $footer    = '# === END Manolito Block ==='
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    if ($script:ctx.Runtime.IsDryRun) {
        foreach ($d in $Domains) { $r.Logs += "    [DRY] HOSTS: 0.0.0.0 $d" }
        $r.Changes = $Domains.Count
        return $r
    }
    try {
        if (-not $script:ctx.Backups.Hosts) {
            $script:ctx.Backups.Hosts = [System.IO.File]::ReadAllText($hostsPath, $utf8NoBom)
            $r.Logs += "    [OK]  HOSTS backup almacenado en memoria"
        }
        if ($script:ctx.Runtime.IsRollback -or $script:ctx.Runtime.IsManifestRestore) {
            if (-not $script:ctx.Backups.Hosts) {
                $r.Logs += "    [SKIP] HOSTS Rollback — sin backup en sesión."
                return $r
            }
            [System.IO.File]::WriteAllText($hostsPath, $script:ctx.Backups.Hosts, $utf8NoBom)
            $r.Logs += "    [OK]  HOSTS restaurado desde backup de sesión"
            $r.Changes = 1
        } else {
            $current = [System.IO.File]::ReadAllText($hostsPath, $utf8NoBom)
            $current = $current -replace "(?s)$([regex]::Escape($header)).*?$([regex]::Escape($footer))\r?\n?", ''
            $block  = "`r`n$header`r`n"
            foreach ($d in $Domains) { $block += "0.0.0.0 $d`r`n" }
            $block += "$footer`r`n"
            [System.IO.File]::WriteAllText($hostsPath, ($current.TrimEnd() + $block), $utf8NoBom)
            $r.Changes  = $Domains.Count
            $r.Logs    += "    [OK]  HOSTS: $($Domains.Count) dominios → 0.0.0.0"
        }
    } catch { $r.Success = $false; $r.Logs += "    [FAIL] HOSTS: $($_.Exception.Message)" }
    return $r
}

function Invoke-PayloadDeKMS($payload) {
    $r = @{ Success=$true; Changes=0; Logs=@() }
    $kmsServer = $null
    try { $kmsServer = (Get-CimInstance SoftwareLicensingService -EA SilentlyContinue).KeyManagementServiceMachine } catch {}
    
    if ($kmsServer) {
        $r.Logs += "    [INFO] KMS Server activo: $kmsServer"
        $isBlacklisted = $false
        foreach ($entry in $payload.Blacklist) {
            if ($kmsServer -match $entry) { $isBlacklisted = $true; break }
        }
        if (-not $isBlacklisted) {
            $r.Logs += "    [SKIP] DeKMS — KMS no está en blacklist (posible activación corporativa legítima)"
            return $r
        }
        $r.Logs += "    [WARN] KMS irregular detectado: $kmsServer — procediendo a limpieza"
    } else {
        $r.Logs += "    [INFO] Sin KMS server activo — limpieza preventiva de restos"
    }
    
    if ($script:ctx.Runtime.IsDryRun) {
        $r.Logs += "    [DRY] slmgr /ckms"
        foreach ($svc  in $payload.Services) { $r.Logs += "    [DRY] Eliminar servicio KMS: $svc";  $r.Changes++ }
        foreach ($file in $payload.Files)    { $r.Logs += "    [DRY] Eliminar archivo KMS: $file"; $r.Changes++ }
        foreach ($task in $payload.Tasks)    { $r.Logs += "    [DRY] Eliminar tarea KMS: $task";   $r.Changes++ }
        return $r
    }
    
    try {
        $res = Invoke-ExternalCommand -Command "cscript //nologo `"$env:SystemRoot\System32\slmgr.vbs`" /ckms" -TimeoutSec 30
        if ($res.Success) { $r.Logs += "    [OK]  slmgr /ckms ejecutado" }
        else              { 
            $r.Logs += "    [WARN] slmgr /ckms — ExitCode: $($res.ExitCode)"
            if ($res.Stderr) { $r.Logs += "    [STDERR] $($res.Stderr)" }
        }
        
        $sppPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
        if (Test-Path $sppPath) {
            Remove-ItemProperty -Path $sppPath -Name 'KeyManagementServiceName' -EA SilentlyContinue
            Remove-ItemProperty -Path $sppPath -Name 'KeyManagementServicePort' -EA SilentlyContinue
            $r.Logs += "    [OK]  Registro SPP KMS limpiado"; $r.Changes++
        }

        foreach ($svc in $payload.Services) {
            if (Get-Service $svc -EA SilentlyContinue) {
                Stop-Service $svc -Force -EA SilentlyContinue
                sc.exe delete $svc 2>$null
                $r.Logs += "    [OK]  Servicio $svc purgado"; $r.Changes++
            } else { $r.Logs += "    [SKIP] Servicio $svc no encontrado" }
        }
        foreach ($file in $payload.Files) {
            $p = [Environment]::ExpandEnvironmentVariables($file)
            if (Test-Path $p) { Remove-Item $p -Force -EA SilentlyContinue; $r.Logs += "    [OK]  Archivo $file purgado"; $r.Changes++ }
        }
        foreach ($task in $payload.Tasks) {
            $schTask = Get-ScheduledTask -TaskName $task -EA SilentlyContinue
            if ($schTask) {
                $schTask | Unregister-ScheduledTask -Confirm:$false -EA SilentlyContinue
                $r.Logs += "    [OK]  Tarea $task purgada"; $r.Changes++
            } else { $r.Logs += "    [SKIP] Tarea $task no encontrada" }
        }
    } catch {
        $r.Success = $false
        $r.Logs += "    [FAIL] Error en limpieza KMS: $($_.Exception.Message)"
    }
    return $r
}

function Invoke-PayloadWinget {
    param([array]$Packages)
    $r = @{ Success = $true; Changes = 0; Logs = @() }
    if (-not $script:SystemCaps.CanUseWinget) { $r.Logs += "    [SKIP] Winget no disponible"; return $r }
    foreach ($pkg in $Packages) {
        $id = $pkg.Id; $friendlyName = $pkg.FriendlyName; $action = if ($pkg.Action) { $pkg.Action } else { 'install' }
        if ($script:ctx.Runtime.IsDryRun) { $r.Changes++; $r.Logs += "    [DRY] winget $action $id ($friendlyName)"; continue }
        if ($action -eq 'install') {
            $checkCmd = "winget list --id `"$id`" --accept-source-agreements --disable-interactivity"
            $checkRes = Invoke-ExternalCommand -Command $checkCmd -TimeoutSec 20 -MaxRetries 0
            if ($checkRes.Success -and $checkRes.Stdout -match [regex]::Escape($id)) {
                $r.Logs += "    [SKIP] $friendlyName ya instalado (idempotencia)"; continue
            }
        }
        $cmd = switch ($action) {
            'install'   { "winget install --id `"$id`" --silent --accept-package-agreements --accept-source-agreements --disable-interactivity" }
            'uninstall' { "winget uninstall --id `"$id`" --silent --accept-source-agreements --disable-interactivity" }
            default     { $r.Logs += "    [WARN] $friendlyName — acción desconocida: $action"; continue }
        }
        $res = Invoke-ExternalCommand -Command $cmd -TimeoutSec 120 -MaxRetries 1
        if ($res.Success) {
            $r.Changes++; $r.Logs += "    [OK]  $friendlyName — winget $action completado"
        } else {
            $r.Logs += "    [WARN] $friendlyName — ExitCode: $($res.ExitCode)"
            if ($res.Stderr) { $r.Logs += "    [STDERR] $($res.Stderr)" }
            if ($res.ExitCode -eq -1946335999) { $r.Logs += "    [INFO] $friendlyName — ya instalado según winget"; $r.Changes++ }
        }
    }
    return $r
}

function Invoke-PayloadOneDrive {
    param([object]$Payload)
    $r = @{ Success = $true; Changes = 0; Logs = @() }
    if (-not $script:SystemCaps.HasOneDrive) { $r.Logs += "    [SKIP] OneDrive no detectado en este sistema"; return $r }
    if ($script:ctx.Runtime.IsDryRun) { $r.Logs += "    [DRY] OneDrive purge"; $r.Changes = 1; return $r }
    try {
        $proc = Get-Process OneDrive -EA SilentlyContinue
        if ($proc) { $proc | Stop-Process -Force -EA SilentlyContinue; Start-Sleep -Milliseconds 800; $r.Logs += "    [OK]  Proceso detenido" }
    } catch { $r.Logs += "    [WARN] Detener proceso: $($_.Exception.Message)" }
    $uninstallPaths = @("$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe", "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe", "$env:SystemRoot\System32\OneDriveSetup.exe")
    $uninstalled = $false
    foreach ($path in $uninstallPaths) {
        if (Test-Path $path) {
            $res = Invoke-ExternalCommand -Command "`"$path`" /uninstall" -TimeoutSec 60 -MaxRetries 1
            if ($res.Success -or $res.ExitCode -eq 0) { $r.Logs += "    [OK]  Desinstalado: $path"; $r.Changes++; $uninstalled = $true; break }
        }
    }
    $regPaths = @('HKCU:\Software\Microsoft\OneDrive', 'HKLM:\SOFTWARE\Microsoft\OneDrive', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\OneDrive')
    foreach ($rp in $regPaths) { try { if (Test-Path $rp) { Remove-Item $rp -Recurse -Force -EA Stop; $r.Logs += "    [OK]  Registro $rp"; $r.Changes++ } } catch {} }
    $userFolders = @("$env:LOCALAPPDATA\Microsoft\OneDrive", "$env:APPDATA\Microsoft\OneDrive", "$env:USERPROFILE\OneDrive")
    foreach ($f in $userFolders) { try { if (Test-Path $f) { Remove-Item $f -Recurse -Force -EA Stop; $r.Logs += "    [OK]  Carpeta $f"; $r.Changes++ } } catch {} }
    $shellKeys = @('HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}', 'HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}')
    foreach ($sk in $shellKeys) { try { if (Test-Path $sk) { Set-ItemProperty $sk -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -EA Stop; $r.Logs += "    [OK]  Explorador oculto"; $r.Changes++ } } catch {} }
    
    $odUWP = Get-AppxPackage -Name '*Microsoft.OneDrive*' -AllUsers -EA SilentlyContinue
    if ($odUWP) {
        try {
            $odUWP | Remove-AppxPackage -AllUsers -EA SilentlyContinue
            $r.Logs += "    [OK]  OneDrive UWP (AppxPackage) eliminado"; $r.Changes++
        } catch { $r.Logs += "    [WARN] OneDrive UWP: $($_.Exception.Message)" }
    }
    $pdFolder = "$env:PROGRAMDATA\Microsoft OneDrive"
    if (Test-Path $pdFolder) {
        try {
            Remove-Item $pdFolder -Recurse -Force -EA Stop
            $r.Logs += "    [OK]  ProgramData OneDrive eliminado"; $r.Changes++
        } catch { $r.Logs += "    [WARN] ProgramData: $($_.Exception.Message)" }
    }
    try {
        $odPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
        if (-not (Test-Path $odPolicy)) { New-Item $odPolicy -Force | Out-Null }
        Set-ItemProperty $odPolicy -Name 'DisableFileSyncNGSC' -Value 1 -Type DWord -Force
        $r.Logs += "    [OK]  Politica DisableFileSyncNGSC=1 aplicada"; $r.Changes++
    } catch { $r.Logs += "    [WARN] DisableFileSyncNGSC: $($_.Exception.Message)" }
    
    return $r
}

function Invoke-PayloadNICTuning {
    param([array]$Properties)
    $r = @{ Success = $true; Changes = 0; Logs = @() }
    $adapters = @(Get-NetAdapter | Where-Object { -not $_.Virtual -and $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'TAP|Tunnel|VPN|WireGuard|Loopback|Hyper-V|vEthernet|Bluetooth' })
    if ($adapters.Count -eq 0) { $r.Logs += "    [SKIP] NICTuning — sin NIC física activa"; return $r }
    foreach ($adapter in $adapters) {
        $r.Logs += "    [INFO] NIC: $($adapter.Name)"
        foreach ($prop in $Properties) {
            $propName = $prop.RegistryKeyword; $friendlyName = $prop.FriendlyName
            $val = if ($script:ctx.Runtime.IsRollback -or $script:ctx.Runtime.IsManifestRestore) { $prop.RestoreValue } else { $prop.TargetValue }
            if ($script:ctx.Runtime.IsDryRun) { $r.Changes++; $r.Logs += "    [DRY] $($adapter.Name) — $($friendlyName) -> $val"; continue }
            try {
                $existing = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $propName -EA SilentlyContinue
                if (-not $existing) {
                    try {
                        Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $friendlyName -DisplayValue "$val" -EA Stop
                        $r.Changes++; $r.Logs += "    [OK]  $($adapter.Name) — $($friendlyName) -> $val (DisplayName fallback)"
                    } catch {
                        $r.Logs += "    [SKIP] $($adapter.Name) — $($friendlyName): no soportado (RegistryKeyword + DisplayName fallaron)"
                    }
                    continue
                }
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $propName -RegistryValue $val -EA Stop
                $r.Changes++; $r.Logs += "    [OK]  $($adapter.Name) — $($friendlyName) -> $val"
            } catch { $r.Logs += "    [WARN] $($adapter.Name) — $($friendlyName): $($_.Exception.Message)" }
        }
    }
    return $r
}

function Invoke-PayloadPowercfg {
    param([array]$Settings)
    $r = @{ Success = $true; Changes = 0; Logs = @() }
    foreach ($s in $Settings) {
        $val = if ($script:ctx.Runtime.IsRollback -or $script:ctx.Runtime.IsManifestRestore) { $s.RestoreValue } else { $s.TargetValue }
        if ($script:ctx.Runtime.IsDryRun) { $r.Changes++; $r.Logs += "    [DRY] powercfg /change $($s.Setting) $val"; continue }
        $res = Invoke-ExternalCommand -Command "powercfg /change $($s.Setting) $val" -TimeoutSec 15
        if ($res.Success) { $r.Changes++; $r.Logs += "    [OK]  powercfg /change $($s.Setting) $val" }
        else { $r.Logs += "    [WARN] powercfg $($s.Setting) — ExitCode: $($res.ExitCode)" }
    }
    return $r
}

function Invoke-PayloadUltimatePower {
    param([object]$Payload)
    $r = @{ Success = $true; Changes = 0; Logs = @() }
    $ultimateGUID = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    if ($script:ctx.Runtime.IsRollback -or $script:ctx.Runtime.IsManifestRestore) {
        if ($script:ctx.Runtime.IsDryRun) { $r.Logs += "    [DRY] powercfg Balanced restore"; $r.Changes = 1; return $r }
        $res = Invoke-ExternalCommand -Command "powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e" -TimeoutSec 15
        if ($res.Success) { $r.Changes++; $r.Logs += "    [OK]  Plan Balanced restaurado" }
        else { $r.Success = $false; $r.Logs += "    [FAIL] Restaurar Balanced" }
        return $r
    }
    if ($script:ctx.Runtime.IsDryRun) { $r.Logs += "    [DRY] Activar Ultimate Performance"; $r.Changes = 1; return $r }
    $listRes = Invoke-ExternalCommand -Command "powercfg /list" -TimeoutSec 15
    $existingGUID = $null
    if ($listRes.Success -and $listRes.Stdout) {
        foreach ($line in ($listRes.Stdout -split "`n")) {
            if ($line -match 'Ultimate Performance' -or $line -match $ultimateGUID) {
                if ($line -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $existingGUID = $Matches[1]; break }
            }
        }
    }
    if ($existingGUID) { $r.Logs += "    [INFO] Plan Ultimate ya existe (GUID: $existingGUID)" } 
    else {
        $dupRes = Invoke-ExternalCommand -Command "powercfg /duplicatescheme $ultimateGUID" -TimeoutSec 20
        if (-not $dupRes.Success) { $r.Success = $false; $r.Logs += "    [FAIL] Duplicar esquema"; return $r }
        if ($dupRes.Stdout -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            $existingGUID = $Matches[1]; $r.Logs += "    [OK]  Plan duplicado: $existingGUID"
        } else { $r.Success = $false; $r.Logs += "    [FAIL] GUID no encontrado en respuesta"; return $r }
    }
    $activeRes = Invoke-ExternalCommand -Command "powercfg /setactive $existingGUID" -TimeoutSec 15
    if ($activeRes.Success) { $r.Changes++; $r.Logs += "    [OK]  Plan Ultimate activado" } 
    else { $r.Success = $false; $r.Logs += "    [FAIL] Activar plan" }
    return $r
}

function Invoke-PayloadNvidiaOptimize {
    param([array]$Template)
    $r = @{ Success = $true; Changes = 0; Logs = @() }
    if (-not $script:SystemCaps.HasNvidia) { $r.Logs += "    [SKIP] NvidiaOptimize — GPU NVIDIA no detectada"; return $r }

    $gpuRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $nvidiaKeys = @()
    foreach ($k in Get-ChildItem -LiteralPath $gpuRoot -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' }) {
        $provider = (Get-ItemProperty -LiteralPath $k.PSPath -Name 'ProviderName' -EA SilentlyContinue).ProviderName
        if ($provider -match 'NVIDIA') { $nvidiaKeys += $k.PSPath }
    }

    if ($nvidiaKeys.Count -eq 0) { $r.Logs += "    [SKIP] NvidiaOptimize — No se encontró subclave de driver NVIDIA"; return $r }

    foreach ($path in $nvidiaKeys) {
        $r.Logs += "    [INFO] Aplicando a subclave: $(Split-Path $path -Leaf)"
        foreach ($reg in $Template) {
            $val = if ($script:ctx.Runtime.IsRollback -or $script:ctx.Runtime.IsManifestRestore) { $reg.RestoreValue } else { $reg.TargetValue }
            $res = Set-ManolitoReg -Path $path -Name $reg.Name -Value $val -Type $reg.Type
            $r.Changes += $res.Changes; $r.Logs += $res.Msg
        }
    }
    return $r
}

function Invoke-PayloadTimerResolution {
    param([object]$Payload)
    $r = @{ Success = $true; Changes = 0; Logs = @() }
    
    if ($script:ctx.Runtime.IsManifestRestore) {
        $val = if ($script:ctx.Backups.BCD.ContainsKey('disabledynamictick')) { $script:ctx.Backups.BCD['disabledynamictick'] } else { $Payload.RestoreValue }
    } else {
        $val = if ($script:ctx.Runtime.IsRollback) { $Payload.RestoreValue } else { $Payload.TargetValue }
    }

    if ($script:ctx.Runtime.IsDryRun) { $r.Changes+=2; $r.Logs += "    [DRY] bcdedit TimerRes: disabledynamictick=$val"; return $r }

    foreach ($setting in @('useplatformtick', 'disabledynamictick')) {
        if (-not $script:ctx.Runtime.IsRollback -and -not $script:ctx.Backups.BCD.ContainsKey($setting)) {
            $bcdEnum = Invoke-ExternalCommand -Command "bcdedit /enum `{current`}" -TimeoutSec 10
            $bcdBefore = if ($bcdEnum.Success -and $bcdEnum.Stdout) { ($bcdEnum.Stdout | Select-String $setting) } else { $null }
            $script:ctx.Backups.BCD[$setting] = if ($bcdBefore) { ($bcdBefore.Line -split '\s+', 2)[1].Trim() } else { $Payload.RestoreValue }
        }
    }

    $platformTickVal = if ($val -eq 'yes') { 'no' } else { 'yes' }

    $res1 = Invoke-ExternalCommand -Command "bcdedit /set useplatformtick $platformTickVal" -TimeoutSec 15
    if ($res1.Success) { $r.Logs += "    [OK]  useplatformtick = $platformTickVal"; $r.Changes++ } else { $r.Logs += "    [WARN] useplatformtick: ExitCode $($res1.ExitCode)" }

    $res2 = Invoke-ExternalCommand -Command "bcdedit /set disabledynamictick $val" -TimeoutSec 15
    if ($res2.Success) { $r.Logs += "    [OK]  disabledynamictick = $val"; $r.Changes++ } else { $r.Success = $false; $r.Logs += "    [FAIL] disabledynamictick" }

    return $r
}

function Invoke-Payload($PayloadName) {
    $payload = $script:Config.Payloads.PSObject.Properties[$PayloadName].Value
    if(-not $payload) { return @{ Success=$false; Logs=@("[FAIL] Payload no encontrado") } }

    $meta = $payload._meta
    
	if(-not $meta.Reversible -and $script:ctx.Runtime.IsRollback) { return @{ Success=$true; Skipped=$true; Logs=@("    [SKIP] $($meta.Label) (No reversible)") } }
    if($script:SystemCaps.IsVM -and $PayloadName -in @('MSITuning', 'DisableVBS')) { return @{ Success=$true; Skipped=$true; Logs=@("    [SKIP] $($meta.Label) (Omitido en VM)") } }
    if($script:SystemCaps.IsDomain -and $PayloadName -in @('DisableVBS', 'KillActiveSetup')) { return @{ Success=$true; Skipped=$true; Logs=@("    [SKIP] $($meta.Label) (Equipo en Dominio)") } }
    if(-not $script:SystemCaps.HasPhysicalNIC -and $PayloadName -eq 'NetworkOptimize') { return @{ Success=$true; Skipped=$true; Logs=@("    [SKIP] $($meta.Label) (Sin NIC física activa)") } }


    if ($meta.PSObject.Properties['MinBuild'] -and $meta.MinBuild -and $script:SystemCaps.WinBuild -lt [int]$meta.MinBuild) {
        return @{ Success=$true; Skipped=$true; Logs=@("    [SKIP] $($meta.Label) — requiere build $($meta.MinBuild)") }
    }
    $script:NvidiaExclusivePayloads = @('NvidiaTelemetry', 'NvidiaOptimize')
    if (-not $script:SystemCaps.HasNvidia -and $PayloadName -in @('NvidiaTelemetry', 'NvidiaOptimize')) {
        return @{ Success=$true; Skipped=$true; Logs=@("    [SKIP] $PayloadName — sin GPU NVIDIA detectada") }
    }
    if ($script:SystemCaps.HasPrinter -and $PayloadName -eq 'DisablePrintSpooler') {
        return @{ Success=$true; Skipped=$true; Logs=@("    [SKIP] DisablePrintSpooler — impresora detectada") }
    }
    if (-not $script:SystemCaps.HasOffice -and $PayloadName -eq 'OfficeTelemetry') {
        return @{ Success=$true; Skipped=$true; Logs=@("    [SKIP] OfficeTelemetry — Office no detectado") }
    }
    if (-not $script:SystemCaps.HasHAGS -and $PayloadName -eq 'EnableHAGS') {
        return @{ Success=$true; Skipped=$true; Logs=@("    [SKIP] EnableHAGS — hardware insuficiente") }
    }
    if (-not $script:SystemCaps.HasOneDrive -and $PayloadName -eq 'DisableOneDrive') {
        return @{ Success=$true; Skipped=$true; Logs=@("    [SKIP] DisableOneDrive — OneDrive no detectado") }
    }

    if(-not $meta.Reversible -and -not $script:ctx.Runtime.IsRollback) { $script:ctx.Tracking.IrreversibleActions += $PayloadName }
    if($meta.RequiresReboot -and -not $script:ctx.Runtime.IsDryRun) { $script:ctx.State.PendingReboot = $true }

    $moduleResult = @{ Name=$PayloadName; Success=$true; Changes=0; Logs=@() }
    $moduleResult.Logs += "> Ejecutando: $($meta.Label)..."

    if ($script:SystemCaps.HasBattery -and $PayloadName -eq 'PowerTuning') {
        $moduleResult.Logs += "    [WARN] PowerTuning en portátil — puede afectar batería."
    }

    if ($PayloadName -eq "DeKMS") {
        $res = Invoke-PayloadDeKMS $payload
        $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false}
    } else {
        if($payload.PSObject.Properties["Packages"])             { $res = Invoke-PayloadAppx $payload.Packages;       $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["Services"])             { $res = Invoke-PayloadServices $payload.Services;   $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["Tasks"])                { $res = Invoke-PayloadTasks $payload.Tasks;         $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["Registry"])             { $res = Invoke-PayloadRegistry $payload.Registry;   $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["RegistryKeys"])         { $res = Invoke-PayloadRegistryKeys $payload.RegistryKeys; $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["NagleTemplate"])        { $res = Invoke-PayloadNagle $payload.NagleTemplate; $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["DNS"])                  { $res = Invoke-PayloadDNS $payload.DNS;             $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["BCD"])                  { $res = Invoke-PayloadBCD $payload.BCD;             $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["DeviceClasses"])        { $res = Invoke-PayloadMSITuning $payload;           $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
		if($payload.PSObject.Properties["WingetPackages"]) { if ($script:SystemCaps.CanUseWinget) { $res = Invoke-PayloadWinget $payload.WingetPackages; $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} } else { $moduleResult.Logs += "    [SKIP] WingetPackages — Winget no disponible" }  }
        if($payload.PSObject.Properties["NvidiaOptimizeTemplate"]) { $res = Invoke-PayloadNvidiaOptimize $payload.NvidiaOptimizeTemplate; $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
		if($payload.PSObject.Properties["OneDriveUninstall"])    { $res = Invoke-PayloadOneDrive $payload;            $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["NICProperties"])        { $res = Invoke-PayloadNICTuning $payload.NICProperties; $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["UltimatePowerPlan"])    { $res = Invoke-PayloadUltimatePower $payload;       $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["TimerResConfig"])       { $res = Invoke-PayloadTimerResolution $payload.TimerResConfig; $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["PowercfgSettings"])     { $res = Invoke-PayloadPowercfg $payload.PowercfgSettings; $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["WindowsFeatures"])      { $res = Invoke-PayloadWindowsFeatures $payload.WindowsFeatures; $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["TempCleanup"])          { $res = Invoke-PayloadCleanup -IncludeDism:$false;  $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties["DismResetBase"])        { $res = Invoke-PayloadCleanup -IncludeDism:$true;   $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false} }
        if($payload.PSObject.Properties['ActiveSetupEntries']) {
            $res = Invoke-PayloadActiveSetup $payload.ActiveSetupEntries; $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false}
        }
        if($payload.PSObject.Properties['HostsEntries']) {
            $res = Invoke-PayloadHosts $payload.HostsEntries; $moduleResult.Changes += $res.Changes; $moduleResult.Logs += $res.Logs; if(-not $res.Success){$moduleResult.Success=$false}
        }
    }

    if($moduleResult.Success) { 
        $script:ctx.State.StepsOk++ 
        $script:logQueue.Enqueue("COUNT:$($script:ctx.State.StepsOk)")
    } else { $script:ctx.State.StepsFail++ }
    
    $script:ctx.Results.Modules += $moduleResult
    return $moduleResult
}

function ConvertTo-NativeHashtable {
    param($obj)
    if ($null -eq $obj) { return @{} }
    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        $ht = @{}
        foreach ($p in $obj.PSObject.Properties) { $ht[$p.Name] = $p.Value }
        return $ht
    }
    return $obj
}

function Invoke-AuditMode {
    $report = @()
    $report += "═══════════════════════════════════════════════════"
    $report += "  MANOLITO ENGINE $($script:Config.Manifest.Version) — MODO AUDITAR"
    $report += "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $report += "═══════════════════════════════════════════════════"
    $report += "`n[ HARDWARE ]"
    $report += "  GPU NVIDIA   : $(if ($script:SystemCaps.HasNvidia)   { 'SÍ' } else { 'NO' })"
    $report += "  HAGS elegible: $(if ($script:SystemCaps.HasHAGS)     { 'SÍ (NVIDIA + VRAM compatible — HAGS requiere ≥ 8 GB)' } else { 'NO' })"
    $report += "  NVMe         : $(if ($script:SystemCaps.HasNVMe)     { 'SÍ' } else { 'NO' })"
    $report += "  Batería      : $(if ($script:SystemCaps.HasBattery)  { 'SÍ (portátil)' } else { 'NO (sobremesa)' })"
    $report += "  Impresora    : $(if ($script:SystemCaps.HasPrinter)  { 'SÍ' } else { 'NO' })"
    $report += "  VM           : $(if ($script:SystemCaps.IsVM)        { 'SÍ' } else { 'NO' })"
    $report += "  Dominio      : $(if ($script:SystemCaps.IsDomain)    { 'SÍ' } else { 'NO' })"
    $report += "  Build Windows: $($script:SystemCaps.WinBuild)"
    $report += "`n[ SOFTWARE ]"
    $report += "  Office 16.x  : $(if ($script:SystemCaps.HasOffice)   { 'SÍ' } else { 'NO' })"
    $report += "  OneDrive     : $(if ($script:SystemCaps.HasOneDrive) { 'SÍ' } else { 'NO' })"
    $report += "  Winget       : $(if ($script:SystemCaps.CanUseWinget){ 'SÍ' } else { 'NO' })"
    $report += "`n[ SEGURIDAD ]"
    try {
        $vbsState = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity' -EA Stop).EnableVirtualizationBasedSecurity
        $report  += "  VBS          : $(if ($vbsState -eq 1) { 'ACTIVO' } else { 'INACTIVO' })"
    } catch { $report += "  VBS          : No determinado" }
    try {
        $hvciState = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled' -EA Stop).Enabled
        $report += "  HVCI         : $(if ($hvciState -eq 1) { 'ACTIVO' } else { 'INACTIVO' })"
    } catch { $report += "  HVCI         : No determinado" }
    try {
        $uacLevel = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ConsentPromptBehaviorAdmin' -EA Stop).ConsentPromptBehaviorAdmin
        $uacDesc  = switch ($uacLevel) { 0 { 'Sin notificación (inseguro)' } 1 { 'Credenciales en escritorio seguro' } 2 { 'Credenciales (sin escritorio seguro)' } 5 { 'Default Windows (confirmación)' } default { "Nivel $uacLevel" } }
        $report += "  UAC          : $uacDesc"
    } catch { $report += "  UAC          : No determinado" }
    $report += "`n[ TELEMETRÍA ]"
    try {
        $telVal = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -EA Stop).AllowTelemetry
        $report += "  AllowTelemetry: $telVal $(if ($telVal -eq 0) { '(bloqueada)' } else { '(activa)' })"
    } catch { $report += "  AllowTelemetry: No configurada por política" }
    $report += "`n[ SERVICIOS ]"
    foreach ($svc in @('DiagTrack','SysMain','WSearch','Spooler','RemoteRegistry','WerSvc','XblAuthManager','NvTelemetryContainer')) {
        $s = Get-Service $svc -EA SilentlyContinue
        if ($s) { $report += "  $($svc.PadRight(22)): $($s.StartType.ToString().PadRight(12)) | Estado: $($s.Status)" } else { $report += "  $($svc.PadRight(22)): No instalado" }
    }
    $report += "`n[ HAGS ]"
    try {
        $hagsVal = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -EA Stop).HwSchMode
        $report += "  HwSchMode    : $hagsVal $(if ($hagsVal -eq 2) { '(HAGS ACTIVO)' } else { '(HAGS inactivo)' })"
    } catch { $report += "  HwSchMode    : No configurado" }
    $report += "`n[ ESTADO ]"
    $report += "  Reboot pendiente: $(if ($script:SystemCaps.PendingReboot) { 'SÍ' } else { 'NO' })"
    $report += "  Safe Mode       : $(if ($script:SystemCaps.IsSafeMode)    { 'SÍ' } else { 'NO' })"
    $report += "`n═══════════════════════════════════════════════════"
    return $report
}

function Invoke-SafeCheckpoint {
    param([string]$Description = "Manolito Engine $($script:Config.Manifest.Version) — Pre-Despliegue")
    $result = @{ Success = $false; Skipped = $false; Message = '' }
    $srEnabled = $false
    try {
        $srConfig = Get-CimInstance -Namespace 'root\default' -ClassName SystemRestoreConfig -EA SilentlyContinue
        if (-not $srConfig) {
            $srReg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'RPSessionInterval' -EA SilentlyContinue
            $srEnabled = ($null -ne $srReg -and $srReg.RPSessionInterval -gt 0)
        } else { $srEnabled = $true }
        if ($null -ne (Get-ComputerRestorePoint -EA SilentlyContinue)) { $srEnabled = $true }
    } catch { $srEnabled = $false }
    if (-not $srEnabled) {
        $result.Skipped = $true; $result.Message = "La Protección del Sistema no está activa en C:\. No se puede crear un punto de restauración.`n`nPara activarla: Panel de control → Sistema → Protección del sistema."
        return $result
    }
    if ($script:SystemCaps.IsSafeMode) {
        $result.Skipped = $true; $result.Message = "Checkpoint no disponible en Modo Seguro."; return $result
    }
    try {
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -EA Stop
        $result.Success = $true; $result.Message = "Punto de restauración creado: `"$Description`""
    } catch { $result.Success = $false; $result.Message = "Error al crear punto: $($_.Exception.Message)" }
    return $result
}

function Start-ManolitoRunspace {
    param([array] $Plan, [System.Collections.Concurrent.ConcurrentQueue[string]] $Queue)
$motorFuncs = @(
        'Set-ManolitoReg','Restore-ManolitoReg','Invoke-ExternalCommand',
        'Invoke-PayloadAppx','Invoke-PayloadServices','Invoke-PayloadTasks',
        'Invoke-PayloadRegistry','Invoke-PayloadRegistryKeys','Invoke-PayloadNagle','Invoke-PayloadDNS',
        'Invoke-PayloadBCD','Invoke-PayloadMSITuning','Invoke-PayloadDeKMS',
        'Invoke-PayloadHosts','Invoke-PayloadActiveSetup','Invoke-Payload',
        'Invoke-PayloadWinget','Invoke-PayloadOneDrive','Invoke-PayloadNICTuning',
        'Invoke-PayloadUltimatePower','Invoke-PayloadTimerResolution','Resolve-DnsBackup',
        'Invoke-PayloadWindowsFeatures','Invoke-PayloadCleanup','Invoke-PayloadPowercfg',
        'Invoke-PayloadNvidiaOptimize'
    )
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($name in $motorFuncs) {
        $def = Get-Item "Function:$name" -EA SilentlyContinue
        if ($def) { $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new($name, $def.Definition)) }
    }
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    
    $null = $ps.AddScript({
        param($plan, $ctx, $systemCaps, $config, $queue)
        $script:ctx        = $ctx
        $script:SystemCaps = $systemCaps
        $script:Config     = $config
        $script:logQueue   = $queue
        $total = $plan.Count; $i = 0
        try {
            foreach ($pName in $plan) {
                $res = Invoke-Payload $pName
                $script:ctx.Tracking.PayloadsExecuted += $pName
                foreach ($log in $res.Logs) { $queue.Enqueue("LOG:$log") }
                $i++; $queue.Enqueue("PROG:$([int]($i / $total * 100))")
            }
            $statePayload = @{
                State    = @{ StepsOk = $script:ctx.State.StepsOk; StepsFail = $script:ctx.State.StepsFail; PendingReboot = $script:ctx.State.PendingReboot }
                Tracking = @{ RegDiff = $script:ctx.Tracking.RegDiff; PayloadsExecuted = $script:ctx.Tracking.PayloadsExecuted; IrreversibleActions = $script:ctx.Tracking.IrreversibleActions }
                Backups  = @{ ServicesStartup = $script:ctx.Backups.ServicesStartup; TasksState = $script:ctx.Backups.TasksState; DNS = $script:ctx.Backups.DNS; Hosts = $script:ctx.Backups.Hosts; BCD = $script:ctx.Backups.BCD; ActiveSetup = $script:ctx.Backups.ActiveSetup; WindowsFeatures = $script:ctx.Backups.WindowsFeatures }
                Results  = @{ Modules = $script:ctx.Results.Modules }
            } | ConvertTo-Json -Depth 15 -Compress
            $queue.Enqueue("STATE:$statePayload")
            $queue.Enqueue('DONE:OK')
        } catch {
            $queue.Enqueue("LOG:    [FATAL] Error inesperado en motor: $($_.Exception.Message)")
            $queue.Enqueue('DONE:FAIL')
        }
    })
    $null = $ps.AddParameter('plan', $Plan); $null = $ps.AddParameter('ctx', $script:ctx); $null = $ps.AddParameter('systemCaps', $script:SystemCaps); $null = $ps.AddParameter('config', $script:Config); $null = $ps.AddParameter('queue', $Queue)
    return @{ PS=$ps; RS=$rs; Result=$ps.BeginInvoke() }
}

function Import-ManifestToContext {
    param([string] $ManifestPath, [System.Windows.Controls.StackPanel] $SpDynamic, [System.Windows.Controls.TextBlock] $TxtDesc, [System.Windows.Controls.TextBox] $Console)
    try { $m = Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $Console.Text += "`n    [FAIL] No se pudo leer el manifest"; return $null }
    $script:ctx.Backups.ServicesStartup = ConvertTo-NativeHashtable $m.BackupServicesState
    $script:ctx.Backups.TasksState      = ConvertTo-NativeHashtable $m.BackupTasksState
    $script:ctx.Backups.DNS             = ConvertTo-NativeHashtable $m.BackupDNS
    $script:ctx.Backups.BCD             = ConvertTo-NativeHashtable $m.BackupBCD
    $script:ctx.Backups.ActiveSetup     = ConvertTo-NativeHashtable $m.BackupActiveSetup
    $script:ctx.Backups.WindowsFeatures = ConvertTo-NativeHashtable $m.BackupWindowsFeatures
    $script:ctx.Backups.Hosts           = $m.BackupHosts
    $script:ctx.Tracking.RegDiff        = if ($m.RegDiff) { @($m.RegDiff) } else { @() }
    $script:ctx.Runtime.IsRollback        = $true
    $script:ctx.Runtime.IsManifestRestore = $true
    $plan = @()
    if ($m.Summary.PayloadsExecuted) {
        foreach ($pName in $m.Summary.PayloadsExecuted) {
            $prop = $script:Config.Payloads.PSObject.Properties[$pName]
            $meta = if ($prop -and $prop.Value -and $prop.Value._meta) { $prop.Value._meta } else { $null }
            if ($meta -and $meta.Reversible) { $plan += $pName }
        }
    }
    $SpDynamic.Children.Clear()
    $TxtDesc.Text = "[MANIFEST RESTORE] $($m.Timestamp)  —  Runlevel origen: $($m.Runlevel)"; $TxtDesc.Foreground = '#BF00FF'
    foreach ($pName in $plan) {
        $meta = $script:Config.Payloads.$pName._meta
        $icono = if ($meta.Risk -eq 'IRR') { '[!]' } elseif ($meta.Risk -eq 'MOD') { '[~]' } else { '[*]' }
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = "$icono $($meta.Label)"; $cb.Tag = $pName; $cb.IsChecked = $true; $cb.Foreground = '#BF00FF'
        $SpDynamic.Children.Add($cb) | Out-Null
    }
    $Console.Text += "`n    [OK]  Manifest cargado — $($plan.Count) payloads desde $ManifestPath"
    return $plan
}

function Write-PreAudit {
    param([array]$Plan, [System.Windows.Controls.TextBox]$Console)
    $Console.Text += "`n`n> [PRE-AUDIT] Plan de ejecución ($($Plan.Count) payloads):"
    foreach ($pName in $Plan) {
        $meta = $script:Config.Payloads.PSObject.Properties[$pName].Value._meta
        if (-not $meta) { continue }
        $tag  = switch ($meta.Risk) { 'IRR' { '[!]' } 'MOD' { '[~]' } default { '[*]' } }
        $rev  = if ($meta.Reversible) { 'Reversible' } else { 'IRREVERSIBLE — confirmar' }
        $Console.Text += "`n    $tag $($pName.PadRight(22)) -> $rev"
    }
    $Console.Text += "`n> Iniciando en 1.5s...`n"
}

function Test-ManolitoSchema {
    param([PSObject]$Config)
    $errors = @()
    $validRisks = @('SAFE','MOD','IRR')
    $validTypes = @('DWord','QWord','String','ExpandString','Binary','MultiString')
    foreach ($rlName in @('Lite','DevEdu','Deep','Rollback')) {
        $rl = $Config.UIMapping.Runlevels.$rlName
        if (-not $rl)            { $errors += "Runlevel '$rlName' ausente"; continue }
        if (-not $rl.Payloads)   { $errors += "Runlevel '$rlName': Payloads vacío"; continue }
        foreach ($pName in $rl.Payloads) { 
            if (-not $Config.Payloads.PSObject.Properties[$pName]) { $errors += "Runlevel '$rlName': payload '$pName' no existe" } 
            if ($rlName -eq 'Rollback' -and $Config.Payloads.PSObject.Properties[$pName]) {
                $meta = $Config.Payloads.PSObject.Properties[$pName].Value._meta
                if ($meta -and $meta.Reversible -eq $false) { $errors += "Runlevel 'Rollback' contiene payload no-reversible: $pName" }
            }
        }
    }
    foreach ($prop in $Config.Payloads.PSObject.Properties) {
        $pName = $prop.Name; $p = $prop.Value
        if (-not $p._meta) { $errors += "Payload '$pName': falta _meta"; continue }
        if ([string]::IsNullOrWhiteSpace($p._meta.Label)) { $errors += "Payload '$pName': _meta.Label vacío" }
        if ($p._meta.Risk -notin $validRisks) { $errors += "Payload '$pName': Risk='$($p._meta.Risk)' inválido" }
        if ($p.Registry) {
            foreach ($entry in $p.Registry) {
                if ($entry.Type -and $entry.Type -notin $validTypes) { $errors += "Payload '$pName': Registry Type '$($entry.Type)' inválido" }
                if ([string]::IsNullOrWhiteSpace($entry.Path)) { $errors += "Payload '$pName': Registry entry sin Path" }
            }
        }
        if ($p.NagleTemplate) {
            foreach ($entry in $p.NagleTemplate) {
                if ($entry.Type -and $entry.Type -notin $validTypes) { $errors += "Payload '$pName': NagleTemplate Type '$($entry.Type)' inválido" }
            }
        }
        if ($p.NvidiaOptimizeTemplate) {
            foreach ($entry in $p.NvidiaOptimizeTemplate) {
                if ($entry.Type -and $entry.Type -notin $validTypes) { $errors += "Payload '$pName': NvidiaOptimizeTemplate Type '$($entry.Type)' inválido" }
            }
        }
        if ($p.HostsEntries) {
            foreach ($entry in $p.HostsEntries) { if (-not ($entry -is [string]) -or [string]::IsNullOrWhiteSpace($entry)) { $errors += "Payload '$pName': HostsEntries — string inválido" } }
        }
        if ($p.ActiveSetupEntries) {
            $guidRegex = '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$'
            foreach ($guid in $p.ActiveSetupEntries) { if (-not ($guid -is [string]) -or $guid -notmatch $guidRegex) { $errors += "Payload '$pName': ActiveSetup GUID mal formado" } }
        }
    }
    return $errors
}

$schemaErrors = Test-ManolitoSchema -Config $script:Config
if ($schemaErrors.Count -gt 0) { [System.Windows.MessageBox]::Show(($schemaErrors -join "`n"), 'Schema Error', 0, 16); exit 1 }

function Test-ProfileVersion {
    param([string]$ProfileVersion, [string]$EngineVersion)
    if ([string]::IsNullOrWhiteSpace($ProfileVersion)) { return @{ Compatible = $true; Warn = $true; Message = "El perfil no contiene EngineVersion. Puede ser de una versión anterior." } }
    if ($ProfileVersion -ne $EngineVersion) {
        $pMajMin = ($ProfileVersion -split '\.') | Select-Object -First 2
        $eMajMin = ($EngineVersion  -split '\.') | Select-Object -First 2
        $sameMinor = ($pMajMin[0] -eq $eMajMin[0]) -and ($pMajMin[1] -eq $eMajMin[1])
        return @{ Compatible = $sameMinor; Warn = $true; Message = "Perfil generado con motor $ProfileVersion. Motor activo: $EngineVersion. $(if (-not $sameMinor) { "Incompatible estructuralmente." } else { "Compatible pero puede omitir payloads nuevos." })" }
    }
    return @{ Compatible = $true; Warn = $false; Message = '' }
}

function Export-HtmlReport {
    param(
        [string]$OutputDir,
        [string]$Runlevel,
        [int]   $StepsOk,
        [int]   $StepsFail,
        [array] $Modules,
        [string]$Version = '2.8.0'
    )
    $ts      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $outFile = Join-Path $OutputDir "report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $rows = foreach ($m in $Modules) {
        $statusHtml = if (-not $m.Success) { '<span class="b-fail">FAIL</span>' } else { '<span class="b-ok">OK</span>' }
        $logText = (($m.Logs | ForEach-Object { [System.Security.SecurityElement]::Escape([string]$_) }) -join "`n")
        "<tr><td class='pname'>$($m.Name)</td><td>$statusHtml</td><td class='num'>$($m.Changes)</td><td class='logs'>$logText</td></tr>"
    }
    $rowsHtml = $rows -join "`n"
$html = @"
<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><title>Manolito Report $Version</title><style>*{box-sizing:border-box;margin:0;padding:0}body{background:#08001A;color:#00FFFF;font-family:Consolas,monospace;padding:40px;line-height:1.6}h1{color:#FF2079;text-shadow:0 0 16px #FF2079;letter-spacing:4px;font-size:22px;margin-bottom:4px}.sub{color:#BF00FF;font-size:12px;letter-spacing:2px;margin-bottom:20px}.meta{background:#0A0015;border:1px solid #2D0050;padding:12px 18px;margin-bottom:24px;font-size:12px;color:#FFB000}.meta span{color:#00FFFF;margin-right:28px}.meta .ok-n{color:#00FF88;font-weight:bold}.meta .fail-n{color:#FF2222;font-weight:bold}table{width:100%;border-collapse:collapse}thead tr{background:#1A0033}th{padding:10px 14px;text-align:left;border:1px solid #2D0050;color:#FF2079;letter-spacing:1px;font-size:12px}td{padding:8px 14px;border:1px solid #2D0050;vertical-align:top;font-size:12px}tr:nth-child(even) td{background:#0A0015}tr:hover td{background:#12002A}.pname{color:#00FFFF;font-weight:bold;white-space:nowrap}.num{text-align:center;color:#FFB000}.logs{color:#44445A;white-space:pre-wrap;max-width:400px;font-size:11px}.b-ok{background:#00FF88;color:#000;padding:2px 10px;border-radius:3px;font-weight:bold;font-size:11px}.b-fail{background:#FF2222;color:#fff;padding:2px 10px;border-radius:3px;font-weight:bold;font-size:11px}footer{margin-top:28px;padding-top:12px;border-top:1px solid #2D0050;color:#2D0050;font-size:11px}</style></head><body><h1>&#9889; MANOLITO ENGINE v$Version</h1><div class="sub">... Xciter ... P R E S E N T A ...</div><div class="meta">  <span>Runlevel: <strong>$Runlevel</strong></span>  <span>Timestamp: <strong>$ts</strong></span>  <span>OK: <strong class="ok-n">$StepsOk</strong></span>  <span>FAIL: <strong class="fail-n">$StepsFail</strong></span></div><table><thead>  <tr><th>PAYLOAD</th><th>STATUS</th><th>CAMBIOS</th><th>LOG</th></tr></thead><tbody>$rowsHtml</tbody></table><footer>Manolito Engine v$Version &mdash; $ts &mdash; $outFile</footer></body></html>
"@
    $html | Out-File -FilePath $outFile -Encoding UTF8 -Force
    return $outFile
}

# ========================================================================
# 4. INTERFAZ GRÁFICA (XAML CYBERPUNK) - DISEÑO GRID RESPONSIVO
# ========================================================================
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Manolito v2.8.0" Height="820" Width="1000" WindowStyle="None" AllowsTransparency="True"
        WindowStartupLocation="CenterScreen" FontFamily="Consolas">
    <Window.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#08001A" Offset="0"/>
            <GradientStop Color="#1A0033" Offset="1"/>
        </LinearGradientBrush>
    </Window.Background>
    <Window.Resources>
        <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#00FFFF"/><Setter Property="Effect"><Setter.Value><DropShadowEffect Color="#00FFFF" BlurRadius="8" ShadowDepth="0" Opacity="0.6"/></Setter.Value></Setter></Style>
        <Style TargetType="CheckBox"><Setter Property="Margin" Value="0,6"/><Setter Property="Cursor" Value="Hand"/></Style>
        <Style TargetType="RadioButton"><Setter Property="Foreground" Value="#00FFFF"/><Setter Property="Margin" Value="0,10"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="FontSize" Value="14"/></Style>
        <Style TargetType="Button"><Setter Property="Cursor" Value="Hand"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="Padding" Value="15,5"/><Setter Property="Margin" Value="5,0"/><Setter Property="Background" Value="Transparent"/></Style>
        <Style TargetType="Border"><Setter Property="BorderBrush" Value="#2D0050"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Background" Value="#0A0015"/><Setter Property="Padding" Value="15"/><Setter Property="Margin" Value="5"/></Style>
    </Window.Resources>
    
    <Border BorderBrush="#00FFFF" Background="Transparent">
        <Border.Effect><DropShadowEffect Color="#BF00FF" BlurRadius="25" ShadowDepth="0" Opacity="0.6"/></Border.Effect>
        <Grid Margin="15">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <TextBlock Grid.Row="0" Name="txtLogo" HorizontalAlignment="Center" FontWeight="Bold" FontSize="11" Margin="0,0,0,6" xml:space="preserve"><TextBlock.Effect><DropShadowEffect Color="#FF2079" BlurRadius="14" ShadowDepth="0" Opacity="1"/></TextBlock.Effect></TextBlock>
			<StackPanel Grid.Row="1" HorizontalAlignment="Center" Margin="0,0,0,10">
                <TextBlock TextAlignment="Center" Margin="0,0,0,4" Foreground="#444444">──────────────────────────────────────────────────────────────────────</TextBlock>
                <TextBlock TextAlignment="Center" FontWeight="Bold">. . . Xciter . . . P R E S E N T A . . .  [ MANOLITO v2.8.0 ]</TextBlock>
            </StackPanel>
            
            <Grid Grid.Row="2" Margin="0,0,0,10">
                <Grid.ColumnDefinitions><ColumnDefinition Width="1.5*"/><ColumnDefinition Width="1.1*"/><ColumnDefinition Width="1.8*"/></Grid.ColumnDefinitions>
                <Border Grid.Column="0"><StackPanel>
                    <TextBlock Text="[ PERFIL DE SISTEMA ]" FontWeight="Bold" Margin="0,0,0,15"/>
                    <TextBlock Margin="0,4"><Run Text="SO         : " Foreground="#555555"/><Run Text="$($script:Config.Manifest.TargetOS)" Foreground="#FF2079"/></TextBlock>
                    <TextBlock Margin="0,4"><Run Text="Motor DB   : " Foreground="#555555"/><Run Text="v$($script:Config.Manifest.Version)" Foreground="#FFB000"/></TextBlock>
                    <TextBlock Margin="0,4"><Run Text="Backend    : " Foreground="#555555"/><Run Text="Data-Driven Async" Foreground="#00FFFF"/></TextBlock>
                    
                    <GroupBox Header="Hardware &amp; Software Detectado" Margin="0,15,0,0" Foreground="#AAAAAA" BorderBrush="#333333">
                        <WrapPanel Margin="4,8,4,4" Orientation="Horizontal">
                            <Label x:Name="lblCapNvidia"   Content="NVIDIA"     Margin="2,2" Padding="6,2" Background="#1A1A1A" Foreground="#666666" FontSize="11"/>
                            <Label x:Name="lblCapHAGS"     Content="HAGS"       Margin="2,2" Padding="6,2" Background="#1A1A1A" Foreground="#666666" FontSize="11"/>
                            <Label x:Name="lblCapNVMe"     Content="NVMe"       Margin="2,2" Padding="6,2" Background="#1A1A1A" Foreground="#666666" FontSize="11"/>
                            <Label x:Name="lblCapOffice"   Content="Office"     Margin="2,2" Padding="6,2" Background="#1A1A1A" Foreground="#666666" FontSize="11"/>
                            <Label x:Name="lblCapOneDrive" Content="OneDrive"   Margin="2,2" Padding="6,2" Background="#1A1A1A" Foreground="#666666" FontSize="11"/>
                            <Label x:Name="lblCapPrinter"  Content="Impresora"  Margin="2,2" Padding="6,2" Background="#1A1A1A" Foreground="#666666" FontSize="11"/>
                            <Label x:Name="lblCapBattery"  Content="Batería"    Margin="2,2" Padding="6,2" Background="#1A1A1A" Foreground="#666666" FontSize="11"/>
                            <Label x:Name="lblCapWinget"   Content="Winget"     Margin="2,2" Padding="6,2" Background="#1A1A1A" Foreground="#666666" FontSize="11"/>
                            <Label x:Name="lblCapVM"       Content="VM"         Margin="2,2" Padding="6,2" Background="#1A1A1A" Foreground="#666666" FontSize="11"/>
                        </WrapPanel>
                    </GroupBox>
                </StackPanel></Border>
                <Border Grid.Column="1"><StackPanel>
                    <TextBlock Text="[ RUNLEVEL ]" FontWeight="Bold" Margin="0,0,0,15"/>
                    <RadioButton Name="rbLite" GroupName="P" Content="$($script:Config.UIMapping.Runlevels.Lite.Label)"/>
                    <RadioButton Name="rbDevEdu" GroupName="P" Content="$($script:Config.UIMapping.Runlevels.DevEdu.Label)" IsChecked="True"/>
                    <RadioButton Name="rbDeep" GroupName="P" Content="$($script:Config.UIMapping.Runlevels.Deep.Label)" Foreground="#FF2222"/>
                    <RadioButton Name="rbRollback" GroupName="P" Content="$($script:Config.UIMapping.Runlevels.Rollback.Label)" Foreground="#BF00FF"/>
                </StackPanel></Border>
                <Border Grid.Column="2"><Grid>
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Name="txtDesc" Text="[ SELECCIONE UN PERFIL ]" FontWeight="Bold" Foreground="#00FFFF" Margin="0,0,0,15"/>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,5,0,0">
                        <StackPanel Name="spDynamicPayloads"></StackPanel>
                    </ScrollViewer>
                </Grid></Border>
            </Grid>
            
            <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="5,0,5,5">
                <CheckBox x:Name="chkSafeCheckpoint" Content="Crear punto de restauración antes de ejecutar" Foreground="#AAAAAA" Margin="8,4,8,4" IsChecked="False" ToolTip="Requiere que la Protección del Sistema esté activa en C:\"/>
            </StackPanel>

            <Border Grid.Row="4" Background="#04000E" Height="260" Margin="5,0,5,5" BorderBrush="#2D0050">
                <ScrollViewer Name="svConsole" VerticalScrollBarVisibility="Auto" Margin="5">
                    <TextBox Name="txtConsole" IsReadOnly="True" Background="Transparent" BorderThickness="0" Foreground="#39FF14" TextWrapping="Wrap" xml:space="preserve" FontSize="12">Manolito Engine v2.8.0 Inicializado. Leyendo Base de Datos...
[INFO] $($script:Config.Manifest.Description)</TextBox>
                </ScrollViewer>
            </Border>
            
            <Grid Grid.Row="5" Margin="5,5,5,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" VerticalAlignment="Center" Orientation="Horizontal">
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Name="txtStatus" Text="ESPERANDO ORDENES..." Foreground="#FFB000"/>
                        <ProgressBar Name="pbProgress" Height="3" Width="200" Background="#111" Foreground="#FF2079" BorderThickness="0" Margin="0,5,0,0" HorizontalAlignment="Left"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="15,0,0,0" VerticalAlignment="Center">
                        <Label Content="Pasos OK:" Foreground="#888888" FontSize="11" VerticalAlignment="Center"/>
                        <Label x:Name="lblStepsCounter" Content="0" Foreground="#00FF99" FontSize="13" FontWeight="Bold" VerticalAlignment="Center" MinWidth="30"/>
                    </StackPanel>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <CheckBox Name="chkDryRun" Content="DRY RUN" IsChecked="True" Foreground="#00FFFF" FontWeight="Bold" Margin="0,0,10,0" VerticalAlignment="Center" />
                    <Button x:Name="btnAudit" Content="🔍 Auditar" Foreground="#FFAA00" BorderBrush="#FFAA00" ToolTip="Diagnóstico pasivo sin aplicar cambios"/>
                    <Button x:Name="btnOpenLogs" Content="📁 Logs" Foreground="#00FFFF" BorderBrush="#00FFFF" IsEnabled="False" ToolTip="Abre carpeta de reportes"/>
                    <Button Name="btnSaveProfile" Content="GUARDAR"  Foreground="#00FFFF" BorderBrush="#00FFFF" ToolTip="Guardar perfil"/>
                    <Button Name="btnLoadProfile" Content="CARGAR"   Foreground="#FFB000" BorderBrush="#FFB000" ToolTip="Cargar perfil"/>
                    <Button Name="btnManifest"    Content="MANIFEST" Foreground="#BF00FF" BorderBrush="#BF00FF" ToolTip="Manifest Restore"/>
                    <Button Name="btnExit"   Content="SALIR"      Foreground="#39FF14" BorderBrush="#39FF14"/>
                    <Button Name="btnDeploy" Content="INICIAR"    Background="#FF2079" Foreground="#08001A" BorderThickness="0"/>
                </StackPanel>
            </Grid>
        </Grid>
    </Border>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)
$window.FindName("txtLogo").Text = " ███╗   ███╗ █████╗ ███╗  ██╗ ██████╗ ██╗     ██╗████████╗ ██████╗ `n ████╗ ████║██╔══██╗████╗ ██║██╔═══██╗██║     ██║╚══██╔══╝██╔═══██╗`n ██╔████╔██║███████║██╔██╗██║██║   ██║██║     ██║   ██║   ██║   ██║`n ██║╚██╔╝██║██╔══██║██║╚████║██║   ██║██║     ██║   ██║   ██║   ██║`n ██║ ╚═╝ ██║██║  ██║██║ ╚███║╚██████╔╝███████╗██║   ██║   ╚██████╔╝`n ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚══╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝    ╚═════╝ "

$btnDeploy = $window.FindName("btnDeploy"); $btnExit = $window.FindName("btnExit"); $btnOpenLogs = $window.FindName("btnOpenLogs")
$btnAudit = $window.FindName("btnAudit"); $chkSafeCheckpoint = $window.FindName("chkSafeCheckpoint")
$txtStatus = $window.FindName("txtStatus"); $pbProgress = $window.FindName("pbProgress"); $lblStepsCounter = $window.FindName("lblStepsCounter")
$chkDryRun = $window.FindName("chkDryRun"); $txtConsole = $window.FindName("txtConsole")
$svConsole = $window.FindName("svConsole"); $txtDesc = $window.FindName("txtDesc")
$spDynamic = $window.FindName("spDynamicPayloads")

$btnSaveProfile = $window.FindName('btnSaveProfile')
$btnLoadProfile = $window.FindName('btnLoadProfile')
$btnManifest    = $window.FindName('btnManifest')

function Update-SystemCapsUI {
    $capMap = @(
        @{ Label = $window.FindName('lblCapNvidia');   Active = $script:SystemCaps.HasNvidia   }
        @{ Label = $window.FindName('lblCapHAGS');     Active = $script:SystemCaps.HasHAGS     }
        @{ Label = $window.FindName('lblCapNVMe');     Active = $script:SystemCaps.HasNVMe     }
        @{ Label = $window.FindName('lblCapOffice');   Active = $script:SystemCaps.HasOffice   }
        @{ Label = $window.FindName('lblCapOneDrive'); Active = $script:SystemCaps.HasOneDrive }
        @{ Label = $window.FindName('lblCapPrinter');  Active = $script:SystemCaps.HasPrinter  }
        @{ Label = $window.FindName('lblCapBattery');  Active = $script:SystemCaps.HasBattery  }
        @{ Label = $window.FindName('lblCapWinget');   Active = $script:SystemCaps.CanUseWinget}
        @{ Label = $window.FindName('lblCapVM');       Active = $script:SystemCaps.IsVM        }
    )
    foreach ($cap in $capMap) {
        if ($cap.Active) {
            $cap.Label.Foreground = '#00FF99'; $cap.Label.Background = '#0A2A1A'
        } else {
            $cap.Label.Foreground = '#444444'; $cap.Label.Background = '#1A1A1A'
        }
    }
}
Update-SystemCapsUI

$updateUI = { param($runlevelKey)
    $rl = $script:Config.UIMapping.Runlevels.$runlevelKey
    $txtDesc.Text = "[ PARAMETROS: $($rl.Label) ]"; $txtDesc.Foreground = $rl.Color
    
    $spDynamic.Children.Clear()
    foreach($p in $rl.Payloads) {
        $meta = $script:Config.Payloads.$p._meta
        $icono = if($meta.Risk -eq 'IRR') { "[!]" } elseif ($meta.Risk -eq 'MOD') { "[~]" } else { "[*]" }
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = "$icono $($meta.Label)"; $cb.Tag = $p
        
        if ($script:MemoriaPayloads.ContainsKey($p) -and $script:MemoriaPayloads[$p] -eq $false) {
            $cb.IsChecked = $false; $cb.Foreground = "#555555"
        } else {
            $cb.IsChecked = $true;  $cb.Foreground = "#FF2079"
        }
        
        $cb.Add_Checked({ $script:MemoriaPayloads.Remove($this.Tag); $this.Foreground = "#FF2079"; Beep-UI "check" })
        $cb.Add_Unchecked({ $script:MemoriaPayloads[$this.Tag] = $false; $this.Foreground = "#555555"; Beep-UI "check" })
        $spDynamic.Children.Add($cb) | Out-Null
    }
    Beep-UI "check"
}

$window.FindName("rbLite").Add_Checked({ & $updateUI "Lite" })
$window.FindName("rbDevEdu").Add_Checked({ & $updateUI "DevEdu" })
$window.FindName("rbDeep").Add_Checked({ & $updateUI "Deep" })
$window.FindName("rbRollback").Add_Checked({ & $updateUI "Rollback" })

$window.Add_MouseLeftButtonDown({ $window.DragMove() })

$window.Add_Loaded({ 
    Beep-UI "boot"
    $window.FindName("rbDevEdu").Focus() | Out-Null
    & $updateUI "DevEdu"
})

$btnSaveProfile.Add_Click({
    $profilesDir = Join-Path $DOCS_MANOLITO 'profiles'
    if (-not (Test-Path $profilesDir)) { New-Item $profilesDir -ItemType Directory -Force | Out-Null }
    $rlKey = if     ($window.FindName('rbLite').IsChecked)   { 'Lite'     }
             elseif ($window.FindName('rbDevEdu').IsChecked) { 'DevEdu'   }
             elseif ($window.FindName('rbDeep').IsChecked)   { 'Deep'     }
             else                                            { 'Rollback' }
    $checked = @($spDynamic.Children | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    $profile  = [ordered]@{ Runlevel = $rlKey; SavedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); EngineVersion = $script:Config.Manifest.Version; Payloads = $checked }
    $filePath = Join-Path $profilesDir "profile_${rlKey}_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $profile | ConvertTo-Json -Depth 5 | Out-File $filePath -Encoding UTF8 -Force
    $txtConsole.Text += "`n    [OK]  Perfil guardado -> $filePath"
    $svConsole.ScrollToEnd(); Beep-UI 'check'
    $btnSaveProfile.Content = 'GUARDADO!'
    $tSave = New-Object System.Windows.Threading.DispatcherTimer
    $tSave.Interval = [TimeSpan]::FromSeconds(2)
    $tSave.Add_Tick({ $args[0].Stop(); $btnSaveProfile.Content = 'GUARDAR' })
    $tSave.Start()
})

$btnLoadProfile.Add_Click({
    $ofd = New-Object Microsoft.Win32.OpenFileDialog
    $ofd.Title = 'Cargar Perfil Manolito'; $ofd.Filter = 'Perfil Manolito (*.json)|*.json'; $ofd.InitialDirectory = Join-Path $DOCS_MANOLITO 'profiles'
    if (-not $ofd.ShowDialog()) { return }
    try {
        $profileData = Get-Content $ofd.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $profileData.Payloads) { throw 'Formato inválido: falta array Payloads' }
        
        $vCheck = Test-ProfileVersion -ProfileVersion $profileData.EngineVersion -EngineVersion $script:Config.Manifest.Version
        if ($vCheck.Warn) {
            $icon = if ($vCheck.Compatible) { [System.Windows.MessageBoxImage]::Warning } else { [System.Windows.MessageBoxImage]::Error }
            $result = [System.Windows.MessageBox]::Show($vCheck.Message + "`n`n¿Deseas continuar cargando este perfil?", 'Versión de Perfil', [System.Windows.MessageBoxButton]::YesNo, $icon)
            if (-not $vCheck.Compatible -and $result -ne [System.Windows.MessageBoxResult]::Yes) { return }
        }

        $rlKey = $profileData.Runlevel
        $script:MemoriaPayloads = @{}
        $allPayloads = $script:Config.UIMapping.Runlevels.$rlKey.Payloads
        foreach ($p in $allPayloads) { if ($profileData.Payloads -notcontains $p) { $script:MemoriaPayloads[$p] = $false } }
        $rbMap = @{ Lite='rbLite'; DevEdu='rbDevEdu'; Deep='rbDeep'; Rollback='rbRollback' }
        if ($rbMap[$rlKey]) { $window.FindName($rbMap[$rlKey]).IsChecked = $true }
        $txtConsole.Text += "`n    [OK]  Perfil cargado — $rlKey / $($profileData.Payloads.Count) payloads — $($ofd.FileName)"
        $svConsole.ScrollToEnd(); Beep-UI 'check'
    } catch { $txtConsole.Text += "`n    [FAIL] Perfil: $($_.Exception.Message)" }
})

$btnManifest.Add_Click({
    $ofd = New-Object Microsoft.Win32.OpenFileDialog
    $ofd.Title = 'Seleccionar Manifest Manolito'; $ofd.Filter = 'Manifest JSON (*.json)|*.json'; $ofd.InitialDirectory = $DOCS_MANOLITO
    if (-not $ofd.ShowDialog()) { return }
    Beep-UI 'action'
    $window.FindName('rbRollback').IsChecked = $true
    $plan = Import-ManifestToContext -ManifestPath $ofd.FileName -SpDynamic $spDynamic -TxtDesc $txtDesc -Console $txtConsole
    if ($plan) {
        $txtConsole.Text += "`n    [INFO] Revisa el plan y pulsa INICIAR para restaurar"
        $svConsole.ScrollToEnd(); Beep-UI 'check'
    } else {
        $script:ctx.Runtime.IsManifestRestore = $false; $script:ctx.Runtime.IsRollback = $false
    }
})

$btnOpenLogs.Add_Click({
    if (Test-Path $DOCS_MANOLITO) { Start-Process explorer.exe -ArgumentList $DOCS_MANOLITO } 
    else { [System.Windows.MessageBox]::Show("La carpeta de logs no existe aún.", 'Logs', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) }
})

$btnAudit.Add_Click({
    Beep-UI "check"; $txtConsole.Text = ''
    foreach ($line in Invoke-AuditMode) { $txtConsole.AppendText("$line`n") }
    $txtConsole.ScrollToHome()
    if (Test-Path $DOCS_MANOLITO) { $btnOpenLogs.IsEnabled = $true }
})

$btnExit.Add_Click({
    Beep-UI "close"; $btnExit.Content="[ APAGANDO ]"; $btnExit.IsEnabled=$false
    $t=New-Object System.Windows.Threading.DispatcherTimer; $t.Interval=[TimeSpan]::FromMilliseconds(400)
    $t.Add_Tick({$args[0].Stop(); $window.Close()}); $t.Start()
})

# ========================================================================
# 5. EL ORQUESTADOR PRINCIPAL
# ========================================================================
$btnDeploy.Add_Click({
    $wasManifestRestore = $script:ctx.Runtime.IsManifestRestore

    $script:ctx.Runtime.IsManifestRestore    = $false
    $script:ctx.Runtime.IsRollback           = $false
    $script:ctx.Runtime.Runlevel             = $null
    $script:ctx.State.StepsOk                = 0
    $script:ctx.State.StepsFail              = 0
    $script:ctx.State.PendingReboot          = $false
    $script:ctx.Tracking.RegDiff             = @()
    $script:ctx.Tracking.PayloadsExecuted    = @()
    $script:ctx.Tracking.IrreversibleActions = @()
    $script:ctx.Results.Modules              = @()
    $script:ctx.Backups = [PSCustomObject]@{ ServicesStartup=@{}; TasksState=@{}; DNS=@{}; Hosts=$null; ActiveSetup=@{}; BCD=@{}; WindowsFeatures=@{} }
    $lblStepsCounter.Content = '0'

    if ($wasManifestRestore) { $script:ctx.Runtime.IsManifestRestore = $true }

    $script:ctx.Runtime.IsDryRun = [bool]$chkDryRun.IsChecked

    if ($script:SystemCaps.IsSafeMode) {
        $txtConsole.Text += "`n    [ABORT] Manolito no puede ejecutarse en modo seguro"
        $btnDeploy.IsEnabled = $true; $btnDeploy.Background = '#FF2079'
        return
    }

    if (Test-AVInterference) {
        $ans = [System.Windows.MessageBox]::Show(
            "Se han detectado procesos de seguridad corporativa activos (CrowdStrike, CarbonBlack, SentinelOne u otro EDR).`n`nManolito puede fallar silenciosamente o generar alertas de seguridad.`n`n¿Deseas continuar de todas formas?",
            "EDR / AV Corporativo Detectado",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($ans -ne [System.Windows.MessageBoxResult]::Yes) {
            $txtConsole.Text += "`n    [ABORT] Ejecucion cancelada — EDR activo"
            $btnDeploy.IsEnabled = $true; $btnDeploy.Background = '#FF2079'
            return
        }
        $txtConsole.Text += "`n    [WARN] EDR detectado — continuando bajo responsabilidad del usuario"
    }

    if ($script:SystemCaps.PendingReboot -and -not $script:ctx.Runtime.IsDryRun) {
        $txtConsole.Text += "`n    [WARN] Reinicio pendiente detectado — se recomienda reiniciar antes de ejecutar"
    }

    $rlKey = if($window.FindName("rbLite").IsChecked){"Lite"} elseif($window.FindName("rbDevEdu").IsChecked){"DevEdu"} elseif($window.FindName("rbDeep").IsChecked){"Deep"} else {"Rollback"}
    
    if (-not $script:ctx.Runtime.IsManifestRestore) { $script:ctx.Runtime.IsRollback = ($rlKey -eq "Rollback") }
    $script:ctx.Runtime.Runlevel = $rlKey
    
    $script:plan = @()
    foreach($cb in $spDynamic.Children) { if($cb.IsChecked) { $script:plan += $cb.Tag } }
    
    $script:capsWarnings = @()
    if (-not $script:SystemCaps.HasNvidia -and -not $script:SystemCaps.HasNVMe) {
        if ($script:plan -contains 'MSITuning') { $script:capsWarnings += "    [SKIP] MSITuning — Sin GPU NVIDIA ni NVMe" }
        $script:plan = @($script:plan | Where-Object { $_ -ne 'MSITuning' })
    } elseif (-not $script:SystemCaps.HasNvidia -and $script:SystemCaps.HasNVMe) {
        if ($script:plan -contains 'MSITuning') { $script:capsWarnings += "    [INFO] MSITuning — Sin NVIDIA, solo NVMe procesado" }
    }
    if ($script:SystemCaps.HasBattery -and $script:plan -contains 'InputTuning') { $script:capsWarnings += "    [WARN] InputTuning — Portátil detectado" }

    $irrPayloads = @()
    foreach ($p in $script:plan) {
        $node = $script:Config.Payloads.$p
        if ($null -ne $node -and $null -ne $node._meta -and $node._meta.Risk -eq 'IRR') { $irrPayloads += $p }
    }
    if ($irrPayloads.Count -gt 0 -and -not $script:ctx.Runtime.IsDryRun) {
        $irrList = ($irrPayloads | ForEach-Object { $pName = $_; $label = $script:Config.Payloads.$pName._meta.Label; "  [!] $pName — $label" }) -join "`n"
        $msg = "ATENCION — Las siguientes acciones son IRREVERSIBLES:`n`n$irrList`n`nNo se pueden deshacer. ¿Confirmas?"
        if ([System.Windows.MessageBox]::Show($msg, 'ALERTA', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning) -ne [System.Windows.MessageBoxResult]::Yes) {
            $txtConsole.Text += "`n> [ABORT] Despliegue cancelado."; return
        }
    }

    Beep-UI "action"
    $btnDeploy.IsEnabled=$false; $btnDeploy.Background="#444"; $pbProgress.Value=0

    if ($chkSafeCheckpoint.IsChecked -eq $true) {
        $txtConsole.AppendText("`n> [INFO] Creando punto de restauración del sistema...")
        $cpResult = Invoke-SafeCheckpoint
        if ($cpResult.Skipped) {
            if ([System.Windows.MessageBox]::Show($cpResult.Message + "`n`n¿Deseas continuar sin checkpoint?", 'Checkpoint no disponible', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning) -ne [System.Windows.MessageBoxResult]::Yes) {
                $txtConsole.AppendText("`n> [ABORT] Despliegue cancelado."); $btnDeploy.IsEnabled = $true; return
            }
            $txtConsole.AppendText("`n> [WARN] Continuando sin punto de restauración.")
        } elseif ($cpResult.Success) { $txtConsole.AppendText("`n> [OK]  $($cpResult.Message)")
        } else {
            if ([System.Windows.MessageBox]::Show($cpResult.Message + "`n`n¿Deseas continuar?", 'Error en Checkpoint', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning) -ne [System.Windows.MessageBoxResult]::Yes) {
                $txtConsole.AppendText("`n> [ABORT] Despliegue cancelado."); $btnDeploy.IsEnabled = $true; return
            }
            $txtConsole.AppendText("`n> [WARN] Continuando sin punto de restauración (error técnico).")
        }
    }

    $btnDeploy.Content = if($script:ctx.Runtime.IsDryRun){"[ SIMULANDO ]"}else{"[ INYECTANDO ]"}
    $txtStatus.Text = if($script:ctx.Runtime.IsDryRun){"MODO SIMULACION ACTIVADO..."}else{"ALTERANDO SISTEMA..."}
    $txtConsole.Text += "`n`n> [$(Get-Date -f 'HH:mm:ss')] $(if($script:ctx.Runtime.IsDryRun){'--- INICIANDO SIMULACION DRY-RUN ---'}else{'!!! DESPLIEGUE BARE-METAL INICIADO !!!'})"
    
    Write-PreAudit -Plan $script:plan -Console $txtConsole

    $highImpactWarnings = @{
        'DisableModernStandby' = if ($script:SystemCaps.HasBattery) { "DisableModernStandby en portátil: puede afectar gestión de energía." } else { $null }
        'TimerResolution' = "TimerResolution: Puede generar inestabilidad en software de audio profesional o VMs."
        'DisableWSearch'  = "DisableWSearch: La búsqueda desde el menú Inicio dejará de mostrar resultados indexados."
    }
    foreach ($warnPayload in $highImpactWarnings.Keys) {
        if ($warnPayload -in $script:plan -and $highImpactWarnings[$warnPayload]) { $txtConsole.AppendText("`n    [WARN] $warnPayload — $($highImpactWarnings[$warnPayload])") }
    }

    $svConsole.ScrollToEnd()

    if(-not $script:ctx.Runtime.IsDryRun) {
        $backupDir = Join-Path $DOCS_MANOLITO "backup_$(Get-Date -f 'yyyyMMdd_HHmmss')"
        New-Item $backupDir -ItemType Directory -Force | Out-Null
        & reg export "HKLM\SOFTWARE\Policies" "$backupDir\Policies_HKLM.reg" /y 2>$null
        & reg export "HKCU\Software\Policies" "$backupDir\Policies_HKCU.reg" /y 2>$null
    }

    if ($script:capsWarnings.Count -gt 0) { foreach ($w in $script:capsWarnings) { $txtConsole.Text += "`n$w" } }

    $script:logQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $script:rsHandle = Start-ManolitoRunspace -Plan $script:plan -Queue $script:logQueue

    $tDrain = New-Object System.Windows.Threading.DispatcherTimer
    $tDrain.Interval = [TimeSpan]::FromMilliseconds(50)
    $tDrain.Add_Tick({
        $msg = $null; $maxTick = 20; $count = 0; $isDone = $false
        while ($count -lt $maxTick -and $script:logQueue.TryDequeue([ref]$msg)) {
            if     ($msg.StartsWith('LOG:'))   { $txtConsole.Text += "`n$($msg.Substring(4))" }
            elseif ($msg.StartsWith('PROG:'))  { $pbProgress.Value = [int]$msg.Substring(5)  }
            elseif ($msg.StartsWith('STATE:')) { $script:rsStateJson = $msg.Substring(6)      }
            elseif ($msg.StartsWith('COUNT:')) { $lblStepsCounter.Content = $msg.Substring(6) }
            elseif ($msg.StartsWith('DONE:'))  { $isDone = $true; break }
            $count++
        }
        $svConsole.ScrollToEnd()
        
	if ($isDone) {
            $args[0].Stop()
            # Vaciar la cola completamente antes de cerrar (procesa el último 100%)
            while ($script:logQueue.TryDequeue([ref]$msg)) {
                if     ($msg.StartsWith('LOG:'))   { $txtConsole.Text += "`n$($msg.Substring(4))" }
                elseif ($msg.StartsWith('PROG:'))  { $pbProgress.Value = [int]$msg.Substring(5)  }
                elseif ($msg.StartsWith('COUNT:')) { $lblStepsCounter.Content = $msg.Substring(6) }
                elseif ($msg.StartsWith('STATE:')) { $script:rsStateJson = $msg.Substring(6)      }
            }
            $svConsole.ScrollToEnd()
            
            try { $script:rsHandle.PS.EndInvoke($script:rsHandle.Result) } catch {}
            $script:rsHandle.RS.Close(); $script:rsHandle.PS.Dispose(); $script:rsHandle = $null

            if ($script:rsStateJson) {
                try {
                    $rs = $script:rsStateJson | ConvertFrom-Json
                    $script:ctx.State.StepsOk       = [int]$rs.State.StepsOk
                    $script:ctx.State.StepsFail     = [int]$rs.State.StepsFail
                    $script:ctx.State.PendingReboot = [bool]$rs.State.PendingReboot
                    
                    $script:ctx.Tracking.RegDiff             = if ($rs.Tracking.RegDiff)             { @($rs.Tracking.RegDiff) }             else { @() }
                    $script:ctx.Tracking.PayloadsExecuted    = if ($rs.Tracking.PayloadsExecuted)    { @($rs.Tracking.PayloadsExecuted) }    else { @() }
                    $script:ctx.Tracking.IrreversibleActions = if ($rs.Tracking.IrreversibleActions) { @($rs.Tracking.IrreversibleActions) } else { @() }
                    
                    $script:ctx.Backups.ServicesStartup = ConvertTo-NativeHashtable $rs.Backups.ServicesStartup
                    $script:ctx.Backups.TasksState      = ConvertTo-NativeHashtable $rs.Backups.TasksState
                    $script:ctx.Backups.DNS             = ConvertTo-NativeHashtable $rs.Backups.DNS
                    $script:ctx.Backups.BCD             = ConvertTo-NativeHashtable $rs.Backups.BCD
                    $script:ctx.Backups.ActiveSetup     = ConvertTo-NativeHashtable $rs.Backups.ActiveSetup
                    $script:ctx.Backups.WindowsFeatures = ConvertTo-NativeHashtable $rs.Backups.WindowsFeatures
                    $script:ctx.Backups.Hosts           = $rs.Backups.Hosts
                    
                    $script:ctx.Results.Modules = if ($rs.Results.Modules) { @($rs.Results.Modules) } else { @() }
                } catch { $txtConsole.Text += "`n    [WARN] Deserialización de estado: $($_.Exception.Message)" }
                $script:rsStateJson = $null
            }

            if (-not $script:ctx.Runtime.IsDryRun) {
                $MANIFEST_PATH = Join-Path $DOCS_MANOLITO "manifest_$(Get-Date -f 'yyyyMMdd_HHmmss').json"
                $manifest = [ordered]@{
                    EngineVersion         = $script:Config.Manifest.Version
                    Timestamp             = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    Runlevel              = $script:ctx.Runtime.Runlevel
                    BackupServicesState   = $script:ctx.Backups.ServicesStartup
                    BackupTasksState      = $script:ctx.Backups.TasksState
                    BackupDNS             = $script:ctx.Backups.DNS
                    BackupHosts           = $script:ctx.Backups.Hosts
                    BackupBCD             = $script:ctx.Backups.BCD
                    BackupActiveSetup     = $script:ctx.Backups.ActiveSetup
                    BackupWindowsFeatures = $script:ctx.Backups.WindowsFeatures
                    RegDiff               = $script:ctx.Tracking.RegDiff
                    IrreversibleActions   = $script:ctx.Tracking.IrreversibleActions
                    Summary               = @{ StepsOk = $script:ctx.State.StepsOk; StepsFail = $script:ctx.State.StepsFail; Reboot = $script:ctx.State.PendingReboot; PayloadsExecuted = $script:ctx.Tracking.PayloadsExecuted }
                }
                $manifest | ConvertTo-Json -Depth 10 | Out-File $MANIFEST_PATH -Encoding UTF8
                $txtConsole.Text += "`n    [MANIFEST] Guardado en $MANIFEST_PATH"
                
                $htmlOut = Export-HtmlReport -OutputDir $DOCS_MANOLITO -Runlevel $script:ctx.Runtime.Runlevel -StepsOk $script:ctx.State.StepsOk -StepsFail $script:ctx.State.StepsFail -Modules $script:ctx.Results.Modules -Version $script:Config.Manifest.Version
                $txtConsole.Text += "`n    [HTML] Report -> $htmlOut"
            }

            if ($script:ctx.State.PendingReboot -and -not $script:ctx.Runtime.IsDryRun) {
                $txtStatus.Text = 'DESPLIEGUE EXITOSO. SE REQUIERE REINICIO'; $txtStatus.Foreground = '#FFB000'
            } else {
                $txtStatus.Text = if ($script:ctx.Runtime.IsDryRun) { 'SIMULACION COMPLETADA.' } else { 'DESPLIEGUE EXITOSO.' }; $txtStatus.Foreground = '#FF2079'
            }
            $txtConsole.Text += "`n    PROCESO FINALIZADO. Pasos OK=$($script:ctx.State.StepsOk), FAIL=$($script:ctx.State.StepsFail)"
            $svConsole.ScrollToEnd()
            
            $btnDeploy.Content = 'INICIAR'; $btnDeploy.Background = '#FF2079'; $btnDeploy.IsEnabled = $true
            $btnOpenLogs.IsEnabled = $true
            $script:ctx.Runtime.IsManifestRestore = $false
            
            if (-not $script:ctx.Runtime.IsDryRun) { $txtConsole.Text += "`n> [INFO] Revisa el informe HTML antes de reiniciar: $htmlOut" }
            $txtConsole.Text += "`n> [INFO] Transcript completo en: $(Join-Path $DOCS_MANOLITO 'transcript*.txt')"
            Beep-UI 'boot'

            if ($script:ctx.State.PendingReboot -and -not $script:ctx.Runtime.IsDryRun) {
                $rebootMsg = "El despliegue ha finalizado.`n`nUno o más cambios aplicados requieren reinicio para tener efecto.`n`n¿Deseas reiniciar ahora?"
                if ([System.Windows.MessageBox]::Show($rebootMsg, 'Reinicio requerido', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq [System.Windows.MessageBoxResult]::Yes) {
                    $txtConsole.AppendText("`n> [INFO] Reiniciando en 5 segundos...")
                    Start-Process shutdown.exe -ArgumentList '/r /t 5 /c "Manolito Engine — Reinicio post-despliegue"'
                } else { $txtConsole.AppendText("`n> [INFO] Reinicio pospuesto. Aplica manualmente cuando estés listo.") }
            }
        }
    })
    $tDrain.Start()
})

$window.Add_Closed({ try { Stop-Transcript } catch {}; try { $_mutex.ReleaseMutex(); $_mutex.Dispose() } catch {} })
$window.ShowDialog() | Out-Null
