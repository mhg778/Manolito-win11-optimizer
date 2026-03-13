<#
╔══════════════════════════════════════════════════════════════════╗
║              Manolito v1.4 — Windows 11 Education                ║
║       Optimizador modular: dev · gaming · estudio                ║
╠══════════════════════════════════════════════════════════════════╣
║  Modos     : Lite | DevEdu | Deep | Personalizado | Restore      ║
║  DryRun    : simula todos los cambios sin aplicar nada            ║
║  Skip      : -Skip HyperV SSD  (secciones separadas por espacio) ║
║  Interac.  : -Interactive  (menu de seleccion guiado)            ║
╠══════════════════════════════════════════════════════════════════╣
║  Ejemplos  : .\manolito.ps1 -Interactive                        ║
║              .\manolito.ps1 -Mode DevEdu                        ║
║              .\manolito.ps1 -Mode Deep -DryRun                  ║
╚══════════════════════════════════════════════════════════════════╝

.SYNOPSIS
    Manolito v1.4 — Optimizador Windows 11 Education
.PARAMETER Mode
    Preset: Lite | DevEdu | Deep | Restore (default: DevEdu)
.PARAMETER DryRun
    Simula todos los cambios sin aplicar nada al sistema.
.PARAMETER Skip
    Secciones a omitir (separadas por espacio):
    Activation, Updates, Defender, HyperV, Bloatware, OneDrive, Xbox,
    Power, UI, Telemetry, SSD, Privacy, Cleanup, OptionalFeatures,
    DiskSpace, ExplorerPerf, DevEnv
.PARAMETER Interactive
    Lanza el menu interactivo para elegir modo y opciones.
#>
[CmdletBinding()]
param(
    [ValidateSet("Lite","DevEdu","Deep","Restore")]
    [Parameter(HelpMessage="Preset de ejecucion: Lite | DevEdu | Deep | Restore")]
    [string]$Mode = "DevEdu",

    [Parameter(HelpMessage="Simula todos los cambios sin aplicar nada al sistema")]
    [switch]$DryRun,

    [ValidateSet(
        "Activation","Updates","Defender","HyperV","Bloatware","OneDrive","Xbox",
        "Power","UI","Telemetry","SSD","Privacy","Cleanup","OptionalFeatures",
        "DiskSpace","ExplorerPerf","DevEnv"
    )]
    [Parameter(HelpMessage="Secciones a omitir, separadas por espacio (ej: -Skip HyperV SSD)")]
    [string[]]$Skip = @(),

    [Parameter(HelpMessage="Lanza el menu interactivo para elegir modo y opciones")]
    [switch]$Interactive
)

#region ── CONFIGURACION DE USUARIO ───────────────────────────────────────────
#  ╔══════════════════════════════════════════════════════════════════╗
#  ║  LICENCIA WINDOWS — introduce tu clave de producto aqui         ║
#  ║  Formato: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX                         ║
#  ║  Si no usas activacion por clave, ejecuta con -Skip Activation  ║
#  ╚══════════════════════════════════════════════════════════════════╝
$ProductKey = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"

#endregion

#region ── BOOTSTRAP ──────────────────────────────────────────────────────────

# Encoding UTF-8 obligatorio (PS5.1 compatible)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'UTF8'

# Verificacion version PowerShell
$PSMajor = $PSVersionTable.PSVersion.Major
if ($PSMajor -lt 5) {
    $errMsg = "[ERROR] Se requiere PowerShell 5.1 o superior. Detectado: $PSMajor"
    [Console]::Error.WriteLine($errMsg)   # stderr para CI/CD y transcripts
    Write-Host $errMsg -ForegroundColor Red
    exit 1
}
$PS7Plus = ($PSMajor -ge 7)

