<#
.COPYRIGHT
    Copyright (c) 2026 Manolito Project Contributors. Todos los derechos reservados.

.LICENSE
    Este script se distribuye bajo la licencia GNU GPLv3.
    Es software libre: puedes redistribuirlo y/o modificarlo bajo los terminos
    de la Licencia Publica General GNU publicada por la Free Software Foundation.

    ⚠️  ADVERTENCIA DE USO COMERCIAL (DOBLE LICENCIA):
    El uso de este software en entornos corporativos, empresariales, o por parte
    de Proveedores de Servicios Gestionados (MSP) con fines lucrativos esta sujeto
    a las estrictas obligaciones de la GPLv3 (liberacion de codigo fuente derivado).
    Para utilizar este software sin las restricciones de la GPLv3, se requiere la
    adquisicion de una Licencia Comercial. Contacta con el autor.
#>

<# 
╔══════════════════════════════════════════════════════════════════╗
║              Manolito v2.4-fixed — Windows 11 Education          ║
║       Optimizador modular: dev · gaming · estudio                ║
╠══════════════════════════════════════════════════════════════════╣
║  Modos     : Lite | DevEdu | Deep | Personalizado | Restore      ║
║  DryRun    : simula todos los cambios sin aplicar nada           ║
║  Skip      : -Skip HyperV SSD AdminTools (secciones separadas)   ║
║  Gaming    : -GamingMode (conserva Xbox + optimizaciones gaming) ║
║  DNS       : -SetSecureDNS (1.1.1.1 + 9.9.9.9)                   ║
║  Interac.  : -Interactive (menu + sub-menu toggles)              ║
╠══════════════════════════════════════════════════════════════════╣
║  Ejemplos  : .\manolito.ps1 -Interactive                         ║
║              .\manolito.ps1 -Mode Deep -GamingMode -SetSecureDNS ║
╚══════════════════════════════════════════════════════════════════╝

.SYNOPSIS
    Manolito v2.4 — Optimizador Windows 11 Education con toggles gaming/admin/DNS/OfflineOS
.PARAMETER Mode
    Preset: Lite | DevEdu | Deep | Restore (default: DevEdu)
.PARAMETER DryRun
    Simula todos los cambios sin aplicar nada al sistema.
.PARAMETER Skip
    Secciones a omitir (separadas por espacio):
    Activation,DeKMS,Updates,Defender,HyperV,Bloatware,OneDrive,Xbox,Power,UI,
    Telemetry,SSD,Privacy,Cleanup,OptionalFeatures,DiskSpace,ExplorerPerf,DevEnv,AdminTools
.PARAMETER GamingMode
    Conserva Xbox + optimizaciones gaming (HAGS, mouse latency). Desactiva desgamificación.
.PARAMETER SetSecureDNS
    Configura DNS 1.1.1.1 + 9.9.9.9 en adaptadores físicos Up.
.PARAMETER InstallWindhawk
    Instala Windhawk (Gestor de mods de UI) via winget.
.PARAMETER SkipAdminTools
    Omite instalación de herramientas sysadmin via winget.
.PARAMETER Interactive
    Menu interactivo con sub-menu de toggles.
#>

[CmdletBinding()]
param(
    [ValidateSet("Lite","DevEdu","Deep","Restore")]
    [Parameter(HelpMessage="Preset de ejecucion: Lite | DevEdu | Deep | Restore")]
    [string]$Mode = "DevEdu",

    [Parameter(HelpMessage="Simula todos los cambios sin aplicar nada al sistema")]
    [switch]$DryRun,

    [Parameter(HelpMessage="Omite confirmaciones interactivas (SCCM/Intune/tarea programada)")]
    [switch]$Force,

    [ValidateSet(
        "Activation","DeKMS","Updates","Defender","HyperV","Bloatware","OneDrive","Xbox",
        "Power","UI","Telemetry","SSD","Privacy","Cleanup","OptionalFeatures",
        "DiskSpace","ExplorerPerf","DevEnv","AdminTools","OfflineOS","DNS"
    )]
    [Parameter(HelpMessage="Secciones a omitir, separadas por espacio (ej: -Skip HyperV SSD)")]
    [string[]]$Skip = @(),

    [Parameter(HelpMessage="Conserva Xbox + optimizaciones gaming (HAGS, mouse latency)")]
    [switch]$GamingMode,

    [Parameter(HelpMessage="Configura DNS seguros 1.1.1.1 + 9.9.9.9 en adaptadores fisicos")]
    [switch]$SetSecureDNS,
    
    [Parameter(HelpMessage="Instala Windhawk (Gestor de mods de UI) via winget")]
    [switch]$InstallWindhawk,

    [Parameter(HelpMessage="Omite instalacion de herramientas sysadmin via winget")]
    [switch]$SkipAdminTools,

    [Parameter(HelpMessage="Lanza el menu interactivo con sub-menu de toggles")]
    [switch]$Interactive
)

# Flags auxiliares para evitar reasignar [switch] en PS 5.1
$script:IsDryRun = $DryRun.IsPresent
$script:UseGamingMode = $GamingMode.IsPresent
$script:UseSetSecureDNS = $SetSecureDNS.IsPresent
$script:UseInstallWindhawk = $InstallWindhawk.IsPresent


#region ── CONFIGURACION DE USUARIO ───────────────────────────────────────────
# LICENCIA WINDOWS — introduce tu clave aquí o usa el prompt interactivo
$script:ProductKey = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
#endregion

#region ── BOOTSTRAP ──────────────────────────────────────────────────────────
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'UTF8'

$PSMajor = $PSVersionTable.PSVersion.Major
if ($PSMajor -lt 5) {
    $errMsg = "[ERROR] Se requiere PowerShell 5.1 o superior. Detectado: $PSMajor"
    # FIX E1b: solo Write-Host para evitar duplicado en consola
    Write-Host $errMsg -ForegroundColor Red
    exit 1
}
$PS7Plus = ($PSMajor -ge 7)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Se requieren privilegios de administrador. Relanzando elevado..."
    $psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode `"$Mode`""
    if ($script:IsDryRun)      { $argList += " -DryRun" }
    if ($Interactive.IsPresent) { $argList += " -Interactive" }
    if ($script:UseGamingMode)  { $argList += " -GamingMode" }
    if ($script:UseSetSecureDNS){ $argList += " -SetSecureDNS" }
    if ($script:UseInstallWindhawk) { $argList += " -InstallWindhawk" } 
    if ($SkipAdminTools.IsPresent) { $argList += " -SkipAdminTools" }
    if ($Skip.Count -gt 0) {
        $skipArgs = $Skip | ForEach-Object { "`"$_`"" }
        $argList += " -Skip " + ($skipArgs -join " ")
    }
    Start-Process $psExe -ArgumentList $argList -Verb RunAs
    exit
}

Set-StrictMode -Version Latest

# Exit-Script en scope global: disponible antes del try{} (fix B3)
function Exit-Script {
    param([int]$Code = 0)
    exit $Code  # finally{} siempre libera mutex + Stop-Transcript
}

# Mutex — $_mutex y $acquired preinicializados para garantizar finally{} seguro
$_mutex   = $null
$acquired = $false

try {
    $_mutex = [System.Threading.Mutex]::new($false, "Global\ManolitoOptimizer")
    try {
        $acquired = $_mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $acquired = $true  # mutex recuperado del proceso anterior muerto
    }
    if (-not $acquired) {
        Write-Host "[ERROR] Manolito ya esta en ejecucion en otra ventana." -ForegroundColor Red
        exit 1  # No poseemos el mutex, no lo liberamos
    }

    $PS7Plus = ($PSMajor -ge 7)   # $PSMajor ya validado en bootstrap

    # Verificacion de entorno: Windows 11 Education
    $OSInfo    = Get-CimInstance Win32_OperatingSystem
    $WinBuild  = [int]$OSInfo.BuildNumber
    $OSCaption = $OSInfo.Caption
    $OSSku     = [int]$OSInfo.OperatingSystemSKU
    # SKUs soportados:
    #   Education     : 121, 122 (Education N)
    #   Pro           : 48, 49 (Pro N)
    #   Enterprise    : 27, 28 (Enterprise N), 84, 125 (Enterprise G/GN)
    $SupportedSkus   = @(121, 122, 48, 49, 27, 28, 84, 125)
    $IsEducationSku  = ($OSSku -in @(121, 122))
    $IsProSku        = ($OSSku -in @(48, 49))
    $IsEnterpriseSku = ($OSSku -in @(27, 28, 84, 125))
    $IsSupportedSku  = ($OSSku -in $SupportedSkus)

    $SKULabel = switch ($OSSku) {
        121  { "Education" }    122 { "Education N" }
        48   { "Pro" }          49  { "Pro N" }
        27   { "Enterprise" }   28  { "Enterprise N" }
        84   { "Enterprise G" } 125 { "Enterprise G N" }
        default { "SKU=$OSSku" }
    }

    $WIN11_BUILD_LATEST_TESTED = 26100
    if ($WinBuild -gt $WIN11_BUILD_LATEST_TESTED -and $IsSupportedSku) {
        Write-Warning "Build $WinBuild superior al ultimo testado ($WIN11_BUILD_LATEST_TESTED / Win11 24H2). Proceder con precaucion."
    }

    if ($WinBuild -lt 22000 -or -not $IsSupportedSku) {
        $skuLabel = $SKULabel
        $errLines = @(
            "ERROR: Edicion no compatible. Requerido: Windows 11 Education, Pro o Enterprise.",
            "SO detectado: $OSCaption (Build $WinBuild | $skuLabel)",
            "SKUs aceptados: 121/122 (Education), 48/49 (Pro), 27/28/84/125 (Enterprise).",
            "Abortando."
        )
        foreach ($e in $errLines) { Write-Host $e -ForegroundColor Red }
        Exit-Script 1
    }
    Write-Host "[Bootstrap] Edicion detectada: $OSCaption [$SKULabel] Build ${WinBuild}" -ForegroundColor DarkGray

    # FIX #23: Logs/backups centralizados en %USERPROFILE%\manolito\
    # FIX #23 (corregido): Documents\Manolito, no raiz de perfil
    $maniDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Manolito'
    if (-not (Test-Path $maniDir)) { New-Item -Path $maniDir -ItemType Directory -Force | Out-Null }
    $TranscriptPath = Join-Path $maniDir "transcript_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $LogFile        = Join-Path $maniDir "log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $BackupDir      = Join-Path $maniDir "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Start-Transcript -Path $TranscriptPath -Append -NoClobber -ErrorAction SilentlyContinue

    # Constantes de registro
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
    $REG_EDGE_POLICIES     = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    $REG_LONGPATHS         = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"

    # Listas compartidas
    $PrivacyCapabilities = @("location","contacts","appointments","phoneCallHistory","radios","userNotificationListener")
    $TelemetryTasks = @(
        @{Path="\Microsoft\Windows\Application Experience\"; Name="Microsoft Compatibility Appraiser"},
        @{Path="\Microsoft\Windows\Application Experience\"; Name="ProgramDataUpdater"},
        @{Path="\Microsoft\Windows\Application Experience\"; Name="StartupAppTask"},
        @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="Consolidator"},
        @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="UsbCeip"},
        @{Path="\Microsoft\Windows\Autochk\"; Name="Proxy"},
        @{Path="\Microsoft\Windows\DiskDiagnostic\"; Name="Microsoft-Windows-DiskDiagnosticDataCollector"}
    )

    # Estado global
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
        DeKMSCleaned     = $false
        DNSBackup        = @{}
    }

    foreach ($s in ($Skip -split '[,\s]+' | Where-Object { $_ })) { $ctx.SkipList.Add($s) }

    $ValidSections = @("Activation","DeKMS","Updates","Defender","HyperV","Bloatware","OneDrive","Xbox",
                      "Power","UI","Telemetry","SSD","Privacy","Cleanup","OptionalFeatures",
                      "DiskSpace","ExplorerPerf","DevEnv","AdminTools","OfflineOS","DNS")

    # Helpers
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


    function Set-RegistryValue {
        param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
        if ($script:IsDryRun) {
            $msg = "  [DRY-RUN] Reg: $Path\$Name = $Value"
            Write-Log $msg "DarkGray"
            $ctx.DryRunActions.Add($msg)
            return
        }
        try {
            if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
            if ($Name -eq "(Default)") {
                $current = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
                if ($null -ne $current -and $current.GetValue('') -eq $Value) { return }
                Set-Item -LiteralPath $Path -Value $Value -ErrorAction Stop
            } else {
                $current = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
                if ($null -ne $current -and $current.$Name -eq $Value) { return }
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
        if ($script:IsDryRun) {
            $msg = "  [DRY-RUN] Stop+Disable servicio: $Name"
            Write-Log $msg "DarkGray"
            $ctx.DryRunActions.Add($msg)
            return
        }
        $svc = Get-Service $Name -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service $Name -Force -ErrorAction SilentlyContinue
            Set-Service $Name -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "   Servicio $Name detenido y deshabilitado." "DarkGray"
        }
    }

    function Start-ServiceSafe {
        param([string]$Name)
        if ($script:IsDryRun) {
            $msg = "  [DRY-RUN] Enable+Start servicio: $Name"
            Write-Log $msg "DarkGray"
            $ctx.DryRunActions.Add($msg)
            return
        }
        $svc = Get-Service $Name -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service $Name -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service $Name -ErrorAction SilentlyContinue
            Write-Log "   Servicio $Name habilitado e iniciado." "DarkGray"
        }
    }

    function Disable-ScheduledTaskSafe {
        param([string]$TaskPath, [string]$TaskName)
        if ($script:IsDryRun) {
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

    function Enable-ScheduledTaskSafe {
        param([string]$TaskPath, [string]$TaskName)
        if ($script:IsDryRun) {
            $msg = "  [DRY-RUN] Enable task: $TaskPath$TaskName"
            Write-Log $msg "DarkGray"
            $ctx.DryRunActions.Add($msg)
            return
        }
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task -and $task.State -eq 'Disabled') {
            $task | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
            Write-Log "   Tarea $TaskName habilitada." "DarkGray"
        }
    }

    # FIX #9/#10/#30: try/catch por item — SilentlyContinue no captura terminating errors
    function Test-KMSValueIrregular {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
        $patterns = @(
            "digiboy","kmsdigital","kmspico","kms\.su","kms8\.msguides",
            "kms9\.msguides","kms\.cafe","kmsauto","vlmcsd","kms-r@1n",
            "auto\.kms","technet24","e8\.us\.to","kms\.xspace","zerothis",
            "127\.0\.0\.2","127\.0\.0\.3","0\.0\.0\.0","255\.255\.255\.255","192\.0\.2\."
        )
        foreach ($p in $patterns) { if ($Value -match $p) { return $true } }
        $isRFC1918 = $Value -match '^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)'
        $isInternal = ($Value -notmatch '\.') -and ($Value.Length -gt 0)
        if ($isRFC1918 -or $isInternal) { return $false }
        return $true
    }

    function Remove-AppxSafe {
        param([string]$Pattern)
        if ($script:IsDryRun) {
            $msg = "  [DRY-RUN] Remove-Appx $Pattern"
            Write-Log $msg "DarkGray"
            $ctx.DryRunActions.Add($msg)
            return
        }
        $pkgList = if ($null -ne $ctx.InstalledCache) {
            @($ctx.InstalledCache | Where-Object { $_.Name -like $Pattern })
        } else {
            @(Get-AppxPackage -Name $Pattern -AllUsers -ErrorAction SilentlyContinue)
        }
        foreach ($pkg in $pkgList) {
            try {
                $pkg | Remove-AppxPackage -AllUsers -ErrorAction Stop
                Write-Log "   [Appx] $($pkg.Name) desinstalado." "DarkGray"
            } catch {
                Write-Log "   [WARN] $($pkg.Name): no desinstalable (esperado): $($_.Exception.Message -replace "`n"," ")" "DarkYellow"
            }
        }
        if ($null -ne $ctx.ProvisionedCache) {
            $provList = @($ctx.ProvisionedCache | Where-Object { $_.DisplayName -like $Pattern })
            foreach ($prov in $provList) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                } catch {
                    Write-Log "   [WARN] Provisioned $($prov.DisplayName): $($_.Exception.Message -replace "`n"," ")" "DarkYellow"
                }
            }
        }
    }

    function Invoke-Step {
        param([string]$Section, [string]$Label, [scriptblock]$Action)
        if (Test-Skip $Section) {
            Write-Log "[$Section] OMITIDO por -Skip" "DarkYellow"
            return
        }
        $ctx.StepNum++
        $stepTag = "[$($ctx.StepNum.ToString('D2'))][$Section]"
        if ($script:IsDryRun) {
            $msg = "  [DRY-RUN] $stepTag $Label"
            Write-Log $msg "DarkGray"
            $ctx.DryRunActions.Add($msg)
            $ctx.StepsOk++
            return
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

    # Preflight functions
    function Test-PendingReboot {
        $cbsKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
        $wuKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        $smKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        $pfroExists = $false
        try {
            $smProps = Get-ItemProperty -LiteralPath $smKey -ErrorAction Stop
            $pfro = $smProps.PendingFileRenameOperations
            $pfroExists = ($null -ne $pfro) -and ($pfro.Count -gt 0)
        } catch {}
        return (Test-Path $cbsKey) -or (Test-Path $wuKey) -or $pfroExists
    }

    function Test-AVInterference {
        $mpPref = Get-MpPreference -ErrorAction SilentlyContinue
        if ($mpPref -and -not $mpPref.DisableRealtimeMonitoring) { return $true }
        $edr = Get-Process "csagent","falconctl","carbonblack" -ErrorAction SilentlyContinue
        return ($null -ne $edr -and $edr.Count -gt 0)
    }

    function Test-SafeMode {
        return $env:SAFEBOOT_OPTION  # Fix B2: variable oficial de Windows Safe Mode
    }

    function Backup-Registry {
        New-Item $BackupDir -ItemType Directory -Force | Out-Null
        & reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" "$BackupDir\HKCU_Explorer.reg" /y 2>$null
        & reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" "$BackupDir\HKCU_Search.reg" /y 2>$null
        & reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "$BackupDir\HKLM_DataCollection.reg" /y 2>$null
        & reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "$BackupDir\HKLM_WindowsUpdate.reg" /y 2>$null
        & reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies" "$BackupDir\HKLM_Policies.reg" /y 2>$null
        Write-Log "Backup de registro selectivo creado en: $BackupDir" "Green"
    }

    # Menu interactivo con sub-menu toggles
    $optWindhawk = $script:UseInstallWindhawk   # CLI default; el toggle lo puede sobreescribir
    if ($Interactive.IsPresent) {
        Clear-Host
        $menuText = @"
╔══════════════════════════════════════════════════════════════════╗
║           Manolito v2.4 — Optimizador Windows 11 Education       ║
╠══════════════════════════════════════════════════════════════════╣
║  [1] Lite        Estudio basico. Minimo impacto al sistema.      ║
║  [2] DevEdu      Dev + gaming + video.  ★ RECOMENDADO            ║
║  [3] Deep        Maxima limpieza. Incluye DISM (irreversible).   ║
║  [4] Personalizado  Elige que secciones omitir.                  ║
║  [5] DryRun      Simular DevEdu sin aplicar cambios.             ║
║  [6] Restore     Revertir cambios criticos al estado original.   ║
║  [0] Salir                                                       ║
╚══════════════════════════════════════════════════════════════════╝
"@
        $menuDone = $false
        do {
            # FIX Bug-B: remuestra menu en cada iteracion (incluido tras opcion invalida)
            Clear-Host
            Write-Host $menuText -ForegroundColor Cyan
            $choice = Read-Host "Elige [0-6]"
            switch ($choice) {
            "1" { $Mode = "Lite"; $menuDone = $true }
            "2" { $Mode = "DevEdu"; $menuDone = $true }
            "3" { $Mode = "Deep"; $menuDone = $true }
            "4" {
                $Mode = "DevEdu"
                $menuDone = $true
                Write-Log "`nSecciones disponibles:" "Yellow"
                Write-Log "  Activation, Updates, Defender, HyperV, Bloatware, OneDrive, Xbox," "DarkGray"
                Write-Log "  Power, UI, Telemetry, SSD, Privacy, Cleanup, OptionalFeatures," "DarkGray"
                Write-Log "  DiskSpace, ExplorerPerf, DevEnv, AdminTools" "DarkGray"
                $customSkip = Read-Host "`nSecciones a OMITIR separadas por coma (Enter = ninguna)"
                if ($customSkip.Trim()) {
                    $customSkip -split "\s*,\s*" | ForEach-Object { Add-Skip $_.Trim() }
                }
            }
            "5" { $Mode = "DevEdu"; $script:IsDryRun = $true; $menuDone = $true }
            "6" { $Mode = "Restore"; $menuDone = $true }
            "0" { Exit-Script 0 }
            default { Write-Log "[WARN] Opcion [$choice] invalida. Elige entre 0-6." "Red" }
            }
        } while (-not $menuDone)  # FIX #2

        # Sub-menu toggles SOLO para modos 1-4 (no DryRun ni Restore)
        if ($Mode -in @("Lite","DevEdu","Deep") -and -not $script:IsDryRun) {
            $optAdminTools   = $true
            $optDesgamificar = -not $script:UseGamingMode
            $optDNS          = $script:UseSetSecureDNS
            $optWindhawk     = $script:UseInstallWindhawk
            $optDeKMS        = $true
            if (Test-Skip "AdminTools") { $optAdminTools = $false }
            if (Test-Skip "DeKMS")      { $optDeKMS      = $false }

            $confirmToggle = $false
            do {
                Clear-Host
                $toggleText = @"
╔════════════════════════════════ TOGGLES ═══════════════════════════════╗
║  [1] Instalar Kit Sysadmin (Winget)    : [$(if ($optAdminTools) {'X'} else {' '})] SI / [ ] NO               ║
║  [2] Desgamificar (Eliminar Xbox)      : [$(if ($optDesgamificar) {'X'} else {' '})] SI / [ ] NO               ║
║  [3] Aplicar DNS Seguras (1.1.1.1)     : [$(if ($optDNS) {'X'} else {' '})] SI / [ ] NO               ║
║  [4] Instalar Windhawk (Mod Manager UI): [$(if ($optWindhawk) {'X'} else {' '})] SI / [ ] NO               ║
║  [5] Limpiar activador KMS (DeKMS)     : [$(if ($optDeKMS) {'X'} else {' '})] SI / [ ] NO               ║
║  [0] CONFIRMAR Y EJECUTAR                                              ║
╚════════════════════════════════════════════════════════════════════════╝
"@
                Write-Host $toggleText -ForegroundColor Cyan
                $toggleChoice = Read-Host "Elige [0-5]"
                switch ($toggleChoice) {
                    "1" { $optAdminTools = -not $optAdminTools }
                    "2" { $optDesgamificar = -not $optDesgamificar }
                    "3" { $optDNS = -not $optDNS }
                    "4" { $optWindhawk = -not $optWindhawk }
                    "5" { $optDeKMS = -not $optDeKMS }
                    "0" { $confirmToggle = $true }
                    default { Write-Host "  [WARN] Opcion invalida. Elige 0-5." -ForegroundColor DarkYellow }
                }
            } while (-not $confirmToggle)  # FIX #3/#4

            # Aplicar toggles como flags CLI equivalentes
            if ($optAdminTools) { $ctx.SkipList.Remove("AdminTools") | Out-Null } else { Add-Skip "AdminTools" }
            if ($optDeKMS)      { $ctx.SkipList.Remove("DeKMS")      | Out-Null } else { Add-Skip "DeKMS" }
            $script:UseGamingMode      = -not $optDesgamificar
            $script:UseSetSecureDNS    = $optDNS
            $script:UseInstallWindhawk = $optWindhawk
        }
    }

    # Aplicar Skip por modo
    switch ($Mode) {
        "Lite" { foreach ($s in @("HyperV","Xbox","Power","SSD","DiskSpace")) { Add-Skip $s } }
        "Deep" { $ctx.AggressiveDisk = $true }
    }

    # Aplicar flags CLI como skips
    if ($SkipAdminTools.IsPresent) { Add-Skip "AdminTools" }
    
    # E04: Check reboot ANTES del backup para evitar falso positivo
    # (reg export genera PendingFileRenameOperations que se detectarian como reboot pendiente)
    if ($Mode -ne "Restore" -and (Test-PendingReboot)) {
        Write-Warning "[⚠️] Hay un reinicio pendiente detectado. Reinicia antes de continuar."
        $continueAny = Read-Host "Continuar de todos modos? [s/N]"
        if ($continueAny -notmatch "^[sS]$") { Exit-Script 2 }
    }

    # FIX #7: No backup en Restore
    if ($script:IsDryRun) {
        Write-Log "[DRY-RUN] Backup de registro omitido (sin cambios en simulacion)." "DarkYellow"
    } elseif ($Mode -eq "Restore") {
        Write-Log "[INFO] Backup omitido en modo Restore." "DarkYellow"
    } else {
        Backup-Registry
    }

    # Fix B2: Safe Mode correcto
    if (Test-SafeMode) {
        Write-Host "[ERROR] Manolito no debe ejecutarse en modo seguro. Reinicia en modo normal." -ForegroundColor Red
        Exit-Script 1
    }

    if (Test-AVInterference) {
        Write-Warning "[⚠️] Defender RealTime o EDR detectado. Algunas operaciones pueden fallar."
    }

    if (-not $script:IsDryRun) {
        $ctx.ProvisionedCache = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        $ctx.InstalledCache = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    }

    # Cabecera
    $dryLabel = if ($script:IsDryRun) { " (DRY-RUN)" } else { "" }
    $skipLabel = if ($ctx.SkipList.Count -gt 0) { " | Skip: $($ctx.SkipList -join ',')" } else { "" }
    $psLabel = if ($PS7Plus) { "PS7+ (paralelo)" } else { "PS$PSMajor" }
    Write-Log "================================================================" "Green"
    Write-Log "Manolito v2.4-fixed — Modo: $Mode$dryLabel$skipLabel | $psLabel" "Green"
    Write-Log "Licencia: GNU GPLv3 (gratis uso personal/educativo | uso comercial requiere acuerdo)" "Yellow"
    Write-Log "OS: $OSCaption  |  Build: $WinBuild" "DarkGray"
    Write-Log "Log: $LogFile  |  Transcript: $TranscriptPath" "DarkGray"
    if (-not $script:IsDryRun) { Write-Log "Backup registro: $BackupDir" "DarkGray" }
    Write-Log "================================================================" "Green"

    # MODO RESTORE
    function Invoke-RestoreMode {
        Write-Log "MODO RESTORE: revirtiendo cambios al estado Windows por defecto..." "Yellow"

        Write-Log "  Windows Update -> automatico (AUOptions=4, default Windows)..." "Cyan"
        # FIX #17: Default real de Windows es 4, no 3
        Set-RegistryValue $REG_WU_AU "AUOptions" 4
        Set-RegistryValue $REG_WU_AU "NoAutoUpdate" 0
        Set-RegistryValue $REG_WU_AU "NoAutoRebootWithLoggedOnUsers" 0

        Write-Log "  Telemetria -> nivel basico (1)..." "Cyan"
        Set-RegistryValue $REG_DATACOLLECTION  "AllowTelemetry" 1
        Set-RegistryValue $REG_DATACOLLECTION2 "AllowTelemetry" 1
        Set-RegistryValue $REG_DATACOLLECTION2 "MaxTelemetryAllowed" 1

        Write-Log "  Servicios -> restaurando DiagTrack y SysMain..." "Cyan"
        Start-ServiceSafe "DiagTrack"
        Start-ServiceSafe "SysMain"

        Write-Log "  Advertising ID -> habilitado..." "Cyan"
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 1

        Write-Log "  Copilot -> restaurado..." "Cyan"
        Set-RegistryValue $REG_COPILOT_USER    "TurnOffWindowsCopilot" 0
        Set-RegistryValue $REG_COPILOT_MACHINE "TurnOffWindowsCopilot" 0

        Write-Log "  Copilot button -> restaurado..." "Cyan"
        Set-RegistryValue $REG_EXPLORER_ADV "ShowCopilotButton" 1

        Write-Log "  Permisos de privacidad -> Allow..." "Cyan"
        Set-PrivacyConsent -Value "Allow"

        Write-Log "  OfflineOS -> restaurando cuentas Microsoft y Azure AD..." "Cyan"
        Set-RegistryValue $REG_POLICIES_SYSTEM "NoConnectedUser" 0
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "NoMicrosoftAccount" 0
        Set-RegistryValue $REG_WORKPLACE_JOIN  "BlockAADWorkplaceJoin" 0
        Set-RegistryValue $REG_MSA             "DisableUserAuth" 0
        Set-RegistryValue $REG_OOBE            "DisablePrivacyExperience" 0
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 1

        Write-Log "  Windows AI / Recall -> restaurando..." "Cyan"
        Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 0
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 0
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 0

        Write-Log "  Edge -> restaurando politicas..." "Cyan"
        if (-not $script:IsDryRun) {
            Remove-ItemProperty -LiteralPath $REG_EDGE_POLICIES -Name "HubsSidebarEnabled" -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $REG_EDGE_POLICIES -Name "EdgeShoppingAssistantEnabled" -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $REG_EDGE_POLICIES -Name "StartupBoostEnabled" -ErrorAction SilentlyContinue
        } else {
            Write-Log "  [DRY-RUN] Remove-ItemProperty: Edge policies (HubsSidebar, Shopping, StartupBoost)" "DarkGray"
        }

        Write-Log "  DNS -> restaurando DHCP automatico..." "Cyan"
        if (-not $script:IsDryRun) {
            $restAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false })
            Write-Log "   Restaurando DNS en $($restAdapters.Count) adaptador(es)..." "DarkGray"
            foreach ($ra in $restAdapters) {
                if ($ctx.DNSBackup.ContainsKey($ra.Name) -and $ctx.DNSBackup[$ra.Name].IPv4.Count -gt 0) {
                    $allDNS = @($ctx.DNSBackup[$ra.Name].IPv4) + @($ctx.DNSBackup[$ra.Name].IPv6 | Where-Object { $_ })
                    Set-DnsClientServerAddress -InterfaceAlias $ra.Name -ServerAddresses $allDNS -ErrorAction SilentlyContinue
                    Write-Log "   DNS restaurados en $($ra.Name): $($allDNS -join ', ')" "DarkGray"
                } else {
                    Set-DnsClientServerAddress -InterfaceAlias $ra.Name -ResetServerAddresses -ErrorAction SilentlyContinue
                    Write-Log "   DNS $($ra.Name) -> DHCP automatico." "DarkGray"
                }
            }
        } else {
            Write-Log "  [DRY-RUN] Set-DnsClientServerAddress -ResetServerAddresses (todos los adaptadores activos)" "DarkGray"
        }

        Write-Log "  Tareas programadas -> reactivando telemetria..." "Cyan"
        foreach ($t in $TelemetryTasks) { Enable-ScheduledTaskSafe $t.Path $t.Name }

        Write-Log "================================================================" "Green"
        Write-Log "Restore completado. Reinicia para aplicar todos los cambios." "Green"
        Write-Log "NOTA: Las apps desinstaladas (bloatware/OneDrive) NO se restauran." "Yellow"
        Write-Log "NOTA: La activacion de Windows NO se revierte desde aqui." "Yellow"
        Write-Log "Log: $LogFile" "DarkGray"
        Exit-Script 0
    }

    # FIX #5: Confirmacion obligatoria antes de restaurar
    if ($Mode -eq "Restore") {
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║  ⚠  RESTAURACION AL ESTADO WINDOWS POR DEFECTO          ║" -ForegroundColor Yellow
        Write-Host "║  Revertira: WU, Telemetria, Servicios, DNS, Edge, etc.   ║" -ForegroundColor Yellow
        Write-Host "║  Las apps desinstaladas (bloatware/OneDrive) NO vuelven. ║" -ForegroundColor Yellow
        Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        $confirmRestore = Read-Host "Confirmar restauracion? [s/N]"
        if ($confirmRestore -notmatch "^[sS]$") {
            Write-Log "Restauracion cancelada por el usuario." "DarkYellow"
            Exit-Script 0
        }
        Invoke-RestoreMode
    }

    # UX Licencia: prompt solo si placeholder Y sin Skip Activation
    if (-not $script:IsDryRun -and -not (Test-Skip "Activation") -and ($script:ProductKey -match "^XXXXX")) {
        $promptKey = Read-Host "No se ha configurado clave. Introduce tu clave real (Enter para omitir):"
        if ($promptKey.Trim()) {
            $script:ProductKey = $promptKey.Trim()
            Write-Log "Licencia configurada via prompt interactivo." "Yellow"
        } else {
            Add-Skip "Activation"
            Write-Log "[INFO] Licencia omitida por usuario (equivalente a -Skip Activation)." "DarkYellow"
        }
    }

    # Despachar DryRun Activation auto-skip
    if ($script:IsDryRun -and -not (Test-Skip "Activation")) {
        Add-Skip "Activation"
        Write-Log "[DRY-RUN] Activation omitida automaticamente (no simulable)." "DarkYellow"
    }