# Elevacion automatica (reenvía todos los parametros)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Se requieren privilegios de administrador. Relanzando elevado..."
    $psExe   = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode `"$Mode`""
    if ($DryRun.IsPresent)      { $argList += " -DryRun" }
    if ($Interactive.IsPresent) { $argList += " -Interactive" }
    if ($Skip.Count -gt 0) {
        $skipArgs = $Skip | ForEach-Object { "`"$_`"" }
        $argList += " -Skip " + ($skipArgs -join " ")
    }
    Start-Process $psExe $argList -Verb RunAs
    exit
}

Set-StrictMode -Version Latest

# Proteccion contra ejecuciones simultaneas
$_mutex = [System.Threading.Mutex]::new($false, "Global\\ManolitoOptimizer")
if (-not $_mutex.WaitOne(0)) {
    Write-Host "[ERROR] Manolito ya esta en ejecucion en otra ventana. Espera a que termine." -ForegroundColor Red
    exit 1
}

#endregion

#region ── VERIFICACION DE ENTORNO ────────────────────────────────────────────

$OSInfo    = Get-CimInstance Win32_OperatingSystem
$WinBuild  = [int]$OSInfo.BuildNumber
$OSCaption = $OSInfo.Caption
#   SKU 121 = Windows 11 Education
#   SKU 122 = Windows 11 Education N
#   SKU   4 = Enterprise (permitido opcionalmente)
#   Caption se conserva solo para logging.
$OSSku     = [int]$OSInfo.OperatingSystemSKU
$IsEducationSku = ($OSSku -in @(121, 122))   # Education / Education N

$WIN11_BUILD_LATEST_TESTED = 26100
if ($WinBuild -gt $WIN11_BUILD_LATEST_TESTED -and $IsEducationSku) {
    Write-Warning "Build $WinBuild superior al ultimo testado ($WIN11_BUILD_LATEST_TESTED / Win11 24H2). Proceder con precaucion."
}

if ($WinBuild -lt 22000 -or -not $IsEducationSku) {
    $skuLabel = if ($OSSku -gt 0) { "SKU=$OSSku" } else { "SKU desconocido" }
    $errLines = @(
        "ERROR: Este script esta disenado exclusivamente para Windows 11 Education.",
        "SO detectado: $OSCaption (Build $WinBuild | $skuLabel)",
        "SKUs aceptados: 121 (Education), 122 (Education N).",
        "Abortando."
    )
    foreach ($e in $errLines) {
        [Console]::Error.WriteLine($e)    # stderr para CI/CD y transcripts
        Write-Host $e -ForegroundColor Red
    }
    $_mutex.ReleaseMutex()
    exit 1
}

#endregion

#region ── TRANSCRIPT Y RUTAS ─────────────────────────────────────────────────

$TranscriptPath = Join-Path $env:USERPROFILE "manolito_transcript_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
Start-Transcript -Path $TranscriptPath -Append -NoClobber -ErrorAction SilentlyContinue

$LogFile  = Join-Path $env:USERPROFILE "manolito_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$BackupDir = Join-Path $env:USERPROFILE "manolito_regbackup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

#endregion

#region ── CONSTANTES DE REGISTRO ────────────────────────────────────────

$REG_DATACOLLECTION    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
$REG_DATACOLLECTION2   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
$REG_WU_AU             = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$REG_DEFENDER_SPYNET   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"
$REG_COPILOT_USER      = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
$REG_COPILOT_MACHINE   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
$REG_EXPLORER_ADV      = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$REG_CDM               = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
$REG_APP_PRIVACY       = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore"
$REG_POLICIES_SYSTEM   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$REG_WORKPLACE_JOIN    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin"
$REG_MSA               = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount"
$REG_OOBE              = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"
$REG_SYSTEM_POLICIES   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"

#endregion

#region ── LISTAS DE DATOS COMPARTIDOS ────────────────────────────────────────

$PrivacyCapabilities = @(
    "location","contacts","appointments",
    "phoneCallHistory","radios","userNotificationListener"
)

$TelemetryTasksRestore = @(
    @{Path="\Microsoft\Windows\Application Experience";                  Name="Microsoft Compatibility Appraiser"},
    @{Path="\Microsoft\Windows\Application Experience";                  Name="ProgramDataUpdater"},
    @{Path="\Microsoft\Windows\Customer Experience Improvement Program"; Name="Consolidator"},
    @{Path="\Microsoft\Windows\Customer Experience Improvement Program"; Name="UsbCeip"}
)

#endregion

#region ── ESTADO GLOBAL ENCAPSULADO ─────────────────────────────────────

$ctx = @{
    StepsOk          = 0
    StepsFail        = 0
    StepNum          = 0
    AggressiveDisk   = $false
    RebootRequired   = [System.Collections.Generic.List[string]]::new()
    SkipList         = [System.Collections.Generic.List[string]]::new()
    ProvisionedCache = $null
    InstalledCache   = $null
    DryRunActions    = [System.Collections.Generic.List[string]]::new()
    FailedModules    = [System.Collections.Generic.List[string]]::new()
}

# Normalize: split any comma-joined strings (e.g. -Skip "HyperV,SSD" desde automatizacion)
foreach ($s in ($Skip -split '[,\s]+' | Where-Object { $_ })) { $ctx.SkipList.Add($s) }

#endregion

#region ── SECCIONES VALIDAS ──────────────────────────────────────────────────

$ValidSections = @(
    "Activation","Updates","Defender","HyperV","Bloatware","OneDrive","Xbox",
    "Power","UI","Telemetry","SSD","Privacy","Cleanup","OptionalFeatures",
    "DiskSpace","ExplorerPerf","DevEnv"
)

#endregion

#region ── LOG Y HELPERS BASICOS ──────────────────────────────────────────────

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Add-Content -LiteralPath $LogFile -Value $line -ErrorAction SilentlyContinue
    Write-Host $Message -ForegroundColor $Color
}

function Add-Skip {
    param([string]$Section)
    if ($Section -in $ValidSections) {
        if ($Section -notin $ctx.SkipList) { $ctx.SkipList.Add($Section) }
    } else {
        Write-Log "[WARN] Seccion '$Section' no reconocida en Add-Skip. Ignorada." "DarkYellow"
    }
}

function Test-Skip([string]$Section) { $ctx.SkipList -contains $Section }

#endregion

#region ── HELPERS DE REGISTRO Y SERVICIOS ────────────────────────────────────

function Set-RegistryValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    if ($DryRun.IsPresent) {
        $msg = "  [DRY-RUN] Reg: $Path\$Name = $Value"
        Write-Log $msg "DarkGray"
        $ctx.DryRunActions.Add($msg)
        return
    }
    try {
        $pathExists = Test-Path $Path
        if (-not $pathExists) {
            New-Item -Path $Path -Force | Out-Null
        } else {
            # Idempotencia: omitir escritura si el valor ya es el correcto
            if ($Name -eq "(Default)") {
                $currentItem = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
                if ($null -ne $currentItem -and $currentItem.GetValue('') -eq $Value) { return }
            } else {
                $current = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
                if ($null -ne $current -and $current.$Name -eq $Value) { return }
            }
        }
        if ($Name -eq "(Default)") {
            Set-Item -LiteralPath $Path -Value $Value -ErrorAction Stop
        } else {
            Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
        }
    } catch {
        Write-Log "  [WARN] No se pudo escribir $Path\$Name : $_" "DarkYellow"
    }
}

function Set-PrivacyConsent {
    param([ValidateSet("Allow","Deny")][string]$Value)
    foreach ($cap in $PrivacyCapabilities) {
        Set-RegistryValue "$REG_APP_PRIVACY\$cap" "Value" $Value "String"
    }
}

function Stop-ServiceSafe {
    param([string]$Name)
    if ($DryRun.IsPresent) {
        $msg = "  [DRY-RUN] Stop+Disable servicio: $Name"
        Write-Log $msg "DarkGray"
        $ctx.DryRunActions.Add($msg)
        return
    }
    $svc = Get-Service $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    Stop-Service $Name -Force -ErrorAction SilentlyContinue
    Set-Service  $Name -StartupType Disabled -ErrorAction SilentlyContinue
    # Timeout defensivo: confirmar parada en hasta 8 s sin bloquear el hilo
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline) {
        if ((Get-Service $Name -ErrorAction SilentlyContinue).Status -eq "Stopped") { break }
        Start-Sleep -Milliseconds 500
    }
    $finalStatus = (Get-Service $Name -ErrorAction SilentlyContinue).Status
    if ($finalStatus -ne "Stopped") {
        Write-Log "   [WARN] $Name no confirmo parada (estado: $finalStatus). Continua." "DarkYellow"
    } else {
        Write-Log "   Servicio $Name detenido y deshabilitado." "DarkGray"
    }
}

function Start-ServiceSafe {
    param([string]$Name)
    if ($DryRun.IsPresent) {
        $msg = "  [DRY-RUN] Enable+Start servicio: $Name"
        Write-Log $msg "DarkGray"
        $ctx.DryRunActions.Add($msg)
        return
    }
    $svc = Get-Service $Name -ErrorAction SilentlyContinue
    if ($svc) {
        Set-Service  $Name -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service $Name -ErrorAction SilentlyContinue
        Write-Log "   Servicio $Name habilitado e iniciado." "DarkGray"
    }
}

function Disable-ScheduledTaskSafe {
    param([string]$TaskPath, [string]$TaskName)
    if ($DryRun.IsPresent) {
        $msg = "  [DRY-RUN] Disable task: $TaskPath$TaskName"
        Write-Log $msg "DarkGray"
        $ctx.DryRunActions.Add($msg)
        return
    }
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task -and $task.State -ne 'Disabled') {
        $task | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        Write-Log "   Tarea $TaskName deshabilitada." "DarkGray"
    }
}

function Remove-AppxSafe {
    param([string]$Pattern)
    if ($DryRun.IsPresent) {
        $msg = "  [DRY-RUN] Remove-Appx $Pattern"
        Write-Log $msg "DarkGray"
        $ctx.DryRunActions.Add($msg)
        return
    }
    if ($null -ne $ctx.InstalledCache) {
        $ctx.InstalledCache | Where-Object { $_.Name -like $Pattern } |
            Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    } else {
        # Fallback: sin caché (p.ej. llamada aislada fuera del flujo principal)
        Get-AppxPackage -Name $Pattern -AllUsers -ErrorAction SilentlyContinue |
            Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    }
    if ($null -ne $ctx.ProvisionedCache) {
        $ctx.ProvisionedCache | Where-Object { $_.DisplayName -like $Pattern } |
            ForEach-Object {
                Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
            }
    }
}

#endregion

#region ── INVOKE-STEP CON DRYRUN CENTRALIZADO [L1] + AUTO-NUM [C3] ──────────

function Invoke-Step {
    param([string]$Section, [string]$Label, [scriptblock]$Action)

    if (Test-Skip $Section) {
        Write-Log "[$Section] OMITIDO por -Skip" "DarkYellow"
        return
    }

    $ctx.StepNum++
    $stepTag = "[$($ctx.StepNum.ToString('D2'))][$Section]"

    # Los helpers (Set-RegistryValue, Stop-ServiceSafe, etc.) ya comprueban $DryRun
    # individualmente para acumular sub-acciones en $ctx.DryRunActions.
    # Comandos externos sin helper (powercfg, DISM, Disable-WindowsOptionalFeature)
    # quedan protegidos gracias a este return centralizado.
    if ($DryRun.IsPresent) {
        $msg = "  [DRY-RUN] $stepTag $Label"
        Write-Log $msg "DarkGray"
        $ctx.DryRunActions.Add($msg)
        $ctx.StepsOk++   # contar como procesado para el resumen
        return           # <<< RETORNO REAL: ninguna acción del módulo se ejecuta
    }

    Write-Log "$stepTag $Label" "Cyan"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    try {
        & $Action
        $ctx.StepsOk++
    } catch {
        Write-Log "  [ERROR] $Section : $_" "Red"
        $ctx.StepsFail++
        $ctx.FailedModules.Add($Section)
    } finally {
        $ErrorActionPreference = $prevEAP
    }
}

#endregion

#region ── PREFLIGHT ──────────────────────────────────────────────────────────

function Test-PendingReboot {
    # Las dos primeras son sub-claves: Test-Path funciona correctamente.
    $cbsKey  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    $wuKey   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    # Test-Path sobre esa ruta siempre devuelve $false aunque el valor exista.
    # Corrección: comprobar con Get-ItemProperty en Session Manager.
    $smKey   = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    $pfroExists = $false
    try {
        $smProps = Get-ItemProperty -LiteralPath $smKey -ErrorAction Stop
        $pfro    = $smProps.PendingFileRenameOperations
        $pfroExists = ($null -ne $pfro) -and ($pfro.Count -gt 0)
    } catch { }
    return (Test-Path $cbsKey) -or (Test-Path $wuKey) -or $pfroExists
}

function Test-AVInterference {
    $mpPref = Get-MpPreference -ErrorAction SilentlyContinue
    if ($mpPref -and -not $mpPref.DisableRealtimeMonitoring) { return $true }
    $edr = Get-Process "csagent","falconctl","carbonblack" -ErrorAction SilentlyContinue
    return ($null -ne $edr -and $edr.Count -gt 0)
}

function Backup-Registry {
    New-Item $BackupDir -ItemType Directory -Force | Out-Null
    & reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer"      "$BackupDir\HKCU_Explorer.reg"          /y 2>$null
    & reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Search"        "$BackupDir\HKCU_Search.reg"            /y 2>$null
    & reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection"      "$BackupDir\HKLM_DataCollection.reg"    /y 2>$null
    & reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"       "$BackupDir\HKLM_WindowsUpdate.reg"     /y 2>$null
    & reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies"      "$BackupDir\HKLM_Policies.reg"          /y 2>$null
    Write-Log "Backup de registro selectivo creado en: $BackupDir" "Green"
}

#endregion

#region ── MODO RESTORE ──────────────────────────────────────────────────

function Invoke-RestoreMode {
    Write-Log "MODO RESTORE: revirtiendo cambios al estado Windows por defecto..." "Yellow"

    Write-Log "  Windows Update -> automatico..." "Cyan"
    Set-RegistryValue $REG_WU_AU "AUOptions"                     3
    Set-RegistryValue $REG_WU_AU "NoAutoUpdate"                  0
    Set-RegistryValue $REG_WU_AU "NoAutoRebootWithLoggedOnUsers" 0

    Write-Log "  Telemetria -> nivel basico (1)..." "Cyan"
    Set-RegistryValue $REG_DATACOLLECTION  "AllowTelemetry"      1
    Set-RegistryValue $REG_DATACOLLECTION2 "AllowTelemetry"      1
    Set-RegistryValue $REG_DATACOLLECTION2 "MaxTelemetryAllowed" 1

    Write-Log "  Servicios -> restaurando DiagTrack y SysMain..." "Cyan"
    Start-ServiceSafe "DiagTrack"
    Start-ServiceSafe "SysMain"

    Write-Log "  Advertising ID -> habilitado..." "Cyan"
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 1

    Write-Log "  Copilot -> restaurado..." "Cyan"
    Set-RegistryValue $REG_COPILOT_USER    "TurnOffWindowsCopilot" 0
    Set-RegistryValue $REG_COPILOT_MACHINE "TurnOffWindowsCopilot" 0

    Write-Log "  Permisos de privacidad -> Allow..." "Cyan"
    Set-PrivacyConsent -Value "Allow"

    Write-Log "  Cuentas -> restaurando permisos de cuenta Microsoft y Azure AD..." "Cyan"
    Set-RegistryValue $REG_POLICIES_SYSTEM "NoConnectedUser"          0
    Set-RegistryValue $REG_WORKPLACE_JOIN  "BlockAADWorkplaceJoin"    0
    Set-RegistryValue $REG_MSA             "DisableUserAuth"          0
    Set-RegistryValue $REG_OOBE            "DisablePrivacyExperience" 0

    Write-Log "  Windows AI / Recall -> restaurando..." "Cyan"
    Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 0
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 0
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 0

    # [F4/Restore] Reactiva tareas de telemetria
    Write-Log "  Tareas programadas -> reactivando telemetria..." "Cyan"
    foreach ($t in $TelemetryTasksRestore) {
        if (-not $DryRun.IsPresent) {
            $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
            if ($task -and $task.State -eq 'Disabled') {
                $task | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
                Write-Log "   Tarea $($t.Name) reactivada." "DarkGray"
            }
        } else {
            Write-Log "  [DRY-RUN] Enable task: $($t.Path)$($t.Name)" "DarkGray"
        }
    }

    Write-Log "================================================================" "Green"
    Write-Log "Restore completado. Reinicia para aplicar todos los cambios." "Green"
    Write-Log "NOTA: Las apps desinstaladas (bloatware/OneDrive) NO se restauran." "Yellow"
    Write-Log "NOTA: La activacion de Windows NO se revierte desde aqui." "Yellow"
    Write-Log "Log: $LogFile" "DarkGray"
    Stop-Transcript -ErrorAction SilentlyContinue
    $_mutex.ReleaseMutex()
    Read-Host "`nPulsa Enter para cerrar"
    exit 0
}

#endregion

#region ── MENU INTERACTIVO ───────────────────────────────────────────────────

if ($Interactive.IsPresent) {
    Clear-Host
    $menuText = @"
╔══════════════════════════════════════════════════════════════════╗
║           Manolito v1.4 — Optimizador Windows 11 Education       ║
╠══════════════════════════════════════════════════════════════════╣
║  [1] Lite        Estudio basico. Minimo impacto al sistema.      ║
║  [2] DevEdu      Dev + gaming + video.  ★ RECOMENDADO           ║
║  [3] Deep        Maxima limpieza. Incluye DISM (irreversible).   ║
║  [4] Personalizado  Elige que secciones omitir.                  ║
║  [5] DryRun      Simular DevEdu sin aplicar cambios.             ║
║  [6] Restore     Revertir cambios criticos al estado original.   ║
║  [0] Salir                                                       ║
╚══════════════════════════════════════════════════════════════════╝
"@
    Write-Log $menuText "Cyan"
    $choice = Read-Host "Elige [0-6]"
    switch ($choice) {
        "1" { $Mode = "Lite" }
        "2" { $Mode = "DevEdu" }
        "3" { $Mode = "Deep" }
        "4" {
            $Mode = "DevEdu"
            Write-Log "`nSecciones disponibles:" "Yellow"
            Write-Log "  Activation, Updates, Defender, HyperV, Bloatware, OneDrive, Xbox," "DarkGray"
            Write-Log "  Power, UI, Telemetry, SSD, Privacy, Cleanup, OptionalFeatures," "DarkGray"
            Write-Log "  DiskSpace, ExplorerPerf, DevEnv" "DarkGray"
            $customSkip = Read-Host "`nSecciones a OMITIR separadas por coma (Enter = ninguna)"
            if ($customSkip.Trim()) {
                $customSkip -split "\s*,\s*" | ForEach-Object { Add-Skip $_.Trim() }
            }
        }
        "5" { $Mode = "DevEdu"; $DryRun = [switch]::Present }
        "6" { $Mode = "Restore" }
        "0" { Stop-Transcript -ErrorAction SilentlyContinue; $_mutex.ReleaseMutex(); exit 0 }
        default {
            Write-Log "Opcion no valida. Saliendo." "Red"
            Stop-Transcript -ErrorAction SilentlyContinue
            $_mutex.ReleaseMutex()
            exit 1
        }
    }
}

#endregion

#region ── APLICAR SKIP POR MODO ──────────────────────────────────────────────

switch ($Mode) {
    "Lite" {
        foreach ($s in @("HyperV","Xbox","Power","SSD","DiskSpace")) { Add-Skip $s }
    }
    "Deep" {
        $ctx.AggressiveDisk = $true
    }
}

#endregion

#region ── INICIO DE EJECUCION ────────────────────────────────────────────────

if ($DryRun.IsPresent) {
    Write-Log "[DRY-RUN] Backup de registro omitido (sin cambios en simulacion)." "DarkYellow"
} else {
    Backup-Registry
}

if (Test-PendingReboot) {
    Write-Warning "[⚠️] Hay un reinicio pendiente detectado. Reinicia antes de continuar."
    $continueAny = Read-Host "Continuar de todos modos? [s/N]"
    if ($continueAny -notmatch "^[sS]$") {
        Stop-Transcript -ErrorAction SilentlyContinue
        $_mutex.ReleaseMutex()
        exit 2
    }
}

# Safe Mode: la mayoria de modulos fallan silenciosamente en Safe Mode
$_safeBoot = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Option" -ErrorAction SilentlyContinue
if ($null -ne $_safeBoot) {
    Write-Host "[ERROR] Manolito no debe ejecutarse en modo seguro. Reinicia en modo normal." -ForegroundColor Red
    $_mutex.ReleaseMutex()
    Stop-Transcript -ErrorAction SilentlyContinue
    exit 1
}

if (Test-AVInterference) {
    Write-Warning "[⚠️] Defender RealTime o EDR detectado. Algunas operaciones pueden fallar."
}

if (-not $DryRun.IsPresent) {
    $ctx.ProvisionedCache = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    $ctx.InstalledCache   = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
}

$dryLabel  = if ($DryRun.IsPresent)          { " (DRY-RUN)" }           else { "" }
$skipLabel = if ($ctx.SkipList.Count -gt 0)  { " | Skip: $($ctx.SkipList -join ',')" } else { "" }
$psLabel   = if ($PS7Plus) { "PS7+ (paralelo)" } else { "PS$PSMajor" }

Write-Log "================================================================" "Green"
Write-Log "Manolito v1.4 — Modo: $Mode$dryLabel$skipLabel | $psLabel" "Green"
Write-Log "OS: $OSCaption  |  Build: $WinBuild" "DarkGray"
Write-Log "Log: $LogFile  |  Transcript: $TranscriptPath" "DarkGray"
if (-not $DryRun.IsPresent) { Write-Log "Backup registro: $BackupDir" "DarkGray" }
Write-Log "================================================================" "Green"

# Despachar modo Restore
if ($Mode -eq "Restore") { Invoke-RestoreMode }

# La activacion real de Windows no es simulable; en DryRun solo genera ruido de error.
if ($DryRun.IsPresent -and -not (Test-Skip "Activation")) {
    Add-Skip "Activation"
    Write-Log "[DRY-RUN] Activation omitida automaticamente (no simulable; usa -Skip Activation para ocultar este aviso)." "DarkYellow"
}

#   Evita un error evitable en el primer uso antes de configurar ProductKey.
if (-not $DryRun.IsPresent -and -not (Test-Skip "Activation") -and ($ProductKey -match "^XXXXX")) {
    Add-Skip "Activation"
    Write-Log "[WARN] Activation omitida automaticamente: ProductKey aun es el placeholder. Edita \$ProductKey en el script o usa -Skip Activation para suprimir este aviso." "DarkYellow"
}

#endregion

#region ── MODULO 0: ACTIVACION ──────────────────────────────────────────

function Invoke-ModuleActivation {
    $slmgr = "$env:SystemRoot\System32\slmgr.vbs"

    # 0.1 Verificar si ya esta activado — /dlv contiene License Status y evita
    # una llamada /dli separada posterior (P3-v3.3: una sola invocacion VBScript)
    $licInfo    = & cscript.exe //Nologo "$slmgr" /dlv 2>&1 | Out-String
    $yaActivado = $licInfo -match "License Status:\s*Licensed" -or
                  $licInfo -match "Estado de licencia:\s*Con licencia"

    if ($yaActivado) {
        # Extraer canal de licencia para log informativo
        $channel = if ($licInfo -match 'License Description\s*:\s*(.+)') { $Matches[1].Trim() } else { 'desconocido' }
        Write-Log "   Windows ya activado. Canal: $channel" "DarkGray"
    } else {
        # 0.2 Validar formato de clave antes de inyectar
        if ($ProductKey -match "^XXXXX") {
            throw "Clave de producto no configurada. Edita `$ProductKey en el script antes de ejecutar."
        }
        if ($ProductKey -notmatch "^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$") {
            throw "Formato de clave invalido. Debe ser XXXXX-XXXXX-XXXXX-XXXXX-XXXXX (25 chars, mayusculas/numeros)."
        }

        # 0.3 Inyectar clave
        Write-Log "   Inyectando clave de producto..." "Yellow"
        Write-Log "   slmgr /ipk $($ProductKey.Substring(0,5))-****-****-****-*****" "DarkGray"
        $ipkResult = & cscript.exe //Nologo "$slmgr" /ipk $ProductKey 2>&1 | Out-String
        Write-Log "   $($ipkResult.Trim())" "DarkGray"
        if ($ipkResult -match "(?i)error|0x8") {
            throw "slmgr /ipk fallo: $($ipkResult.Trim())"
        }

        # Verificar conectividad antes de /ato
        Write-Log "   Verificando conectividad con servidores Microsoft..." "Yellow"
        $netOk = Test-NetConnection -ComputerName "activation.sls.microsoft.com" -Port 443 `
                     -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if (-not $netOk.TcpTestSucceeded) {
            throw "Sin conectividad a activation.sls.microsoft.com:443. Verifica tu conexion a internet."
        }

        # slmgr /ato con timeout 60 s
        Write-Log "   Activando contra servidores Microsoft (timeout 60 s)..." "Yellow"
        $atoProc = Start-Process "cscript.exe" -ArgumentList "//Nologo `"$slmgr`" /ato" `
                       -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\slmgr_ato.txt" `
                       -RedirectStandardError  "$env:TEMP\slmgr_ato_err.txt" -ErrorAction Stop
        # excepción en timeout. No usar el valor de retorno como bool: usar HasExited.
        try {
            Wait-Process -Id $atoProc.Id -Timeout 60 -ErrorAction Stop
        } catch [System.TimeoutException] {
            Stop-Process -Id $atoProc.Id -Force -ErrorAction SilentlyContinue
            throw "slmgr /ato excedio el timeout de 60 s. Verifica la conexion a internet."
        } catch {
            # Proceso ya terminó antes de Wait-Process (carrera): ignorar
        }
        if (-not $atoProc.HasExited) {
            Stop-Process -Id $atoProc.Id -Force -ErrorAction SilentlyContinue
            throw "slmgr /ato no termino en 60 s (HasExited=false). Verifica la conexion."
        }
        $atoResult  = (Get-Content "$env:TEMP\slmgr_ato.txt"     -ErrorAction SilentlyContinue) -join "`n"
        $atoErrResult = (Get-Content "$env:TEMP\slmgr_ato_err.txt" -ErrorAction SilentlyContinue) -join "`n"
        Remove-Item "$env:TEMP\slmgr_ato.txt","$env:TEMP\slmgr_ato_err.txt" -Force -ErrorAction SilentlyContinue
        Write-Log "   $($atoResult.Trim())" "DarkGray"
        if ($atoErrResult.Trim()) {
            Write-Log "   [slmgr stderr] $($atoErrResult.Trim())" "DarkYellow"
        }
        # Evaluar fallo combinando stdout + stderr
        $atoFullOutput = "$atoResult`n$atoErrResult"
        if ($atoFullOutput -match "(?i)error|0x8") {
            throw "slmgr /ato fallo: $($atoFullOutput.Trim())"
        }

        # 0.6 Verificar resultado con /dlv — si no aparece Licensed, es error duro
        $dlvResult = & cscript.exe //Nologo "$slmgr" /dlv 2>&1 | Out-String
        if ($dlvResult -match "Licensed|Con licencia") {
            Write-Log "   Windows activado correctamente." "Green"
        } else {
            throw "slmgr /ato ejecutado pero Windows NO figura como Licensed. Verifica manualmente: slmgr /dlv"
        }
    }

    # 0.7 Bloquear vinculacion a cuenta Microsoft personal
    Write-Log "   Bloqueando vinculacion a cuenta Microsoft personal..." "DarkGray"
    Set-RegistryValue $REG_POLICIES_SYSTEM "NoConnectedUser" 3

    # 0.8 Bloquear Azure AD
    Write-Log "   Bloqueando Azure AD / Work account join..." "DarkGray"
    Set-RegistryValue $REG_WORKPLACE_JOIN "BlockAADWorkplaceJoin" 1

    # 0.9 Deshabilitar proveedor MSA
    Write-Log "   Deshabilitando proveedor de identidad MSA del sistema..." "DarkGray"
    Set-RegistryValue $REG_MSA "DisableUserAuth" 1

    # 0.10 Suprimir OOBE
    Write-Log "   Suprimiendo prompts OOBE de cuenta en la nube..." "DarkGray"
    Set-RegistryValue $REG_OOBE "DisablePrivacyExperience" 1

    # 0.11 Bloquear banner Sign-in
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" `
        "ScoobeSystemSettingEnabled" 0

    Write-Log "   Bloqueo de cuentas en la nube aplicado." "Green"
}

Invoke-Step "Activation" "Activando Windows y bloqueando cuentas en la nube..." { Invoke-ModuleActivation }

#endregion

#region ── MODULO 1: WINDOWS UPDATE ──────────────────────────────────────

function Invoke-ModuleUpdates {
    Set-RegistryValue $REG_WU_AU "AUOptions"                       2
    Set-RegistryValue $REG_WU_AU "NoAutoUpdate"                    0
    Set-RegistryValue $REG_WU_AU "NoAutoRebootWithLoggedOnUsers"   1
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 0
}

Invoke-Step "Updates" "Configurando Windows Update a modo manual..." { Invoke-ModuleUpdates }

#endregion

#region ── MODULO 2: DEFENDER ────────────────────────────────────────────

function Invoke-ModuleDefender {
    Set-RegistryValue $REG_DEFENDER_SPYNET "SubmitSamplesConsent" 2
    Set-RegistryValue $REG_DEFENDER_SPYNET "SpynetReporting"      0
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" "DisableBlockAtFirstSeen" 1
}

Invoke-Step "Defender" "Cortando telemetria de Windows Defender..." { Invoke-ModuleDefender }

#endregion

#region ── MODULO 3: HYPER-V ─────────────────────────────────────────────

function Invoke-ModuleHyperV {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
    if ($feature -and $feature.State -eq "Enabled") {
        Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All `
            -NoRestart -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
        $ctx.RebootRequired.Add("HyperV")
        Write-Log "   Hyper-V desactivado. Requiere reinicio." "Yellow"
    } else {
        Write-Log "   Hyper-V ya estaba desactivado o no instalado." "DarkGray"
    }
}

Invoke-Step "HyperV" "Desactivando Hyper-V para liberar VMware/VirtualBox..." { Invoke-ModuleHyperV }

#endregion

#region ── MODULO 4: BLOATWARE ───────────────────────────────────────────

function Invoke-ModuleBloatware {
    $bloatware = @(
        "*YourPhone*", "*PhoneLink*", "*SkypeApp*", "*Microsoft.People*",
        "*MicrosoftTeams*", "*LinkedInforWindows*",
        "*ZuneMusic*", "*ZuneVideo*", "*Clipchamp*",
        "*Microsoft3DViewer*", "*Print3D*", "*MixedReality*", "*Paint3D*",
        "*BingSearch*", "*News*", "*Weather*", "*BingFinance*",
        "*BingSports*", "*BingTravel*", "*BingHealthAndFitness*",
        "*549981C3F5F10*",
        "*MicrosoftWindows.Client.WebExperience*",
        "*WindowsFeedbackHub*", "*GetHelp*", "*Getstarted*",
        "*MicrosoftOfficeHub*", "*Todos*",
        "*PowerAutomateDesktop*", "*MicrosoftSolitaireCollection*",
        "*WindowsMaps*", "*WindowsAlarms*", "*WindowsSoundRecorder*",
        "*MicrosoftStickyNotes*", "*Microsoft.Wallet*",
        "*WindowsCommunicationsApps*",
        "*ContentDeliveryManager*",
        "*Microsoft.OutlookForWindows*",       # Outlook nuevo (no Office)
        "*Microsoft.Copilot*",                 # Copilot standalone app (24H2)
        "*Microsoft.Windows.DevHome*",         # Dev Home (no usar si eres dev activo)
        "*Microsoft.MSPaint*",                 # Paint nuevo AI (si no lo usas)
        "*Clipchamp.Clipchamp*",               # Duplicado de *Clipchamp*
        "*Microsoft.BingSearch*"               # Bing Search redundante
    )

    if ($PS7Plus -and -not $DryRun.IsPresent) {
        $localProvCache = $ctx.ProvisionedCache
        $localInstCache = $ctx.InstalledCache
        $bloatware | ForEach-Object -Parallel {
            $pat        = $_
            $provCache  = $using:localProvCache
            $instCache  = $using:localInstCache
            # Filtrar desde caché: 0 llamadas WMI adicionales en PS7
            if ($null -ne $instCache) {
                $instCache | Where-Object { $_.Name -like $pat } |
                    Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            } else {
                Get-AppxPackage -Name $pat -AllUsers -ErrorAction SilentlyContinue |
                    Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            }
            if ($null -ne $provCache) {
                $provCache | Where-Object { $_.DisplayName -like $pat } |
                    ForEach-Object {
                        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
                    }
            }
        } -ThrottleLimit 4
    } else {
        foreach ($app in $bloatware) { Remove-AppxSafe $app }
    }
}

Invoke-Step "Bloatware" "Erradicando Bloatware de Microsoft..." { Invoke-ModuleBloatware }

#endregion

#region ── MODULO 4b: ONEDRIVE ───────────────────────────────────────────

function Invoke-ModuleOneDrive {
    # Matar procesos OneDrive antes de desinstalar
    Get-Process OneDrive,OneDriveSetup -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800

    # Desinstalar OneDrive via setup exe (instalacion clasica)
    $onedrivePaths = @(
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:SystemRoot\System32\OneDriveSetup.exe"
    )
    $found = $false
    foreach ($od in $onedrivePaths) {
        if (Test-Path $od) {
            Write-Log "   Desinstalando OneDrive exe ($od)..." "Yellow"
            $proc = Start-Process $od "/uninstall" -NoNewWindow -PassThru -Wait
            if ($proc.ExitCode -ne 0) {
                Write-Log "   [WARN] OneDriveSetup salio con codigo $($proc.ExitCode)" "DarkYellow"
            } else {
                Write-Log "   OneDrive exe desinstalado correctamente." "DarkGray"
            }
            $found = $true
            break
        }
    }
    # Eliminar tambien paquete Appx (Win11 moderno instala OneDrive como Appx)
    Remove-AppxSafe "*OneDrive*"
    if (-not $found) {
        Write-Log "   OneDrive exe no encontrado (ya desinstalado, se elimino via Appx o no presente)." "DarkGray"
    }
    # Limpiar residuos de perfil y ProgramData
    foreach ($f in @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive",
        "$env:PROGRAMDATA\Microsoft OneDrive",
        "$env:USERPROFILE\OneDrive"
    )) {
        if (Test-Path $f) { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue }
    }
    # Eliminar clave de registro de autoarranque
    Remove-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name "OneDrive" -ErrorAction SilentlyContinue
}

Invoke-Step "OneDrive" "OneDrive: Desinstalar y limpiar residuos..." { Invoke-ModuleOneDrive }

#endregion

#region ── MODULO 5: XBOX ────────────────────────────────────────────────

function Invoke-ModuleXbox {
    Remove-AppxSafe "*Xbox*"
    Remove-AppxSafe "*GamingApp*"
    Set-RegistryValue "HKCU:\System\GameConfigStore"                       "GameDVR_Enabled" 0
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR"    0
}

Invoke-Step "Xbox" "Eliminando Xbox y Game Bar..." { Invoke-ModuleXbox }

#endregion

#region ── MODULO 6: ENERGIA ─────────────────────────────────────────────

function Invoke-ModulePower {
    & powercfg.exe /hibernate off                  2>&1 | Out-Null
    & powercfg.exe /change standby-timeout-ac 120  2>&1 | Out-Null
    & powercfg.exe /change monitor-timeout-ac 15   2>&1 | Out-Null
}

Invoke-Step "Power" "Optimizando energia (sin Hibernacion, Suspension a 2 h)..." { Invoke-ModulePower }

#endregion

#region ── MODULO 7: INTERFAZ ────────────────────────────────────────────

function Invoke-ModuleUI {
    # Menu contextual clasico Win11
    Set-RegistryValue `
        "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" `
        "(Default)" "" "String"

    Set-RegistryValue $REG_EXPLORER_ADV "TaskbarAl" 0
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0
    Set-RegistryValue $REG_EXPLORER_ADV "TaskbarDa" 0
    Set-RegistryValue $REG_COPILOT_USER    "TurnOffWindowsCopilot" 1
    Set-RegistryValue $REG_COPILOT_MACHINE "TurnOffWindowsCopilot" 1
    Set-RegistryValue $REG_EXPLORER_ADV "TaskbarMn" 0

    $searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    Set-RegistryValue $searchPath "BingSearchEnabled"    0
    Set-RegistryValue $searchPath "SearchboxTaskbarMode" 1
    Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1

    Set-RegistryValue $REG_CDM "SubscribedContent-338389Enabled" 0
    Set-RegistryValue $REG_CDM "SubscribedContent-310093Enabled" 0
    Set-RegistryValue $REG_CDM "SubscribedContent-338388Enabled" 0
    Set-RegistryValue $REG_CDM "SubscribedContent-353698Enabled" 0
    Set-RegistryValue $REG_CDM "SilentInstalledAppsEnabled"      0
    Set-RegistryValue $REG_CDM "SystemPaneSuggestionsEnabled"    0
    Set-RegistryValue $REG_CDM "SoftLandingEnabled"              0
}

Invoke-Step "UI" "Restaurando interfaz clasica y limpiando distracciones..." { Invoke-ModuleUI }

#endregion

#region ── MODULO 8: TELEMETRIA ──────────────────────────────────────────

function Invoke-ModuleTelemetry {
    Set-RegistryValue $REG_DATACOLLECTION  "AllowTelemetry"      0
    Set-RegistryValue $REG_DATACOLLECTION2 "AllowTelemetry"      0
    Set-RegistryValue $REG_DATACOLLECTION2 "MaxTelemetryAllowed" 0

    Set-RegistryValue $REG_SYSTEM_POLICIES "EnableActivityFeed"    0
    Set-RegistryValue $REG_SYSTEM_POLICIES "PublishUserActivities" 0
    Set-RegistryValue $REG_SYSTEM_POLICIES "UploadUserActivities"  0

    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0

    foreach ($svc in @("DiagTrack","dmwappushservice","diagnosticshub.standardcollector.service")) {
        Stop-ServiceSafe $svc
    }

    # Tareas con nombres fijos conocidos
    $teleTasks = @(
        @{Path="\Microsoft\Windows\Application Experience\";                  Name="Microsoft Compatibility Appraiser"},
        @{Path="\Microsoft\Windows\Application Experience\";                  Name="ProgramDataUpdater"},
        @{Path="\Microsoft\Windows\Application Experience\";                  Name="StartupAppTask"},
        @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="Consolidator"},
        @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="UsbCeip"},
        @{Path="\Microsoft\Windows\Autochk\";                                 Name="Proxy"},
        @{Path="\Microsoft\Windows\DiskDiagnostic\";                          Name="Microsoft-Windows-DiskDiagnosticDataCollector"}
    )
    foreach ($t in $teleTasks) {
        Disable-ScheduledTaskSafe -TaskPath $t.Path -TaskName $t.Name
    }

    # Deshabilitar cualquier tarea activa en rutas CEIP conocidas (cubre nuevas tareas futuras)
    $ceipPaths = @(
        "\Microsoft\Windows\Application Experience\",
        "\Microsoft\Windows\Customer Experience Improvement Program\"
    )
    foreach ($ceipPath in $ceipPaths) {
        $dynTasks = Get-ScheduledTask -TaskPath $ceipPath -ErrorAction SilentlyContinue
        if ($dynTasks) {
            $dynTasks | Where-Object { $_.State -ne 'Disabled' } | ForEach-Object {
                $_ | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
                Write-Log "   [Dyn] Tarea deshabilitada: $($_.TaskName) en $ceipPath" "DarkGray"
            }
        }
    }
}

Invoke-Step "Telemetry" "Desactivando telemetria y diagnosticos del SO..." { Invoke-ModuleTelemetry }

#endregion

#region ── MODULO 9: PRIVACIDAD ──────────────────────────────────────────

function Invoke-ModulePrivacy {
    Set-PrivacyConsent -Value "Deny"
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC"               "PreventHandwritingDataSharing"  1
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports" "PreventHandwritingErrorReports" 1
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat"              "DisableInventory"               1
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config"        "AutoConnectAllowedOEM"          0

    # DisableAIDataAnalysis: deshabilita Recall (captura de pantalla AI)
    Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1
    # Deshabilitar el boton Copilot en taskbar (24H2 re-introduce esta clave)
    Set-RegistryValue $REG_EXPLORER_ADV "ShowCopilotButton" 0
    # Cloud Content / Consumer Features
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableSoftLanding"             1
    Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableCloudOptimizedContent"  1
    # Telemetria nivel policy adicional (24H2)
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\System" "AllowTelemetry" 0
    Write-Log "   Privacidad Win11 24H2+ (Recall/AI/Copilot) configurada." "DarkGray"
}

Invoke-Step "Privacy" "Endureciendo privacidad de aplicaciones..." { Invoke-ModulePrivacy }

#endregion

#region ── MODULO 10: SSD ────────────────────────────────────────────────

function Invoke-ModuleSSD {
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag"

    $trimOutput = & fsutil.exe behavior query DisableDeleteNotify 2>&1 | Out-String
    if ($trimOutput -match 'DisableDeleteNotify\s*=\s*1') {
        if ($trimOutput -match 'NTFS\s+DisableDeleteNotify\s*=\s*1') {
            & fsutil.exe behavior set DisableDeleteNotify NTFS 0 2>&1 | Out-Null
            Write-Log "   TRIM NTFS reactivado." "Yellow"
        }
        if ($trimOutput -match 'ReFS\s+DisableDeleteNotify\s*=\s*1') {
            & fsutil.exe behavior set DisableDeleteNotify ReFS 0 2>&1 | Out-Null
            Write-Log "   TRIM ReFS reactivado." "Yellow"
        }
        if ($trimOutput -notmatch '(NTFS|ReFS)\s+DisableDeleteNotify') {
            & fsutil.exe behavior set DisableDeleteNotify 0 2>&1 | Out-Null
            Write-Log "   TRIM reactivado." "Yellow"
        }
    } else {
        Write-Log "   TRIM ya estaba activo en todos los filesystems." "DarkGray"
    }

    Stop-ServiceSafe "SysMain"
}

Invoke-Step "SSD" "Optimizando SSD..." { Invoke-ModuleSSD }

#endregion

#region ── MODULO 11: LIMPIEZA ───────────────────────────────────────────

function Invoke-ModuleCleanup {
    $targets = @(
        @{Path="$env:TEMP";                                     Label="TEMP usuario"},
        @{Path="$env:SystemRoot\Temp";                          Label="TEMP sistema"},
        # Prefetch excluido de aqui: solo se limpia en modo Deep via bloque AggressiveDisk
        @{Path="$env:SystemRoot\SoftwareDistribution\Download"; Label="WU Cache"}
    )
    if ($ctx.AggressiveDisk) {
        Write-Log "   [Deep] Limpiando Prefetch (solo modo Deep)..." "Yellow"
        $prefetchPath = "$env:SystemRoot\Prefetch"
        if (Test-Path $prefetchPath) {
            $pbefore = (Get-ChildItem $prefetchPath -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum -as [long]
            Get-ChildItem $prefetchPath -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Log "   Prefetch: ~$([math]::Round(($pbefore/1MB),1)) MB liberados (apps tardaran mas en 1er arranque)." "DarkGray"
        }
    }
    foreach ($t in $targets) {
        if (Test-Path $t.Path) {
            $before   = (Get-ChildItem $t.Path -Recurse -Force -ErrorAction SilentlyContinue |
                         Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum -as [long]
            Get-ChildItem $t.Path -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -ne $LogFile } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            # $before puede ser mayor a lo efectivamente eliminado (archivos
            # bloqueados, ACL, errores silenciosos): usar la diferencia real.
            $after    = (Get-ChildItem $t.Path -Recurse -Force -ErrorAction SilentlyContinue |
                         Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum -as [long]
            $freedMB  = [math]::Round((($before - $after) / 1MB), 1)
            Write-Log "   $($t.Label): ~${freedMB} MB liberados" "DarkGray"
        }
    }

    $iconCache = "$env:LOCALAPPDATA\IconCache.db"
    if (Test-Path $iconCache) { Remove-Item $iconCache -Force -ErrorAction SilentlyContinue }

    $cbsLogs = "$env:SystemRoot\Logs\CBS"
    if (Test-Path $cbsLogs) {
        Get-ChildItem $cbsLogs -Filter "*.log" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Step "Cleanup" "Limpiando archivos temporales y caches..." { Invoke-ModuleCleanup }

#endregion

#region ── MODULO 12: OPTIONAL FEATURES ──────────────────────────────────

function Invoke-ModuleOptionalFeatures {
    $features = @("FaxServicesClientPackage","Printing-XPSServices-Features","WorkFolders-Client")
    $anyDisabled = $false
    foreach ($f in $features) {
        $feat = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
        if ($feat -and $feat.State -eq "Enabled") {
            Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction SilentlyContinue | Out-Null
            $anyDisabled = $true
            Write-Log "   Feature $f desactivada." "DarkGray"
        } else {
            Write-Log "   Feature $f ya estaba desactivada." "DarkGray"
        }
    }
    if ($anyDisabled) {
        $ctx.RebootRequired.Add("OptionalFeatures")
        Write-Log "   Requiere reinicio para aplicar cambios de features." "Yellow"
    }
}

Invoke-Step "OptionalFeatures" "Desactivando features opcionales innecesarias..." { Invoke-ModuleOptionalFeatures }

#endregion

#region ── MODULO 13: DISK SPACE PROFUNDO ────────────────────────────────

function Invoke-ModuleDiskSpace {
    if (-not $ctx.AggressiveDisk) {
        Write-Log "   [SKIP] DiskSpace profundo solo activo en modo Deep." "DarkGray"
        return
    }
    Write-Log "   ADVERTENCIA: Esta operacion es IRREVERSIBLE." "Yellow"
    Write-Log "   Limpiando WinSxS con DISM /ResetBase..." "Yellow"
    & Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart 2>&1 |
        ForEach-Object { Write-Log "   $_" "DarkGray" }
    if ($LASTEXITCODE -ne 0) {
        throw "DISM /ResetBase fallo con codigo $LASTEXITCODE"
    } else {
        $ctx.RebootRequired.Add("WinSxS-DISM")
        Write-Log "   DISM completado correctamente." "Green"
    }
}

Invoke-Step "DiskSpace" "Limpieza profunda WinSxS con DISM (solo modo Deep)..." { Invoke-ModuleDiskSpace }

#endregion

#region ── MODULO 14: EXPLORER PERFORMANCE ───────────────────────────────

function Invoke-ModuleExplorerPerf {
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2
}

Invoke-Step "ExplorerPerf" "Desactivando animaciones del sistema..." { Invoke-ModuleExplorerPerf }

#endregion

#region ── MODULO 15: DEV ENVIRONMENT ────────────────────────────────────

function Invoke-ModuleDevEnv {
    Set-RegistryValue $REG_EXPLORER_ADV "HideFileExt"     0
    Set-RegistryValue $REG_EXPLORER_ADV "Hidden"          1
    Set-RegistryValue $REG_EXPLORER_ADV "ShowSuperHidden" 1
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
    Write-Log "   ExecutionPolicy -> RemoteSigned (CurrentUser)" "DarkGray"
}

Invoke-Step "DevEnv" "Configurando entorno de desarrollo..." { Invoke-ModuleDevEnv }

#endregion

#region ── EXPLORER RESTART SEGURO ────────────────────────────────────────────

function Restart-ExplorerSafe {
    if ($DryRun.IsPresent) {
        $msg = "  [DRY-RUN] Explorer restart omitido en simulacion."
        Write-Log $msg "DarkGray"
        $ctx.DryRunActions.Add($msg)
        return
    }
    Write-Log "Reiniciando Explorer para aplicar cambios visuales..." "Yellow"

    $explorerProcs = Get-Process explorer -ErrorAction SilentlyContinue
    if ($explorerProcs) {
        $originalPIDs = $explorerProcs.Id
        $explorerProcs | Stop-Process -Force -ErrorAction SilentlyContinue

        $deadline = (Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $deadline) {
            $stillAlive = $originalPIDs | Where-Object {
                $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue)
            }
            if (-not $stillAlive) { break }
            Start-Sleep -Milliseconds 300
        }

        $notDead = $originalPIDs | Where-Object {
            $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue)
        }
        if ($notDead) {
            Write-Log "  [WARN] PIDs originales de Explorer no terminaron a tiempo: $($notDead -join ',')" "DarkYellow"
        }
    }
    Start-Process explorer.exe
}

Restart-ExplorerSafe

#endregion

#region ── FINALIZACION ───────────────────────────────────────────────────────

Write-Log "================================================================" "Green"
$summaryColor = if ($ctx.StepsFail -gt 0) { "Red" } else { "Green" }
Write-Log "Resumen: $($ctx.StepsOk) OK  |  $($ctx.StepsFail) errores" $summaryColor

if ($ctx.FailedModules.Count -gt 0) {
    Write-Log "Modulos con error: $($ctx.FailedModules -join ', ')" "Red"
}

if ($DryRun.IsPresent) {
    Write-Log "" "White"
    Write-Log "════════════════ RESUMEN DRY-RUN ════════════════" "Cyan"
    Write-Log "Total de acciones que se habrian aplicado: $($ctx.DryRunActions.Count)" "Cyan"
    Write-Log "─────────────────────────────────────────────────" "DarkGray"
    $ctx.DryRunActions | ForEach-Object { Write-Log $_ "DarkGray" }
    Write-Log "═════════════════════════════════════════════════" "Cyan"
    Write-Log "[DRY-RUN] Fin de la simulacion. Ningun cambio fue aplicado." "Green"
    Write-Log "Log: $LogFile  |  Transcript: $TranscriptPath" "DarkGray"
    Stop-Transcript -ErrorAction SilentlyContinue
    $_mutex.ReleaseMutex()
    exit 0
}

if ($ctx.RebootRequired.Count -gt 0) {
    Write-Log "Reinicio OBLIGATORIO para: $($ctx.RebootRequired -join ', ')" "Yellow"
}

Write-Log "Backup registro: $BackupDir" "DarkGray"
Write-Log "Log: $LogFile" "DarkGray"
Write-Log "Transcript: $TranscriptPath" "DarkGray"

Stop-Transcript -ErrorAction SilentlyContinue

if ($ctx.RebootRequired.Count -gt 0) {
    $respuesta = Read-Host "`nReinicio REQUERIDO para: $($ctx.RebootRequired -join ', '). Reiniciar ahora? [s/N]"
    if ($respuesta -match "^[sS]$") {
        Write-Log "Reiniciando el sistema..." "Yellow"
        $_mutex.ReleaseMutex()
        Restart-Computer -Force
        exit 0
    } else {
        Write-Log "Reinicio pospuesto. Recuerda reiniciar para aplicar todo." "Yellow"
    }
} else {
    Write-Log "No se requiere reinicio para los modulos ejecutados." "Green"
}

$_mutex.ReleaseMutex()
if ($ctx.StepsFail -gt 0) { exit 1 }
exit 0

#endregion