#endregion

#region ── MÓDULOS 0-15 (existentes con fixes) ──────────────────────────────

    # MÓDULO DeKMS: Limpieza completa activadores KMS irregulares
    # Cubre: MAS, KMSpico, HEU KMS, kms.digiboy.ir, 127.0.0.2, vlmcsd
    # NO toca License State. Sin /upk ni /rearm.
    # KMS corporativo (RFC1918 / hostname interno) → preservado.
    function Invoke-ModuleDeKMS {
        $currentKMS = ""
        $dlvRaw = & cscript //Nologo "$env:SystemRoot\System32\slmgr.vbs" /dlv 2>&1 | Out-String
        if ($dlvRaw -match "KMS\s+machine\s+name[^:]*:\s*(.+)") { $currentKMS = $Matches[1].Trim() }
        elseif ($dlvRaw -match "Nombre.*maquina.*KMS[^:]*:\s*(.+)") { $currentKMS = $Matches[1].Trim() }

        $isIrregular = Test-KMSValueIrregular $currentKMS
        $isCorp = $false
        if ($currentKMS -and -not $isIrregular) {
            $isRFC1918  = $currentKMS -match '^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)'
            $isInternal = ($currentKMS -notmatch '\.') -and ($currentKMS.Length -gt 0)
            if ($isRFC1918 -or $isInternal) { $isCorp = $true }
        }
        if ($isCorp) {
            Write-Log "   [DeKMS] KMS corporativo ($currentKMS). Preservado." "Yellow"
            return
        }
        if ($currentKMS) { Write-Log "   [DeKMS] Servidor KMS detectado: $currentKMS" "Yellow" }
        else { Write-Log "   [DeKMS] No hay servidor KMS externo configurado." "DarkGray" }

        if ($script:IsDryRun) {
            $ctx.DryRunActions.Add("[DeKMS] Limpieza KMS simulada")
            Write-Log "  [DRY-RUN] DeKMS: limpieza simulada." "DarkGray"
            return
        }
        if ($currentKMS) {
            Write-Log "   AVISO: Servidor KMS a limpiar: $currentKMS" "Yellow"
            Write-Log "   License State NO se toca. Equipo sigue activo en grace period." "DarkGray"
            if ($WinBuild -ge 26040) { Write-Log "   Build ${WinBuild}: grace period KMS no renovable. Necesitaras clave MAK." "Yellow" }
            $isUnattended = $Force.IsPresent -or (-not [Environment]::UserInteractive) -or ($host.Name -ne "ConsoleHost")
            if (-not $isUnattended) {
                $confirm = Read-Host "   Confirmar limpieza KMS? [s/N]"
                if ($confirm -notmatch "^[sS]$") { Write-Log "   [DeKMS] Cancelado por el usuario." "Yellow"; return }
            } else {
                Write-Log "   [DeKMS] Modo desatendido: limpieza aprobada automaticamente." "DarkGray"
            }
        }

        $sppStopped = $false
        try {
            Stop-Service sppsvc -Force -ErrorAction SilentlyContinue
            $sppStopped = $true
            Write-Log "   [DeKMS] sppsvc detenido." "DarkGray"
            & cscript //Nologo "$env:SystemRoot\System32\slmgr.vbs" /ckms 2>&1 | Out-Null

            $SPP = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform"
            $cleaned = 0

            $rootP = Get-ItemProperty -LiteralPath $SPP -ErrorAction SilentlyContinue
            if ($null -ne $rootP -and $null -ne $rootP.PSObject.Properties['KeyManagementServiceName']) {
                $kmsValRoot = $rootP.PSObject.Properties['KeyManagementServiceName'].Value
                if (Test-KMSValueIrregular $kmsValRoot) {
                    try {
                        $rk = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                            "SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform",
                            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                            [System.Security.AccessControl.RegistryRights]::ChangePermissions)
                        if ($rk) {
                            $acl  = $rk.GetAccessControl()
                            $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                                [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
                                "FullControl","Allow")
                            $acl.SetAccessRule($rule); $rk.SetAccessControl($acl); $rk.Close()
                        }
                        Remove-ItemProperty -LiteralPath $SPP -Name "KeyManagementServiceName" -ErrorAction Stop
                        Remove-ItemProperty -LiteralPath $SPP -Name "KeyManagementServicePort" -ErrorAction SilentlyContinue
                        $cleaned++
                    } catch { Write-Log "   [DeKMS] HKLM SPP raiz: ACL bloqueada. slmgr /ckms ya actuo." "DarkYellow" }
                }
            }

            Get-ChildItem $SPP -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                if ($null -ne $p -and $null -ne $p.PSObject.Properties['KeyManagementServiceName']) {
                    $kmsValChild = $p.PSObject.Properties['KeyManagementServiceName'].Value
                    if (Test-KMSValueIrregular $kmsValChild) {
                        Remove-ItemProperty -LiteralPath $_.PSPath -Name "KeyManagementServiceName" -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $_.PSPath -Name "KeyManagementServicePort" -ErrorAction SilentlyContinue
                        $cleaned++
                        Write-Log "   [DeKMS] Eliminado en: $($_.PSChildName)" "DarkGray"
                    }
                }
            }

            try {
                New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -ErrorAction SilentlyContinue | Out-Null
                $hkuSPP = "HKU:\S-1-5-20\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform"
                if (Test-Path $hkuSPP) {
                    $hkuRoot = Get-ItemProperty -LiteralPath $hkuSPP -ErrorAction SilentlyContinue
                    if ($null -ne $hkuRoot -and $null -ne $hkuRoot.PSObject.Properties['KeyManagementServiceName']) {
                        $kmsValHku = $hkuRoot.PSObject.Properties['KeyManagementServiceName'].Value
                        if (Test-KMSValueIrregular $kmsValHku) {
                            Remove-ItemProperty -LiteralPath $hkuSPP -Name "KeyManagementServiceName" -ErrorAction SilentlyContinue
                            Remove-ItemProperty -LiteralPath $hkuSPP -Name "KeyManagementServicePort" -ErrorAction SilentlyContinue
                            $cleaned++; Write-Log "   [DeKMS] Raiz HKU S-1-5-20 limpiada." "DarkGray"
                        }
                    }
                    Get-ChildItem $hkuSPP -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                        $p2 = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                        if ($null -ne $p2 -and $null -ne $p2.PSObject.Properties['KeyManagementServiceName']) {
                            $kmsValP2 = $p2.PSObject.Properties['KeyManagementServiceName'].Value
                            if (Test-KMSValueIrregular $kmsValP2) {
                                Remove-ItemProperty -LiteralPath $_.PSPath -Name "KeyManagementServiceName" -ErrorAction SilentlyContinue
                                Remove-ItemProperty -LiteralPath $_.PSPath -Name "KeyManagementServicePort" -ErrorAction SilentlyContinue
                                $cleaned++
                            }
                        }
                    }
                }
            } catch {
                Write-Log "   [WARN] HKU\S-1-5-20 no accesible: $_" "DarkYellow"
            }

            foreach ($svc in @("KMS4k","SppExtComObjPatcher","vlmcsd","KMService","KMSELDI","KMSAutoS","KMSAuto")) {
                $s = Get-Service $svc -ErrorAction SilentlyContinue
                if ($s) {
                    Stop-Service $svc -Force -ErrorAction SilentlyContinue
                    & sc.exe delete $svc 2>&1 | Out-Null
                    Write-Log "   [DeKMS] Servicio eliminado: $svc" "Yellow"
                }
            }

            Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
                ($_.TaskName -match "HEU|KMSAuto|KMSpico|vlmcsd|KMSELDI") -or
                ($_.TaskPath -match "\\HEU|\\KMSAuto")
            } | ForEach-Object {
                $tp = if ($_.TaskPath) { $_.TaskPath } else { "\" }
                Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $tp -Confirm:$false -ErrorAction SilentlyContinue
                Write-Log "   [DeKMS] Tarea eliminada: $($_.TaskName)" "Yellow"
            }
            # B12: binarios conocidos de activadores piratas
            $kmsFiles = @(
                (Join-Path $env:SystemRoot "System32\SppExtComObjHook.dll"),
                (Join-Path $env:SystemRoot "SECOH-QAD.exe"),
                (Join-Path $env:SystemRoot "SECOH-QAD.dll"),
                (Join-Path $env:SystemRoot "System32\vlmcsd.exe"),
                (Join-Path $env:ProgramFiles "KMSpico\KMSpico.exe"),
                (Join-Path $env:ProgramFiles "KMSpico\Service_KMS.exe"),
                (Join-Path $env:ProgramData "KMSpico\KMSpico.exe")
            )
            foreach ($f in $kmsFiles) {
                if (Test-Path $f) {
                    try   { Remove-Item $f -Force -ErrorAction Stop; Write-Log "   [DeKMS] Binario eliminado: $f" "Yellow" }
                    catch { Write-Log "   [WARN] No se pudo eliminar $f : $_" "DarkYellow" }
                }
            }
            # B12: WMI Event Consumers maliciosos (KMS38, KMSpico)
            try {
                $badC = Get-CimInstance -Namespace "root\subscription" -ClassName "__EventConsumer" `
                    -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "KMS|SPP|vlmcsd|SECOH" }
                foreach ($c in $badC) {
                    Get-CimInstance -Namespace "root\subscription" -ClassName "__FilterToConsumerBinding" `
                        -ErrorAction SilentlyContinue | Where-Object { $_.Consumer.Name -eq $c.Name } |
                        Remove-CimInstance -ErrorAction SilentlyContinue
                    $c | Remove-CimInstance -ErrorAction SilentlyContinue
                    Write-Log "   [DeKMS] WMI Consumer eliminado: $($c.Name)" "Yellow"
                }
                if (-not $badC) { Write-Log "   [DeKMS] Sin WMI Consumers maliciosos." "DarkGray" }
            } catch { Write-Log "   [WARN] WMI scan: $_" "DarkYellow" }

            if ($cleaned -gt 0) {
                $ctx.DeKMSCleaned = $true
                Write-Log "   [DeKMS] $cleaned entrada(s) KMS eliminada(s). Activation forzara reactivacion MAK." "Green"
            }
            else { Write-Log "   [DeKMS] No se encontraron entradas KMS irregulares." "DarkGray" }
            Write-Log "   [INFO] License State intacto. Equipo activo en grace period." "DarkGray"
            if ($WinBuild -ge 26040) {
                Write-Log "   [WARN] Grace period no renovable en Build $WinBuild." "Yellow"
                Write-Log "   [INFO] Activacion permanente: Configuracion > Sistema > Activacion." "Yellow"
            }
        }
        finally {
            if ($sppStopped) {
                Start-Service sppsvc -ErrorAction SilentlyContinue
                Write-Log "   [DeKMS] sppsvc reiniciado." "DarkGray"
            }
        }
    }
    Invoke-Step "DeKMS" "Limpiando activadores KMS irregulares" { Invoke-ModuleDeKMS }

    function Invoke-ModuleActivation {
        $slmgr      = "$env:SystemRoot\System32\slmgr.vbs"
        $licInfo    = & cscript.exe //Nologo $slmgr /dlv 2>&1 | Out-String
        $yaActivado = $licInfo -match "License Status:\s*Licensed" -or $licInfo -match "Estado de licencia:\s*Con licencia"
        # C3: si DeKMS limpió un activador pirata, forzar reactivación con clave MAK
        if ($yaActivado -and -not $ctx.DeKMSCleaned) {
            $channel = if ($licInfo -match "License Description\s*:\s*(.+)") { $Matches[1].Trim() } else { "desconocido" }
            Write-Log "   Windows ya activado legitimamente. Canal: $channel" "DarkGray"
            return
        }
        if ($ctx.DeKMSCleaned) { Write-Log "   DeKMS limpio activador pirata. Forzando reactivacion MAK..." "Yellow" }
        if ($script:ProductKey -match "^XXXXX") { throw "Clave no configurada." }
        if ($script:ProductKey -notmatch "^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$") {
            throw "Formato de clave invalido."
        }
        Write-Log "   Inyectando clave de producto..." "Yellow"
        $ipkResult = & cscript.exe //Nologo $slmgr /ipk $script:ProductKey 2>&1 | Out-String
        Write-Log "   slmgr /ipk $($script:ProductKey.Substring(0,5))-****-****-****-*****" "DarkGray"
        if ($ipkResult -match "(?i)error|0x8") { throw "slmgr /ipk fallo: $ipkResult" }
        # B05: KMS local (RFC1918/hostname) no requiere check WAN
        $dlvCheck = & cscript.exe //Nologo $slmgr /dlv 2>&1 | Out-String
        $kmsHost  = if ($dlvCheck -match "KMS machine name[^:]*:\s*(.+)") { $Matches[1].Trim() } else { "" }
        $kmsIsLAN = ($kmsHost -match "^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)") -or
                    (($kmsHost -notmatch "\.") -and $kmsHost.Length -gt 0)
        if (-not $kmsIsLAN) {
            Write-Log "   Verificando conectividad WAN..." "Yellow"
            $actNetOk = $false
            try {
                $actc  = [System.Net.Sockets.TcpClient]::new()
                $actar = $actc.BeginConnect("activation.sls.microsoft.com", 443, $null, $null)
                $actNetOk = $actar.AsyncWaitHandle.WaitOne(3000)
                $actc.Close()
            } catch { $actNetOk = $false }
            if (-not $actNetOk) { throw "Sin conectividad a activation.sls.microsoft.com:443." }
        } else {
            Write-Log "   KMS local ($kmsHost) — check WAN omitido." "DarkGray"
        }
        Write-Log "   Activando (timeout 15 s)..." "Yellow"
        $tmpOut  = Join-Path $env:TEMP "slmgr_ato_$PID.txt"
        $tmpErr  = Join-Path $env:TEMP "slmgr_ato_err_$PID.txt"
        $atoProc = Start-Process "cscript.exe" -ArgumentList "//Nologo `"$slmgr`" /ato" `
            -NoNewWindow -PassThru -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr -ErrorAction Stop
        try { Wait-Process -Id $atoProc.Id -Timeout 15 -ErrorAction Stop }
        catch [System.TimeoutException] {
            Stop-Process -Id $atoProc.Id -Force -ErrorAction SilentlyContinue
            throw "slmgr /ato excedio timeout 15 s."
        }
        if (-not $atoProc.HasExited) {
            Stop-Process -Id $atoProc.Id -Force -ErrorAction SilentlyContinue
            throw "slmgr /ato no termino (HasExited=false)."
        }
        $atoResult = (Get-Content $tmpOut -ErrorAction SilentlyContinue) -join "`n"
        $atoErr    = (Get-Content $tmpErr -ErrorAction SilentlyContinue) -join "`n"
        Remove-Item $tmpOut,$tmpErr -Force -ErrorAction SilentlyContinue
        Write-Log "   $atoResult" "DarkGray"
        if ($atoErr.Trim()) { Write-Log "   [stderr] $atoErr" "DarkYellow" }
        if ("$atoResult`n$atoErr" -match "(?i)error|0x8") { throw "slmgr /ato fallo." }
        $dlvResult = & cscript.exe //Nologo $slmgr /dlv 2>&1 | Out-String
        if ($dlvResult -match "Licensed|Con licencia") {
            Write-Log "   Windows activado correctamente." "Green"
            Write-Log "   [INFO] KMS: verifica accesibilidad del servidor desde esta red." "DarkYellow"
        } else { throw "Activacion ejecutada pero NO Licensed. Verifica: slmgr /dlv" }
    }
        Invoke-Step "Activation" "Activando Windows..." { Invoke-ModuleActivation }


    # MÓDULO OfflineOS: Bloqueo de identidad cloud — siempre ejecutado salvo -Skip OfflineOS
    function Invoke-ModuleOfflineOS {
        if ($IsProSku -or $IsEnterpriseSku) {
            Write-Log "   [OfflineOS] Pro/Enterprise: restricciones MSA omitidas." "Yellow"
            Write-Log "   [INFO] Usa GPO/Intune para gestionar identidades en entornos gestionados." "DarkGray"
            return
        }
        Write-Log "   Bloqueando vinculacion a cuenta Microsoft personal..." "DarkGray"
        Set-RegistryValue $REG_POLICIES_SYSTEM "NoConnectedUser" 3
        Write-Log "   Bloqueando Azure AD / Work account join..." "DarkGray"
        Set-RegistryValue $REG_WORKPLACE_JOIN "BlockAADWorkplaceJoin" 1
        Write-Log "   Deshabilitando proveedor de identidad MSA..." "DarkGray"
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "NoMicrosoftAccount" 3
        Set-RegistryValue $REG_MSA "DisableUserAuth" 1
        Write-Log "   Suprimiendo prompts OOBE de cuenta en la nube..." "DarkGray"
        Set-RegistryValue $REG_OOBE "DisablePrivacyExperience" 1
        Write-Log "   Bloqueando banner Sign-in (Scoobe)..." "DarkGray"
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 1
        Write-Log "   Identidad cloud aislada correctamente." "Green"
    }

    Invoke-Step "OfflineOS" "Aislando identidad cloud (AAD/MSA/OOBE)..." { Invoke-ModuleOfflineOS }

    function Invoke-ModuleUpdates {
        Set-RegistryValue $REG_WU_AU "AUOptions" 2
        Set-RegistryValue $REG_WU_AU "NoAutoUpdate" 0
        Set-RegistryValue $REG_WU_AU "NoAutoRebootWithLoggedOnUsers" 1
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 0
    }
    Invoke-Step "Updates" "Configurando Windows Update a modo manual..." { Invoke-ModuleUpdates }

    function Invoke-ModuleDefender {
        Set-RegistryValue $REG_DEFENDER_SPYNET "SubmitSamplesConsent" 2
        Set-RegistryValue $REG_DEFENDER_SPYNET "SpynetReporting" 0
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" "DisableBlockAtFirstSeen" 1
    }
    Invoke-Step "Defender" "Cortando telemetria de Windows Defender..." { Invoke-ModuleDefender }

    function Invoke-ModuleHyperV {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
        if ($feature -and $feature.State -eq "Enabled") {
            Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart -ErrorAction SilentlyContinue | Out-Null
            $ctx.RebootRequired.Add("HyperV")
            Write-Log "   Hyper-V desactivado. Requiere reinicio." "Yellow"
        } else {
            Write-Log "   Hyper-V ya desactivado." "DarkGray"
        }
    }
    Invoke-Step "HyperV" "Desactivando Hyper-V..." { Invoke-ModuleHyperV }

    function Invoke-ModuleBloatware {
        # Education base
        $bloatware_edu = @(
            "*YourPhone*","*PhoneLink*","*SkypeApp*","*Microsoft.People*","*MicrosoftTeams*","*LinkedInforWindows*",
            "*ZuneMusic*","*ZuneVideo*","*Clipchamp*","*Microsoft3DViewer*","*Print3D*","*MixedReality*","*Paint3D*",
            "*BingSearch*","*News*","*Weather*","*BingFinance*","*BingSports*","*BingTravel*","*BingHealthAndFitness*",
            "*549981C3F5F10*","*MicrosoftWindows.Client.WebExperience*","*WindowsFeedbackHub*","*GetHelp*","*Getstarted*",
            "*MicrosoftOfficeHub*","*Todos*","*PowerAutomateDesktop*","*MicrosoftSolitaireCollection*","*WindowsMaps*",
            "*WindowsAlarms*","*WindowsSoundRecorder*","*MicrosoftStickyNotes*","*Microsoft.Wallet*","*WindowsCommunicationsApps*",
            "*ContentDeliveryManager*","*Microsoft.OutlookForWindows*","*Microsoft.Copilot*","*Microsoft.Windows.DevHome*",
            "*Microsoft.MSPaint*","*Microsoft.BingSearch*"
        )
        # Pro/Enterprise consumer zoo (preinstalado por Microsoft en Pro y superior)
        $bloatware_pro = @(
            "*SpotifyAB.SpotifyMusic*",        # Spotify
            "*BytedancePte.TikTok*",           # TikTok
            "*Instagram*",                     # Instagram
            "*Facebook*",                      # Facebook
            "*Disney*",                        # Disney+
            "*AmazonVideo*","*PrimeVideo*",    # Prime Video
            "*Netflix*",                       # Netflix
            "*Clipchamp*",                     # Clipchamp (ya en edu, redundante pero seguro)
            "*CandyCrush*",                    # Candy Crush saga/friends/soda
            "*BubbleWitch*",                   # Bubble Witch
            "*Minecraft*",                     # Minecraft launcher
            "*Roblox*",                        # Roblox
            "*EclipseManager*",                # Eclipse Manager (adware)
            "*ActiproSoftware*",               # Actipro code samples
            "*AdobeSystemsIncorporated.AdobePhotoshopExpress*",
            "*Duolingo*",                      # Duolingo
            "*PandoraMedia*",                  # Pandora
            "*Shazam*",                        # Shazam
            "*iHeartRadio*",                   # iHeart Radio
            "*Twitter*","*XCorp*",             # Twitter/X
            "*TikTokPte*",                     # TikTok alt package
            "*HiddenCity*",                    # Hidden City
            "*Phototastic*",                   # Phototastic Collage
            "*Keeper*",                        # Keeper Password
            "*LenovoCompanion*","*McAfee*",    # OEM adware
            "*EsportsGameService*",            # Microsoft Gaming extras
            "*MSN*"                            # MSN portal apps
        )
        # Unir según edicion detectada
        $bloatware = $bloatware_edu
        if ($IsProSku -or $IsEnterpriseSku) {
            $bloatware = $bloatware_edu + $bloatware_pro
            Write-Log "   [Bloatware] Edicion Pro/Enterprise: lista extendida ($($bloatware.Count) patrones)." "DarkGray"
        } else {
            Write-Log "   [Bloatware] Edicion Education: lista base ($($bloatware.Count) patrones)." "DarkGray"
        }
        if ($PS7Plus) {
            $localProv = $ctx.ProvisionedCache
            $localInst = $ctx.InstalledCache
            # FIX Bug-A: try/catch por item dentro del bloque -Parallel
            # (Remove-AppxSafe no es accesible desde runspaces separados de PS7+)
            $bloatware | ForEach-Object -Parallel {
            $pat  = $_
            $inst = $using:localInst
            $pkgs = if ($null -ne $inst) { @($inst | Where-Object { $_.Name -like $pat }) }
                    else { @(Get-AppxPackage -Name $pat -AllUsers -ErrorAction SilentlyContinue) }
            foreach ($pkg in $pkgs) {
                try   { $pkg | Remove-AppxPackage -AllUsers -ErrorAction Stop }
                catch {
                    # 0x80070032 = SystemApp protegida, no eliminable — silenciar
                    if ($_.Exception.Message -notmatch "0x80070032") {
                        $lf  = $using:LogFile
                        $msg = "[$(Get-Date -f 'HH:mm:ss')] [WARN-Parallel] $($pkg.Name): $($_.Exception.Message -replace "`n"," ")"
                        if ($lf) { Add-Content -LiteralPath $lf -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue }
                        Write-Warning $msg
                    }
                }
            }
        } -ThrottleLimit 4
        if ($null -ne $localProv) {
            foreach ($pat in $bloatware) {
                @($localProv | Where-Object { $_.DisplayName -like $pat }) | ForEach-Object {
                    try {
                        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null
                        Write-Log "   [Bloatware] Prov eliminado: $($_.DisplayName)" "DarkGray"
                    } catch { Write-Log "   [WARN] Prov $($_.DisplayName): $($_.Exception.Message -replace "`n"," ")" "DarkYellow" }
                }
            }
        }
        } else {
            foreach ($app in $bloatware) { Remove-AppxSafe $app }
        }
    }
    Invoke-Step "Bloatware" "Erradicando Bloatware..." { Invoke-ModuleBloatware }

    function Invoke-ModuleOneDrive {
        Get-Process OneDrive,OneDriveSetup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        $onedrivePaths = @("$env:SystemRoot\SysWOW64\OneDriveSetup.exe","$env:SystemRoot\System32\OneDriveSetup.exe")
        foreach ($od in $onedrivePaths) {
            if (Test-Path $od) {
                Write-Log "   Desinstalando OneDrive ($od)..." "Yellow"
                $proc = Start-Process $od "/uninstall" -NoNewWindow -PassThru -Wait
                # FIX D3: -2147219813 (0x8024801B) = cleanup parcial con sesion activa
                # OneDrive SÍ se desinstala — es un falso negativo conocido del uninstaller
                if ($proc.ExitCode -in @(0, -2147219813)) {
                    Write-Log "   OneDrive desinstalado." "DarkGray"
                } else {
                    Write-Log "   [WARN] OneDrive exit code $($proc.ExitCode)." "DarkYellow"
                }
                break
            }
        }
        Remove-AppxSafe "*OneDrive*"
        @("$env:LOCALAPPDATA\Microsoft\OneDrive","$env:PROGRAMDATA\Microsoft OneDrive","$env:USERPROFILE\OneDrive") | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
        Remove-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
    }
    Invoke-Step "OneDrive" "OneDrive: Desinstalar y limpiar..." { Invoke-ModuleOneDrive }

    function Invoke-ModuleXbox {
        if ($script:UseGamingMode) {
            # Gaming mode: conservar Xbox + optimizaciones
            Write-Log "   Gaming mode activado: conservando Xbox + optimizaciones." "Yellow"
            Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2  # HAGS
            Set-RegistryValue "HKCU:\Control Panel\Mouse" "MouseSpeed" "0" "String"  # Latencia ratón
        } else {
            # Desgamificar por defecto
            Remove-AppxSafe "*Xbox*"
            Remove-AppxSafe "*GamingApp*"
            Set-RegistryValue "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
            Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0
        }
    }
    Invoke-Step "Xbox" "Xbox/Gaming mode..." { Invoke-ModuleXbox }

    function Invoke-ModulePower {
        & powercfg.exe /hibernate off 2>&1 | Out-Null
        & powercfg.exe /change standby-timeout-ac 120 2>&1 | Out-Null
        & powercfg.exe /change monitor-timeout-ac 15 2>&1 | Out-Null
    }
    Invoke-Step "Power" "Optimizando energia..." { Invoke-ModulePower }

    function Invoke-ModuleUI {
        # Menu contextual clásico
        Set-RegistryValue "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" "(Default)" "" "String"
        Set-RegistryValue $REG_EXPLORER_ADV "TaskbarAl" 0
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0
        # FIX C5: En 24H2 TaskbarDa puede ser REG_BINARY — Remove+NewItemProperty evita
        # error "operacion no valida" al sobreescribir un tipo de dato distinto
        if ($script:IsDryRun) {
            Write-Log "  [DRY-RUN] Reg: TaskbarDa = 0 (Widgets off)" "DarkGray"
        } else {
            try {
                Remove-ItemProperty -LiteralPath $REG_EXPLORER_ADV -Name "TaskbarDa" -ErrorAction SilentlyContinue
                New-ItemProperty -LiteralPath $REG_EXPLORER_ADV -Name "TaskbarDa" -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
                Write-Log "   TaskbarDa = 0 (Widgets ocultos)" "DarkGray"
            } catch {
                Write-Log "   [WARN] TaskbarDa no modificable en Build $WinBuild. Ajusta en: Configuracion > Personalizacion > Barra de tareas." "DarkYellow"
            }
        }
        Set-RegistryValue $REG_COPILOT_USER "TurnOffWindowsCopilot" 1
        Set-RegistryValue $REG_COPILOT_MACHINE "TurnOffWindowsCopilot" 1
        Set-RegistryValue $REG_EXPLORER_ADV "TaskbarMn" 0
        Set-RegistryValue $REG_EXPLORER_ADV "ShowCopilotButton" 0  # Fix L3
        # Edge castrado
        Set-RegistryValue $REG_EDGE_POLICIES "HubsSidebarEnabled" 0
        Set-RegistryValue $REG_EDGE_POLICIES "EdgeShoppingAssistantEnabled" 0
        Set-RegistryValue $REG_EDGE_POLICIES "StartupBoostEnabled" 0
        $searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        Set-RegistryValue $searchPath "BingSearchEnabled" 0
        Set-RegistryValue $searchPath "SearchboxTaskbarMode" 1
        Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1
        Set-RegistryValue $REG_CDM "SubscribedContent-338389Enabled" 0
        Set-RegistryValue $REG_CDM "SubscribedContent-310093Enabled" 0
        Set-RegistryValue $REG_CDM "SubscribedContent-338388Enabled" 0
        Set-RegistryValue $REG_CDM "SubscribedContent-353698Enabled" 0
        Set-RegistryValue $REG_CDM "SilentInstalledAppsEnabled" 0
        Set-RegistryValue $REG_CDM "SystemPaneSuggestionsEnabled" 0
        Set-RegistryValue $REG_CDM "SoftLandingEnabled" 0
    }
    Invoke-Step "UI" "Restaurando interfaz clasica..." { Invoke-ModuleUI }

    function Invoke-ModuleTelemetry {
        Set-RegistryValue $REG_DATACOLLECTION "AllowTelemetry" 0
        Set-RegistryValue $REG_DATACOLLECTION2 "AllowTelemetry" 0
        Set-RegistryValue $REG_DATACOLLECTION2 "MaxTelemetryAllowed" 0
        Set-RegistryValue $REG_SYSTEM_POLICIES "EnableActivityFeed" 0
        Set-RegistryValue $REG_SYSTEM_POLICIES "PublishUserActivities" 0
        Set-RegistryValue $REG_SYSTEM_POLICIES "UploadUserActivities" 0
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
        @("DiagTrack","utcsvc","dmwappushservice","diagnosticshub.standardcollector.service") | ForEach-Object { Stop-ServiceSafe $_ }
        foreach ($t in $TelemetryTasks) {
            Disable-ScheduledTaskSafe $t.Path $t.Name
        }
        # Cazador dinamico: deshabilita cualquier tarea activa en rutas CEIP (cubre tareas nuevas futuras)
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
    Invoke-Step "Telemetry" "Desactivando telemetria..." { Invoke-ModuleTelemetry }

    function Invoke-ModulePrivacy {
        Set-PrivacyConsent "Deny"
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC" "PreventHandwritingDataSharing" 1
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports" "PreventHandwritingErrorReports" 1
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" "DisableInventory" 1
        Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" "AutoConnectAllowedOEM" 0
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
        Write-Log "   Privacidad Win11 24H2+ (Recall/AI/Copilot/CloudContent) configurada." "DarkGray"
    }
    Invoke-Step "Privacy" "Endureciendo privacidad..." { Invoke-ModulePrivacy }

    function Invoke-ModuleSSD {
        Disable-ScheduledTaskSafe "\Microsoft\Windows\Defrag\" "ScheduledDefrag"
        $trimOutput = & fsutil.exe behavior query DisableDeleteNotify 2>&1 | Out-String
        if ($trimOutput -match 'DisableDeleteNotify\s*=\s*1') {
            if ($trimOutput -match 'NTFS\s+DisableDeleteNotify\s*=\s*1') { & fsutil.exe behavior set DisableDeleteNotify NTFS 0 2>&1 | Out-Null }
            if ($trimOutput -match 'ReFS\s+DisableDeleteNotify\s*=\s*1') { & fsutil.exe behavior set DisableDeleteNotify ReFS 0 2>&1 | Out-Null }
            Write-Log "   TRIM reactivado." "Yellow"
        }
        # FIX #28: Solo detener SysMain si no estaba ya deshabilitado
        $smSvc = Get-Service "SysMain" -ErrorAction SilentlyContinue
        if ($smSvc -and $smSvc.StartType -ne 'Disabled') {
            Stop-ServiceSafe "SysMain"
        } else {
            Write-Log "   SysMain ya deshabilitado." "DarkGray"
        }
    }
    Invoke-Step "SSD" "Optimizando SSD..." { Invoke-ModuleSSD }

    function Invoke-ModuleCleanup {
        $targets = @(
            @{Path="$env:TEMP";                                     Label="TEMP usuario"},
            @{Path="$env:SystemRoot\Temp";                          Label="TEMP sistema"},
            # Prefetch excluido: solo se limpia en modo Deep (AggressiveDisk)
            @{Path="$env:SystemRoot\SoftwareDistribution\Download"; Label="WU Cache"}
        )
        if ($ctx.AggressiveDisk) {
            Write-Log "   [Deep] Limpiando Prefetch (solo modo Deep)..." "Yellow"
            $prefetchPath = "$env:SystemRoot\Prefetch"
            if (Test-Path $prefetchPath) {
                # FIX C1-Prefetch: mismo patron seguro que el bucle principal
                $moPref = Get-ChildItem $prefetchPath -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
                $pbefore = if ($null -ne $moPref -and $null -ne $moPref.Sum) { [long]$moPref.Sum } else { 0L }
                # FIX D1: -Recurse para ReadyBoot (subdirectorio); -Confirm:$false elimina
                # el prompt interactivo "tiene elementos secundarios" en PS5.1
                Get-ChildItem $prefetchPath -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
                Write-Log "   Prefetch: ~$([math]::Round(($pbefore/1MB),1)) MB liberados (apps tardaran mas en 1er arranque)." "DarkGray"
            }
        }
        # FIX Bug-C: detener wuauserv para liberar archivos de WU Cache en uso
        $wuWasRunning = (Get-Service wuauserv -ErrorAction SilentlyContinue).Status -eq "Running"
        if ($wuWasRunning) {
            Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
            Write-Log "   wuauserv detenido para limpieza WU Cache." "DarkGray"
        }
        try {
            foreach ($t in $targets) {
                if (Test-Path $t.Path) {
                    $moB    = Get-ChildItem $t.Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
                    $before = if ($null -ne $moB -and $null -ne $moB.Sum) { [long]$moB.Sum } else { 0L }
                    Get-ChildItem $t.Path -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.FullName -notin @($LogFile, $TranscriptPath) } |
                        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    $moA   = Get-ChildItem $t.Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
                    $after = if ($null -ne $moA -and $null -ne $moA.Sum) { [long]$moA.Sum } else { 0L }
                    Write-Log "   $($t.Label): ~$([math]::Round((($before-$after)/1MB),1)) MB liberados" "DarkGray"
                }
            }
        } finally {
            if ($wuWasRunning) {
                Start-Service wuauserv -ErrorAction SilentlyContinue
                Write-Log "   wuauserv reiniciado." "DarkGray"
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
    Invoke-Step "Cleanup" "Limpiando caches..." { Invoke-ModuleCleanup }

    function Invoke-ModuleOptionalFeatures {
        $features = @("FaxServicesClientPackage","Printing-XPSServices-Features","WorkFolders-Client")
        $anyDisabled = $false
        foreach ($f in $features) {
            $feat = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
            if ($feat -and $feat.State -eq "Enabled") {
                Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction SilentlyContinue | Out-Null
                $anyDisabled = $true
            }
        }
        if ($anyDisabled) {
            $ctx.RebootRequired.Add("OptionalFeatures")
            Write-Log "   Requiere reinicio para features." "Yellow"
        }
    }
    Invoke-Step "OptionalFeatures" "Desactivando features opcionales..." { Invoke-ModuleOptionalFeatures }

    function Invoke-ModuleDiskSpace {
        if (-not $ctx.AggressiveDisk) {
            Write-Log "   [SKIP] DiskSpace profundo solo en Deep." "DarkGray"
            return
        }
        Write-Log "   [IRREVERSIBLE] Limpiando WinSxS con DISM..." "Yellow"
        & Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart 2>&1 | ForEach-Object { Write-Log "   $_" "DarkGray" }
        if ($LASTEXITCODE -ne 0) { throw "DISM fallo codigo $LASTEXITCODE" }
        $ctx.RebootRequired.Add("WinSxS")
    }
    Invoke-Step "DiskSpace" "Limpieza WinSxS DISM..." { Invoke-ModuleDiskSpace }

    function Invoke-ModuleExplorerPerf {
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2
    }
    Invoke-Step "ExplorerPerf" "Desactivando animaciones..." { Invoke-ModuleExplorerPerf }

    function Invoke-ModuleDevEnv {
        Set-RegistryValue $REG_EXPLORER_ADV "HideFileExt" 0
        Set-RegistryValue $REG_EXPLORER_ADV "Hidden" 1
        Set-RegistryValue $REG_EXPLORER_ADV "ShowSuperHidden" 1
        # FIX C2: -ExecutionPolicy Bypass del proceso tiene precedencia; PS emite
        # una advertencia que con ErrorActionPreference=Stop se convierte en terminating
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop 2>&1 | Out-Null
            Write-Log "   ExecutionPolicy -> RemoteSigned (CurrentUser)" "DarkGray"
        } catch {
            Write-Log "   [INFO] ExecutionPolicy no modificada: scope Bypass del proceso tiene precedencia (esperado)." "DarkGray"
        }
        # LongPathsEnabled (solo marca reboot si el valor cambia)
        $_lp = Get-ItemProperty -LiteralPath $REG_LONGPATHS -Name "LongPathsEnabled" -ErrorAction SilentlyContinue
        $longPathsCurrent = if ($null -ne $_lp) { $_lp.LongPathsEnabled } else { $null }
        Set-RegistryValue $REG_LONGPATHS "LongPathsEnabled" 1
        if ($longPathsCurrent -ne 1) {
            $ctx.RebootRequired.Add("LongPaths")
            Write-Log "   LongPathsEnabled activado (requiere reinicio)." "Yellow"
        } else {
            Write-Log "   LongPathsEnabled ya estaba activo." "DarkGray"
        }
    }
    Invoke-Step "DevEnv" "Configurando entorno desarrollo..." { Invoke-ModuleDevEnv }

    # MÓDULO 16: Admin Tools (winget + features de red nativas)
    function Invoke-ModuleAdminTools {
        # FIX #13: Verificar red antes de winget (evita timeout 30-90s por app sin red)
        $wingetNetOk = $false
        try {
            $wgc = [System.Net.Sockets.TcpClient]::new()
            $wgar = $wgc.BeginConnect("winget.azureedge.net", 443, $null, $null)
            $wingetNetOk = $wgar.AsyncWaitHandle.WaitOne(3000)
            $wgc.Close()
        } catch { $wingetNetOk = $false }

        # Apps via winget
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Log "   [SKIP] winget no disponible." "DarkYellow"
        } elseif (-not $wingetNetOk) {
            Write-Log "   [SKIP] Sin conectividad a winget.azureedge.net:443. Instala apps manualmente." "DarkYellow"
        } else {
            # FIX C3: resetear fuentes winget — codigo -1978335157 indica indice corrupto
            Write-Log "   Reseteando fuentes de winget (puede tardar 10-15s)..." "DarkGray"
            & winget source reset --force 2>&1 | Out-Null
            & winget source update 2>&1 | Out-Null
            $apps = @("7zip.7zip", "PuTTY.PuTTY", "Notepad++.Notepad++", "Microsoft.Sysinternals.Suite", "Ghisler.TotalCommander")
            if ($script:UseInstallWindhawk) { $apps += "RamenSoftware.Windhawk" }
            foreach ($app in $apps) {
                Write-Log "   Instalando $app via winget..." "Yellow"
                # FIX D2: --source winget omite msstore (falla SSL en proxies corporativos: 0x8a15005e)
                $proc = Start-Process "winget" -ArgumentList @("install","--id",$app,"--exact","--silent","--accept-package-agreements","--accept-source-agreements","--source","winget") -NoNewWindow -PassThru -Wait
                # FIX C3b: deteccion especifica de error SSL de proxy corporativo
                if ($proc.ExitCode -eq -1978335138 -or $proc.ExitCode -eq 0x8A15005E) {
                    Write-Log "   [WARN] $app fallo: error SSL (¿proxy corporativo? Intenta: winget settings --enable ProxyBypass)." "DarkYellow"
                } elseif ($proc.ExitCode -eq 3010) {
                    Write-Log "   $app instalado. Reinicio requerido (3010)." "Yellow"
                    $ctx.RebootRequired.Add("AdminTools")
                } elseif ($proc.ExitCode -eq -1978335189) {
                    Write-Log "   $app ya instalado y actualizado (sin upgrade disponible)." "DarkGray"
                } elseif ($proc.ExitCode -ne 0) {
                    Write-Log "   [WARN] $app fallo (codigo $($proc.ExitCode))." "DarkYellow"
                } else {
                    Write-Log "   $app instalado." "DarkGray"
                }
            }
        }

        # Features de red nativas (try/catch individual por robustez en builds que no las tienen)
        $netFeatures = @("TelnetClient", "ClientForNFS-Infrastructure")
        if ($WinBuild -lt 26000) { $netFeatures += "TFTPClient" }  # E09: eliminada en builds 26xxx+
        $anyNetEnabled = $false
        foreach ($f in $netFeatures) {
            try {
                $feat = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop
                # FIX #14: $feat puede ser null si el feature no existe en este build
                if ($null -eq $feat) { Write-Log "   [WARN] Feature $f no encontrada en este build." "DarkYellow"; continue }
                if ($feat.State -ne 'Enabled') {
                    Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart -ErrorAction Stop | Out-Null
                    Write-Log "   $f habilitado." "DarkGray"
                    $anyNetEnabled = $true
                } else {
                    Write-Log "   $f ya estaba habilitado." "DarkGray"
                }
            } catch {
                Write-Log "   [WARN] $f no disponible en este build/edicion: $_" "DarkYellow"
            }
        }
        if ($anyNetEnabled) { $ctx.RebootRequired.Add("NetFeatures") }
    }
    Invoke-Step "AdminTools" "Instalando kit sysadmin (winget + features de red)..." { Invoke-ModuleAdminTools }

    # MÓDULO 17: DNS seguros (Cloudflare 1.1.1.1 + Quad9 9.9.9.9)
    function Invoke-ModuleDNS {
        if (-not $script:UseSetSecureDNS) {
            Write-Log "   [DNS] Toggle inactivo. Omitiendo." "DarkGray"
            return
        }
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false })
        if ($adapters.Count -eq 0) {
            Write-Log "   [DNS][SKIP] Sin adaptadores fisicos Up." "DarkGray"
            return
        }
        # B14: guardar DNS actuales antes de sobreescribir
        foreach ($a in $adapters) {
            $v4 = (Get-DnsClientServerAddress -InterfaceAlias $a.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
            $v6 = (Get-DnsClientServerAddress -InterfaceAlias $a.Name -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses
            $ctx.DNSBackup[$a.Name] = @{ IPv4 = @($v4 | Where-Object { $_ }); IPv6 = @($v6 | Where-Object { $_ }) }
        }
        # B08: IPv4 + IPv6 (Cloudflare + Quad9) — evita fuga via AAAA
        $dnsServers = @("1.1.1.1","9.9.9.9","2606:4700:4700::1111","2620:fe::fe")
        foreach ($a in $adapters) {
            Write-Log "   DNS en $($a.Name)..." "Yellow"
            Set-DnsClientServerAddress -InterfaceAlias $a.Name -ServerAddresses $dnsServers -ErrorAction SilentlyContinue
        }
        Write-Log "   DNS seguros IPv4+IPv6 configurados ($($adapters.Count) adaptadores)." "Green"
    }
    if ($SetSecureDNS) { Invoke-Step "DNS" "Configurando DNS seguros (Cloudflare/Quad9)..." { Invoke-ModuleDNS } }

#endregion

#region ── FINALIZACION ──────────────────────────────────────────────────────

    # Restart Explorer condicional (fix L2)
    if (-not (Test-Skip "UI") -or -not (Test-Skip "ExplorerPerf")) {
        if ($script:IsDryRun) {
            $msg = "  [DRY-RUN] Explorer restart omitido."
            Write-Log $msg "DarkGray"
            $ctx.DryRunActions.Add($msg)
        } else {
            Write-Log "Reiniciando Explorer..." "Yellow"
            $explorerProcs = Get-Process explorer -ErrorAction SilentlyContinue
            if ($explorerProcs) {
                $originalPIDs = $explorerProcs.Id
                $explorerProcs | Stop-Process -Force -ErrorAction SilentlyContinue
                $deadline = (Get-Date).AddSeconds(5)
                while ((Get-Date) -lt $deadline) {
                    $stillAlive = $originalPIDs | Where-Object { $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue) }
                    if (-not $stillAlive) { break }
                    Start-Sleep -Milliseconds 300
                }
                Start-Process explorer.exe
            }
        }
    }

    Write-Log "================================================================" "Green"
    $summaryColor = if ($ctx.StepsFail -gt 0) { "Red" } else { "Green" }
    Write-Log "Resumen: $($ctx.StepsOk) OK | $($ctx.StepsFail) errores" $summaryColor
    if ($ctx.FailedModules.Count -gt 0) {
        Write-Log "Fallidos: $($ctx.FailedModules -join ', ')" "Red"
    }

    if ($script:IsDryRun) {
        Write-Log "" "White"
        Write-Log "═══════════════ RESUMEN DRY-RUN ═══════════════" "Cyan"
        Write-Log "Acciones simuladas: $($ctx.DryRunActions.Count)" "Cyan"
        Write-Log "───────────────────────────────────────────────" "DarkGray"
        $ctx.DryRunActions | ForEach-Object { Write-Log $_ "DarkGray" }
        Write-Log "═══════════════════════════════════════════════" "Cyan"
        Write-Log "[DRY-RUN] Ningun cambio aplicado." "Green"
        Exit-Script 0
    }

    if ($ctx.RebootRequired.Count -gt 0) {
        Write-Log "Reinicio OBLIGATORIO para: $($ctx.RebootRequired -join ', ')" "Yellow"
    }

    Write-Log "Backup: $BackupDir | Log: $LogFile | Transcript: $TranscriptPath" "DarkGray"
    $respuesta = Read-Host "`nReiniciar ahora? [s/N]"
    if ($respuesta -match "^[sS]$") {
        Restart-Computer -Force
    } else {
        Write-Host "Reinicio pospuesto. Recuerda reiniciar para aplicar todo." -ForegroundColor Yellow
    }

    if ($ctx.StepsFail -gt 0) { Exit-Script 1 }
    Exit-Script 0

} finally {
    # FIX E2: en PS5.1 Stop-Transcript ignora -ErrorAction SilentlyContinue
    # si no hay transcripcion activa — necesita try/catch explicito
    try { Stop-Transcript } catch {}
    try { if ($_mutex -and $acquired) { $_mutex.ReleaseMutex() } } catch {}
}
