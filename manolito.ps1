<#
 ███╗   ███╗ █████╗ ██████╗  ██████╗ ██╗     ██╗████████╗ ██████╗ 
 ████╗ ████║██╔══██╗██╔══██╗██╔═══██╗██║     ██║╚══██╔══╝██╔═══██╗
 ██╔████╔██║███████║██║  ██║██║   ██║██║     ██║   ██║   ██║   ██║
 ██║╚██╔╝██║██╔══██║██║  ██║██║   ██║██║     ██║   ██║   ██║   ██║
 ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╔╝███████╗██║   ██║   ╚██████╔╝
 ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝    ╚═════╝ 
                 [ Windows 11 Enterprise Provisioning ]
                 [ v2.5.5 - The Offline Armor Update  ]
.COPYRIGHT
    Copyright (c) 2026 Manolito Project Contributors. Todos los derechos reservados.

.LICENSE
    Este script se distribuye bajo la licencia GNU GPLv3.
    Es software libre: puedes redistribuirlo y/o modificarlo bajo los terminos
    de la Licencia Publica General GNU publicada por la Free Software Foundation.

    [!]  ADVERTENCIA DE USO COMERCIAL (DOBLE LICENCIA):
    El uso de este software en entornos corporativos, empresariales, o por parte
    de Proveedores de Servicios Gestionados (MSP) con fines lucrativos esta sujeto
    a las estrictas obligaciones de la GPLv3 (liberacion de codigo fuente derivado).
    Para utilizar este software sin las restricciones de la GPLv3, se requiere la
    adquisicion de una Licencia Comercial. Contacta con el autor.
#>
<# 
+==================================================================+
|              Manolito v2.5.5 -- Windows 11 Edu/Pro/Ent           |
|  Optimizador modular: dev * gaming * esports * sysadmin          |
+==================================================================+
|  Modos     : Lite | DevEdu | Deep | Restore | Check              |
|  DryRun    : simula todos los cambios sin aplicar nada           |
|  Skip      : -Skip HyperV SSD AdminTools (secciones separadas)   |
|  Gaming    : -GamingMode (HAGS, MSITuning, latencia raton/red)   |
|  DNS       : -SetSecureDNS (1.1.1.1 + 9.9.9.9)                   |
|  Interac.  : -Interactive (menu + sub-menu toggles)              |
|  Auditoria : -Verify (auditoria post-escritura de registro)      |
|  Seguridad : -DisableVBS (Solo Deep. Deshabilita HVCI/VBS)       |
+==================================================================+
|  Ejemplos  : .\manolito.ps1 -Mode Check                          |
|              .\manolito.ps1 -Mode Deep -GamingMode -Verify       |
+==================================================================+

.PARAMETER Mode              Lite | DevEdu | Deep | Restore | Check (default: DevEdu)
.PARAMETER DryRun            Simula sin aplicar nada
.PARAMETER Force             Omite confirmaciones interactivas
.PARAMETER Skip              Secciones a omitir (string[])
.PARAMETER GamingMode        Conserva Xbox + optimizaciones gaming
.PARAMETER SetSecureDNS      DNS 1.1.1.1 + 9.9.9.9
.PARAMETER InstallWindhawk   Instala Windhawk via winget
.PARAMETER SkipAdminTools    Omite herramientas sysadmin
.PARAMETER Interactive       Menu interactivo
.PARAMETER Verify            Auditoria post-ejecucion de registro
.PARAMETER DisableVBS        Deshabilita VBS/HVCI (Deep + reboot)
.PARAMETER ActivationTimeoutSec  Timeout slmgr /ato en segundos (default 120)
#>

[CmdletBinding()]
param(
    [ValidateSet("Lite", "DevEdu", "Deep", "Restore", "Check")]
    [string]$Mode = "DevEdu",
    [switch]$DryRun,
    [switch]$Force,
    [ValidateSet(
        "Activation", "DeKMS", "Updates", "Defender", "HyperV", "Bloatware", "OneDrive", "Xbox",
        "Power", "UI", "Telemetry", "SSD", "Privacy", "Cleanup", "OptionalFeatures",
        "DiskSpace", "ExplorerPerf", "DevEnv", "AdminTools", "OfflineOS", "DNS",
        "NICTuning", "InputTuning", "MSITuning", "VBSTuning"
    )]
    [string[]]$Skip = @(),
    [switch]$GamingMode,
    [switch]$SetSecureDNS,
    [switch]$InstallWindhawk,
    [switch]$SkipAdminTools,
    [switch]$Interactive,
    [switch]$Verify,
    [switch]$DisableVBS,
    [ValidateRange(30, 600)]
    [int]$ActivationTimeoutSec = 120
)

$script:IsDryRun = $DryRun.IsPresent
$script:UseGamingMode = $GamingMode.IsPresent
$script:UseSetSecureDNS = $SetSecureDNS.IsPresent
$script:UseInstallWindhawk = $InstallWindhawk.IsPresent

#region -- CONFIGURACION DE USUARIO
$script:ProductKey = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
#endregion

#region -- BOOTSTRAP
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'UTF8'

$PSMajor = $PSVersionTable.PSVersion.Major
if ($PSMajor -lt 5) {
    Write-Host "[ERROR] Se requiere PowerShell 5.1 o superior. Detectado: $PSMajor" -ForegroundColor Red
    exit 1
}
$PS7Plus = ($PSMajor -ge 7)

# FIX-B08: detectar PS 32-bit
if ([IntPtr]::Size -eq 4) {
    Write-Warning "[FIX-B08] PowerShell 32-bit en Windows 64-bit. Set-RegTracked usa Registry64 pero Set-ItemProperty usara WOW64. Ejecuta desde PowerShell 64-bit."
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Se requieren privilegios de administrador. Relanzando elevado..."
    $psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode `"$Mode`""
    if ($script:IsDryRun) { $argList += " -DryRun" }
    if ($Force.IsPresent) { $argList += " -Force" }
    if ($Interactive.IsPresent) { $argList += " -Interactive" }
    if ($script:UseGamingMode) { $argList += " -GamingMode" }
    if ($script:UseSetSecureDNS) { $argList += " -SetSecureDNS" }
    if ($script:UseInstallWindhawk) { $argList += " -InstallWindhawk" }
    if ($SkipAdminTools.IsPresent) { $argList += " -SkipAdminTools" }
    if ($Verify.IsPresent) { $argList += " -Verify" }
    if ($DisableVBS.IsPresent) { $argList += " -DisableVBS" }
    if ($ActivationTimeoutSec -ne 120) { $argList += " -ActivationTimeoutSec $ActivationTimeoutSec" }
    if ($Skip.Count -gt 0) {
        $argList += " -Skip " + (($Skip | ForEach-Object { "`"$_`"" }) -join " ")
    }
    Start-Process $psExe -ArgumentList $argList -Verb RunAs
    exit
}

Set-StrictMode -Version Latest
function Exit-Script { param([int]$Code = 0); exit $Code }

$_mutex = $null; $acquired = $false
try {
    $_mutex = [System.Threading.Mutex]::new($false, "Global\ManolitoOptimizer")
    try { $acquired = $_mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) {
        Write-Host "[ERROR] Manolito ya esta en ejecucion en otra ventana." -ForegroundColor Red
        exit 1
    }

    $PS7Plus = ($PSMajor -ge 7)
    $OSInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $WinBuild = [int]$OSInfo.BuildNumber
    $OSCaption = $OSInfo.Caption
    $OSSku = [int]$OSInfo.OperatingSystemSKU

    $SupportedSkus = @(121, 122, 48, 49, 27, 28, 84, 125)
    $IsEducationSku = ($OSSku -in @(121, 122))
    $IsProSku = ($OSSku -in @(48, 49)) # reservado para expansiones futuras
    $IsEnterpriseSku = ($OSSku -in @(27, 28, 84, 125)) # reservado para expansiones futuras
    $IsSupportedSku = ($OSSku -in $SupportedSkus)

    $SKULabel = switch ($OSSku) {
        121 { "Education" }    122 { "Education N" }
        48 { "Pro" }          49 { "Pro N" }
        27 { "Enterprise" }   28 { "Enterprise N" }
        84 { "Enterprise G" } 125 { "Enterprise G N" }
        default { "SKU=$OSSku" }
    }

    $WIN11_BUILD_LATEST_TESTED = 26100
    if ($WinBuild -gt $WIN11_BUILD_LATEST_TESTED -and $IsSupportedSku) {
        Write-Warning "Build $WinBuild superior al ultimo testado ($WIN11_BUILD_LATEST_TESTED)."
    }
    if ($WinBuild -lt 22000 -or -not $IsSupportedSku) {
        @(
            "ERROR: Edicion no compatible. Requerido: Windows 11 Education, Pro o Enterprise.",
            "SO detectado: $OSCaption (Build $WinBuild | $SKULabel)",
            "Abortando."
        ) | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Exit-Script 1
    }
    Write-Host "[Bootstrap] $OSCaption [$SKULabel] Build $WinBuild" -ForegroundColor DarkGray

    $maniDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Manolito'
    if (-not (Test-Path $maniDir)) { New-Item -Path $maniDir -ItemType Directory -Force | Out-Null }
    $TranscriptPath = Join-Path $maniDir "transcript_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $LogFile = Join-Path $maniDir "log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $BackupDir = Join-Path $maniDir "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $DNSBackupFile = Join-Path $maniDir "dns_backup.json"

    # FIX-C35: verificar inicio de transcript con try/catch explicito
    $script:TranscriptStarted = $false
    try {
        Start-Transcript -Path $TranscriptPath -Append -NoClobber -ErrorAction Stop
        $script:TranscriptStarted = $true
    }
    catch {
        Write-Host "[WARN] No se pudo iniciar transcript: $($_.Exception.Message). Log en $LogFile sigue activo." -ForegroundColor DarkYellow
    }

    # Constantes de registro
    $REG_DATACOLLECTION = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    $REG_DATACOLLECTION2 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
    $REG_WU_AU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    $REG_DEFENDER_SPYNET = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"
    $REG_COPILOT_USER = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
    $REG_COPILOT_MACHINE = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
    $REG_EXPLORER_ADV = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $REG_CDM = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $REG_APP_PRIVACY = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore"
    $REG_POLICIES_SYSTEM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $REG_WORKPLACE_JOIN = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin"
    $REG_MSA = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount"
    $REG_OOBE = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"
    $REG_SYSTEM_POLICIES = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    $REG_EDGE_POLICIES = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    $REG_LONGPATHS = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"

    $PrivacyCapabilities = @(
        "location", "contacts", "appointments", "phoneCallHistory", "radios", "userNotificationListener"
    )

    $TelemetryTasks = @(
        @{Path = "\Microsoft\Windows\Application Experience\"; Name = "Microsoft Compatibility Appraiser" },
        @{Path = "\Microsoft\Windows\Application Experience\"; Name = "ProgramDataUpdater" },
        @{Path = "\Microsoft\Windows\Application Experience\"; Name = "StartupAppTask" },
        @{Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "Consolidator" },
        @{Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "UsbCeip" },
        @{Path = "\Microsoft\Windows\Autochk\"; Name = "Proxy" },
        @{Path = "\Microsoft\Windows\DiskDiagnostic\"; Name = "Microsoft-Windows-DiskDiagnosticDataCollector" }
    )

    $ctx = @{
        StepsOk              = 0
        StepsFail            = 0
        StepNum              = 0
        AggressiveDisk       = $false
        RebootRequired       = [System.Collections.Generic.List[string]]::new()
        SkipList             = [System.Collections.Generic.List[string]]::new()
        ProvisionedCache     = $null
        InstalledCache       = $null
        DryRunActions        = [System.Collections.Generic.List[string]]::new()
        FailedModules        = [System.Collections.Generic.List[string]]::new()
        DeKMSCleaned         = $false
        DNSBackup            = @{}
        RegDiff              = [System.Collections.Generic.List[PSCustomObject]]::new()
        OfflineOSApplied     = $false
        ResetBaseApplied     = $false   # FIX-C08: flag DISM /ResetBase
        ServiceStartupBackup = @{}      # FIX-C34: backup de StartupType por servicio
    }

    $ValidSections = @(
        "Activation", "DeKMS", "Updates", "Defender", "HyperV", "Bloatware", "OneDrive", "Xbox",
        "Power", "UI", "Telemetry", "SSD", "Privacy", "Cleanup", "OptionalFeatures",
        "DiskSpace", "ExplorerPerf", "DevEnv", "AdminTools", "OfflineOS", "DNS",
        "NICTuning", "InputTuning", "MSITuning", "VBSTuning"
    )

    # FIX-B07: iterar string[] elemento a elemento antes de -split
    foreach ($skipEntry in $Skip) {
        foreach ($part in ($skipEntry -split '[,\s]+' | Where-Object { $_ })) {
            if ($part -in $ValidSections -and $part -notin $ctx.SkipList) {
                $ctx.SkipList.Add($part)
            }
        }
    }

    #region -- HELPERS --------------------------------------------------------

    # FIX-C36: Write-Log con try/catch en Add-Content; consola nunca se pierde
    function Write-Log {
        param([string]$Message, [string]$Color = "White")
        $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
        try {
            Add-Content -LiteralPath $LogFile -Value $line -ErrorAction Stop
        }
        catch {
            # Fallo silencioso en disco; la consola sigue funcionando
        }
        Write-Host $Message -ForegroundColor $Color
    }

    function Add-Skip {
        param([string]$Section)
        if ($Section -in $ValidSections) {
            if ($Section -notin $ctx.SkipList) { $ctx.SkipList.Add($Section) }
        }
        else {
            Write-Log "[WARN] Seccion '$Section' no reconocida en Add-Skip." "DarkYellow"
        }
    }

    function Test-Skip([string]$Section) { $ctx.SkipList -contains $Section }

    function Set-RegistryValue {
        param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
        if ($script:IsDryRun) {
            $msg = "  [DRY-RUN] Reg: $Path\$Name = $Value"
            Write-Log $msg "DarkGray"; $ctx.DryRunActions.Add($msg); return
        }
        try {
            if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
            if ($Name -eq "(Default)") {
                $current = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
                if ($null -ne $current -and $current.GetValue('') -eq $Value) { return }
                Set-Item -LiteralPath $Path -Value $Value -ErrorAction Stop
            }
            else {
                $current = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
                if ($null -ne $current -and $current.$Name -eq $Value) { return }
                Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
            }
        }
        catch { Write-Log "  [WARN] No se pudo escribir $Path\$Name : $_" "DarkYellow" }
    }

    function Set-RegTracked {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][object]$Value,
            [ValidateSet("DWord", "QWord", "String", "ExpandString", "MultiString", "Binary")]
            [string]$Type = "DWord"
        )
        if ($script:IsDryRun) {
            $msg = "  [DRY-RUN] RegTracked: $Path\$Name = $Value ($Type)"
            Write-Log $msg "DarkGray"; $ctx.DryRunActions.Add($msg); return
        }
        $before = $null
        try {
            $hive = if ($Path -match "^HKLM") { [Microsoft.Win32.RegistryHive]::LocalMachine } else { [Microsoft.Win32.RegistryHive]::CurrentUser }
            $subPath = $Path -replace "^HK[LC][MU]:\\", ""
            $regKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Registry64)
            $subKey = $regKey.OpenSubKey($subPath)
            if ($null -ne $subKey) {
                $before = if ($Name -eq "(Default)") { $subKey.GetValue("") } else { $subKey.GetValue($Name) }
            }
        }
        catch { }
        try {
            if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
            if ($Name -eq "(Default)") { Set-Item -LiteralPath $Path -Value $Value -ErrorAction Stop }
            else { Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop }
            $after = $null
            try {
                $hive = if ($Path -match "^HKLM") { [Microsoft.Win32.RegistryHive]::LocalMachine } else { [Microsoft.Win32.RegistryHive]::CurrentUser }
                $subPath = $Path -replace "^HK[LC][MU]:\\", ""
                $regKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Registry64)
                $subKey = $regKey.OpenSubKey($subPath)
                if ($null -ne $subKey) {
                    $after = if ($Name -eq "(Default)") { $subKey.GetValue("") } else { $subKey.GetValue($Name) }
                }
            }
            catch { }
            $ctx.RegDiff.Add([PSCustomObject]@{
                    Path          = $Path
                    Name          = $Name
                    Type          = $Type
                    Before        = $before
                    AfterExpected = $Value
                    AfterActual   = $after
                    PendingReboot = $Path -match "(GraphicsDrivers|Interrupt Management|bcdedit|DeviceGuard)"
                    Timestamp     = Get-Date
                })
            Write-Log "  [RegTracked] $Path\$Name : $before -> $Value" "DarkGray"
        }
        catch {
            Write-Log "  [WARN] Set-RegTracked $Path\$Name : $($_.Exception.Message)" "DarkYellow"
        }
    }

    function Invoke-Check {
        param(
            [Parameter(Mandatory)][string]$Name,
            [bool]$RequiresAdmin = $false,
            [Parameter(Mandatory)][scriptblock]$ScriptBlock
        )
        $status = "OK"; $detail = ""
        if ($RequiresAdmin -and -not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $status = "SKIP"; $detail = "Requiere privilegios de administrador."
        }
        else {
            try {
                $result = & $ScriptBlock
                $status = if ($null -ne $result.Status) { $result.Status } else { "OK" }
                $detail = if ($null -ne $result.Detail) { $result.Detail } else { "Correcto" }
            }
            catch { $status = "FAIL"; $detail = $_.Exception.Message }
        }
        return [PSCustomObject]@{ Name = $Name; Status = $status; Detail = $detail }
    }

    # FIX-C17: Invoke-Verify soporta Binary y MultiString correctamente
    function Invoke-Verify {
        if ($ctx.RegDiff.Count -eq 0) { Write-Log "[Verify] Sin cambios rastreados." "Yellow"; return }
        Write-Log "`n[Verify] Verificando $($ctx.RegDiff.Count) claves..." "Cyan"
        $verified = 0; $mismatch = 0; $pending = 0; $notfound = 0
        foreach ($entry in $ctx.RegDiff) {
            $status = "VERIFIED"
            if ($null -eq $entry.AfterActual) {
                $status = "NOTFOUND"; $notfound++
            }
            elseif ($entry.PendingReboot) {
                $status = "PENDINGREBOOT"; $pending++
            }
            else {
                # FIX-C17: intentar uint32 primero; si falla (Binary/MultiString/String)
                #          serializar elemento a elemento para comparacion real
                $actualNorm = try { [uint32]$entry.AfterActual } catch { $null }
                $expectedNorm = try { [uint32]$entry.AfterExpected } catch { $null }
                if ($null -eq $actualNorm -or $null -eq $expectedNorm) {
                    $serialize = {
                        param($v)
                        if ($v -is [array]) { ($v | ForEach-Object { "$_" }) -join ',' }
                        else { "$v" }
                    }
                    $aStr = & $serialize $entry.AfterActual
                    $eStr = & $serialize $entry.AfterExpected
                    if ($aStr -ne $eStr) { $status = "MISMATCH"; $mismatch++ } else { $verified++ }
                }
                elseif ($actualNorm -ne $expectedNorm) { $status = "MISMATCH"; $mismatch++ }
                else { $verified++ }
            }
            $pathShort = $entry.Path -replace "^HK[LC][MU]:\\", ""
            Write-Log "  [$status] $pathShort\$($entry.Name) : $($entry.Before) -> $($entry.AfterExpected)" "DarkGray"
        }
        $sc = if ($mismatch -gt 0 -or $notfound -gt 0) { "Yellow" } else { "Green" }
        Write-Log "[Verify] VERIFIED=$verified MISMATCH=$mismatch PENDING=$pending NOTFOUND=$notfound" $sc
        if ($mismatch -gt 0 -or $notfound -gt 0) { Write-Log "[Verify] [!] Detectados errores." "Yellow" }
    }

    function Set-PrivacyConsent {
        param([ValidateSet("Allow", "Deny")][string]$Value)
        foreach ($cap in $PrivacyCapabilities) {
            Set-RegistryValue "$REG_APP_PRIVACY\$cap" "Value" $Value "String"
        }
    }

    # FIX-C28: verificar estado post-operacion
    # FIX-C34: guardar StartupType original en ctx.ServiceStartupBackup
    function Stop-ServiceSafe {
        param([string]$Name)
        if ($script:IsDryRun) { $ctx.DryRunActions.Add("[DRY-RUN] Stop/Disable: $Name"); return }
        $svc = Get-Service $Name -ErrorAction SilentlyContinue
        if ($svc) {
            # FIX-C34: guardar StartupType si no esta ya guardado
            if (-not $ctx.ServiceStartupBackup.ContainsKey($Name)) {
                $ctx.ServiceStartupBackup[$Name] = $svc.StartType
            }
            Stop-Service $Name -Force -ErrorAction SilentlyContinue
            Set-Service  $Name -StartupType Disabled -ErrorAction SilentlyContinue
            # FIX-C28: verificar post-operacion
            $svcPost = Get-Service $Name -ErrorAction SilentlyContinue
            if ($null -ne $svcPost -and $svcPost.Status -eq 'Stopped') {
                Write-Log "   Servicio $Name detenido." "DarkGray"
            }
            else {
                $st = if ($null -ne $svcPost) { $svcPost.Status } else { "N/A" }
                Write-Log "   [WARN] $Name no se detuvo completamente (status=$st)." "DarkYellow"
            }
        }
    }

    # FIX-C28: verificar estado post-operacion
    function Start-ServiceSafe {
        param([string]$Name)
        if ($script:IsDryRun) { $ctx.DryRunActions.Add("[DRY-RUN] Enable/Start: $Name"); return }
        $svc = Get-Service $Name -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service   $Name -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service $Name                        -ErrorAction SilentlyContinue
            # FIX-C28: verificar post-operacion
            $svcPost = Get-Service $Name -ErrorAction SilentlyContinue
            if ($null -ne $svcPost -and $svcPost.Status -eq 'Running') {
                Write-Log "   Servicio $Name iniciado." "DarkGray"
            }
            else {
                $st = if ($null -ne $svcPost) { $svcPost.Status } else { "N/A" }
                Write-Log "   [WARN] $Name puede no haber arrancado correctamente (status=$st)." "DarkYellow"
            }
        }
    }

    function Disable-ScheduledTaskSafe {
        param([string]$TaskPath, [string]$TaskName)
        if ($script:IsDryRun) { $ctx.DryRunActions.Add("[DRY-RUN] Disable task: $TaskPath$TaskName"); return }
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task -and $task.State -ne 'Disabled') {
            $task | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        }
    }

    function Enable-ScheduledTaskSafe {
        param([string]$TaskPath, [string]$TaskName)
        if ($script:IsDryRun) { $ctx.DryRunActions.Add("[DRY-RUN] Enable task: $TaskPath$TaskName"); return }
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task -and $task.State -eq 'Disabled') {
            $task | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        }
    }

    function Test-KMSValueIrregular {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
        $blacklist = @(
            "digiboy", "kmsdigital", "kmspico", "kms\.su", "kms8\.msguides", "kms9\.msguides",
            "kms\.cafe", "kmsauto", "vlmcsd", "kms-r1n", "auto\.kms", "technet24",
            "e8\.us\.to", "kms\.xspace", "zerothis",
            "127\.0\.0\.2", "127\.0\.0\.3", "0\.0\.0\.0", "255\.255\.255\.255", "192\.0\.2\."
        )
        foreach ($p in $blacklist) { if ($Value -match $p) { return $true } }
        return $false
    }

    function Remove-AppxSafe {
        param([string]$Pattern)
        if ($script:IsDryRun) { $ctx.DryRunActions.Add("[DRY-RUN] Remove-Appx: $Pattern"); return }
        $pkgList = if ($null -ne $ctx.InstalledCache) {
            $ctx.InstalledCache | Where-Object { $_.Name -like $Pattern }
        }
        else {
            Get-AppxPackage -Name $Pattern -AllUsers -ErrorAction SilentlyContinue
        }
        foreach ($pkg in $pkgList) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                Write-Log "   Appx [$($pkg.Name)] desinstalado." "DarkGray"
            }
            catch {
                Write-Log "   [WARN] $($pkg.Name): $($_.Exception.Message -replace '\n','')" "DarkYellow"
            }
        }
        if ($null -ne $ctx.ProvisionedCache) {
            $ctx.ProvisionedCache | Where-Object { $_.DisplayName -like $Pattern } | ForEach-Object {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null
                }
                catch {
                    Write-Log "   [WARN] Provisioned $($_.DisplayName): $($_.Exception.Message -replace '\n','')" "DarkYellow"
                }
            }
        }
    }

    function Invoke-Step {
        param([string]$Section, [string]$Label, [scriptblock]$Action)
        if (Test-Skip $Section) { Write-Log "   [$Section] OMITIDO por -Skip" "DarkYellow"; return }
        $ctx.StepNum++
        $stepTag = $ctx.StepNum.ToString("D2") + " $Section"
        if ($script:IsDryRun) {
            $msg = "  [DRY-RUN] $stepTag -- $Label"
            Write-Log $msg "DarkGray"; $ctx.DryRunActions.Add($msg); $ctx.StepsOk++; return
        }
        Write-Log "[$stepTag] $Label" "Cyan"
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Stop"
        try { & $Action; $ctx.StepsOk++ }
        catch {
            Write-Log "[ERROR] $Section : $($_.Exception.Message)" "Red"
            $ctx.StepsFail++; $ctx.FailedModules.Add($Section)
        }
        finally { $ErrorActionPreference = $prevEAP }
    }

    function Test-PendingReboot {
        $cbsKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
        $wuKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        $smKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        $pfroExists = $false
        try {
            $smProps = Get-ItemProperty -LiteralPath $smKey -ErrorAction Stop
            $pfro = $smProps.PendingFileRenameOperations
            $pfroExists = (@($pfro)).Count -gt 0
        }
        catch { }
        return (Test-Path $cbsKey) -or (Test-Path $wuKey) -or $pfroExists
    }

    # FIX-B01: solo EDR de terceros conocidos
    function Test-AVInterference {
        $edrProcs = @(Get-Process csagent, falconctl, carbonblack -ErrorAction SilentlyContinue)
        return ($edrProcs.Count -gt 0)
    }

    function Test-SafeMode { return $env:SAFEBOOT_OPTION }

    function Backup-Registry {
        New-Item $BackupDir -ItemType Directory -Force | Out-Null
        & reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "$BackupDir\Explorer.reg"       /y 2>$null
        & reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Search"            "$BackupDir\Search.reg"         /y 2>$null
        & reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection"          "$BackupDir\DataCollection.reg" /y 2>$null
        & reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"           "$BackupDir\WindowsUpdate.reg"  /y 2>$null
        & reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows"                         "$BackupDir\Policies.reg"       /y 2>$null
        Write-Log "   Backup de registro en $BackupDir" "Green"
    }

    #endregion -- HELPERS

    #region -- MODULOS v2.5.4 (C1-C4) ----------------------------------------

    # FIX-B04: InterfaceIndex explicito en Get-NetIPAddress
    function Invoke-ModuleNICTuning {
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false })
        if ($adapters.Count -eq 0) { Write-Log "   [NICTuning] Sin adaptadores fisicos activos." "DarkYellow"; return }

        foreach ($nic in $adapters) {
            Write-Log "   [NICTuning] $($nic.Name) -- $($nic.InterfaceDescription)" "DarkGray"
            try {
                Set-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword "FlowControl" -RegistryValue 0 -ErrorAction Stop
                Write-Log "      FlowControl=0" "DarkGray"
            }
            catch {
                try {
                    Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName "Flow Control" -DisplayValue "Disabled" -ErrorAction Stop
                    Write-Log "      FlowControl=Disabled (DisplayName)" "DarkGray"
                }
                catch { Write-Log "      FlowControl: no soportado." "DarkGray" }
            }
            try {
                Set-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword "EEE" -RegistryValue 0 -ErrorAction Stop
                Write-Log "      EEE=0" "DarkGray"
            }
            catch {
                try {
                    Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName "Energy Efficient Ethernet" -DisplayValue "Disabled" -ErrorAction Stop
                    Write-Log "      EEE=Disabled (DisplayName)" "DarkGray"
                }
                catch { Write-Log "      EEE: no soportado." "DarkGray" }
            }
            try {
                Set-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword "InterruptModeration" -RegistryValue 1 -ErrorAction Stop
                Write-Log "      InterruptModeration=1" "DarkGray"
            }
            catch { Write-Log "      InterruptModeration: no soportado." "DarkGray" }

            # FIX-B04: InterfaceIndex explicito
            $nicIPs = @(
                Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty IPAddress |
                Where-Object { $_ -and $_ -ne "0.0.0.0" }
            )
            if ($nicIPs.Count -eq 0) { Write-Log "      Sin IPs IPv4 en $($nic.Name). Nagle omitido." "DarkGray"; continue }

            $ifaceRoot = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
            foreach ($guid in @(Get-ChildItem -LiteralPath $ifaceRoot -ErrorAction SilentlyContinue)) {
                $props = Get-ItemProperty -LiteralPath $guid.PSPath -ErrorAction SilentlyContinue
                $dhcpIP = if ($null -ne $props -and $null -ne $props.PSObject.Properties["DhcpIPAddress"]) { $props.DhcpIPAddress } else { "" }
                $staticIP = if ($null -ne $props -and $null -ne $props.PSObject.Properties["IPAddress"]) { @($props.IPAddress) } else { @() }
                $allIPs = (@($dhcpIP) + $staticIP) | Where-Object { $_ -and $_ -ne "0.0.0.0" }
                if ($allIPs | Where-Object { $_ -in $nicIPs }) {
                    $guidPath = "$ifaceRoot\$($guid.PSChildName)"
                    Set-RegTracked -Path $guidPath -Name "TcpAckFrequency" -Value 1 -Type DWord
                    Set-RegTracked -Path $guidPath -Name "TCPNoDelay"      -Value 1 -Type DWord
                    Write-Log "      Nagle deshabilitado en $($guid.PSChildName)" "DarkGray"
                    break
                }
            }
        }
    }

    function Invoke-ModuleInputTuning {
        $mousePath = "HKCU:\Control Panel\Mouse"
        Set-RegTracked -Path $mousePath -Name "MouseSpeed"      -Value "0" -Type String
        Set-RegTracked -Path $mousePath -Name "MouseThreshold1" -Value "0" -Type String
        Set-RegTracked -Path $mousePath -Name "MouseThreshold2" -Value "0" -Type String
        Write-Log "   [InputTuning] Aceleracion de raton deshabilitada." "DarkGray"
        Set-RegTracked -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value "0" -Type String
        Write-Log "   [InputTuning] KeyboardDelay=0." "DarkGray"
    }

    function Invoke-ModuleMSITuning {
        $targets = [System.Collections.Generic.List[object]]::new()
        $gpus = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.PNPClass -eq "Display" -and $_.Status -eq "OK" -and $_.DeviceID -like "PCI*" }
        $nvmes = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq "OK" -and $_.DeviceID -like "PCI*" -and $_.Name -match "NVM|NVMe|Non-Volatile" }
        foreach ($g in $gpus) { $targets.Add($g) }
        foreach ($n in $nvmes) { $targets.Add($n) }
        if ($targets.Count -eq 0) { Write-Log "   [MSITuning] No se detectaron dispositivos PCI elegibles." "DarkYellow"; return }
        $enumRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum"
        foreach ($dev in $targets) {
            $msiPath = "$enumRoot\$($dev.DeviceID)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            Write-Log "   [MSITuning] $($dev.Name)" "DarkGray"
            try {
                Set-RegTracked -Path $msiPath -Name "MSISupported"      -Value 1 -Type DWord
                Set-RegTracked -Path $msiPath -Name "InterruptPriority" -Value 2 -Type DWord
                Write-Log "      MSISupported=1, InterruptPriority=2 (PENDINGREBOOT)" "DarkGray"
            }
            catch { Write-Log "      [WARN] $($dev.Name): $($_.Exception.Message)" "DarkYellow" }
        }
        if (-not $ctx.RebootRequired.Contains("MSITuning")) { $ctx.RebootRequired.Add("MSITuning") }
        Write-Log "   [MSITuning] Reinicio necesario." "Yellow"
    }

    # FIX-C18: bcdedit añade entrada manual a ctx.RegDiff para aparecer en Verify
    function Invoke-ModuleVBSTuning {
        if (-not $DisableVBS.IsPresent) { Write-Log "   [VBSTuning] Omitido: requiere -DisableVBS." "DarkYellow"; return }
        $compSys = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($null -ne $compSys -and $compSys.PartOfDomain) { Write-Log "   [VBSTuning] OMITIDO: equipo en dominio." "Yellow"; return }
        $dgRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
        $dgProps = Get-ItemProperty -LiteralPath $dgRegPath -ErrorAction SilentlyContinue
        if ($null -ne $dgProps -and $null -ne $dgProps.PSObject.Properties["Locked"] -and $dgProps.Locked -eq 1) {
            Write-Log "   [VBSTuning] OMITIDO: VBS con UEFI Lock." "Yellow"; return
        }
        $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
        if ($null -ne $dg -and $dg.VirtualizationBasedSecurityState -eq 0) { Write-Log "   [VBSTuning] VBS ya deshabilitado." "DarkGray"; return }

        Set-RegTracked -Path $dgRegPath -Name "EnableVirtualizationBasedSecurity" -Value 0 -Type DWord
        Set-RegTracked -Path $dgRegPath -Name "RequirePlatformSecurityFeatures"   -Value 0 -Type DWord
        Set-RegTracked -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" `
            -Name "Enabled" -Value 0 -Type DWord

        if (-not $script:IsDryRun) {
            $bcdOut = & bcdedit /set hypervisorlaunchtype off 2>&1 | Out-String
            Write-Log "   [VBSTuning] bcdedit hypervisorlaunchtype off: $($bcdOut.Trim())" "DarkGray"
            # FIX-C18: entrada manual en RegDiff para que Verify lo incluya
            $ctx.RegDiff.Add([PSCustomObject]@{
                    Path          = "bcdedit"
                    Name          = "hypervisorlaunchtype"
                    Type          = "External"
                    Before        = "auto"
                    AfterExpected = "off"
                    AfterActual   = if ($LASTEXITCODE -eq 0) { "off" } else { "error:$LASTEXITCODE" }
                    PendingReboot = $true
                    Timestamp     = Get-Date
                })
        }
        else { Write-Log "   [DRY-RUN] bcdedit /set hypervisorlaunchtype off" "DarkGray" }

        if (-not $ctx.RebootRequired.Contains("VBSTuning")) { $ctx.RebootRequired.Add("VBSTuning") }
        Write-Log "   [VBSTuning] VBS/HVCI deshabilitado. REBOOT REQUERIDO." "Yellow"
    }

    #endregion -- MODULOS v2.5.4 (C1-C4)
    #region -- MENU INTERACTIVO -----------------------------------------------

    $optWindhawk = $script:UseInstallWindhawk
    if ($Interactive.IsPresent) {
        Clear-Host
        $menuText = @"
+==================================================================+
|           Manolito v2.5.5 -- Optimizador Windows 11              |
+==================================================================+
|  [1] Lite        Estudio basico. Minimo impacto al sistema.      |
|  [2] DevEdu      Dev + gaming + video.  * RECOMENDADO            |
|  [3] Deep        Maxima limpieza. Incluye DISM (irreversible).   |
|  [4] Personalizado  Elige que secciones omitir.                  |
|  [5] DryRun      Simular DevEdu sin aplicar cambios.             |
|  [6] Restore     Revertir cambios criticos al estado original.   |
|  [0] Salir                                                       |
+==================================================================+
"@
        $menuDone = $false
        do {
            Clear-Host
            Write-Host $menuText -ForegroundColor Cyan
            $choice = Read-Host "Elige [0-6]"
            switch ($choice) {
                "1" { $Mode = "Lite"; $menuDone = $true }
                "2" { $Mode = "DevEdu"; $menuDone = $true }
                "3" { $Mode = "Deep"; $menuDone = $true }
                "4" {
                    $Mode = "DevEdu"; $menuDone = $true
                    # FIX-C31: lista completa de secciones validas
                    Write-Log "`nSecciones disponibles (todas):" "Yellow"
                    Write-Log "  Activation, DeKMS, Updates, Defender, HyperV, Bloatware, OneDrive," "DarkGray"
                    Write-Log "  Xbox, Power, UI, Telemetry, SSD, OfflineOS, Privacy, Cleanup,"      "DarkGray"
                    Write-Log "  OptionalFeatures, DiskSpace, ExplorerPerf, DevEnv, AdminTools,"     "DarkGray"
                    Write-Log "  DNS, NICTuning, InputTuning, MSITuning, VBSTuning"                  "DarkGray"
                    $customSkip = Read-Host "`nSecciones a OMITIR separadas por coma (Enter = ninguna)"
                    if ($customSkip.Trim()) {
                        $customSkip -split "\s*,\s*" | ForEach-Object { Add-Skip $_.Trim() }
                    }
                }
                "5" { $Mode = "DevEdu"; $script:IsDryRun = $true; $menuDone = $true }
                "6" { $Mode = "Restore"; $menuDone = $true }
                "0" { Exit-Script 0 }
                default { Write-Log "[WARN] Opcion [$choice] invalida." "Red" }
            }
        } while (-not $menuDone)

        if ($Mode -in @("Lite", "DevEdu", "Deep") -and -not $script:IsDryRun) {
            $optAdminTools = $true
            $optDesgamificar = -not $script:UseGamingMode
            $optDNS = $script:UseSetSecureDNS
            $optWindhawk = $script:UseInstallWindhawk
            $optDeKMS = $true
            # FIX-C27: toggle explicito para InputTuning
            $optInputTuning = $script:UseGamingMode
            if (Test-Skip "AdminTools") { $optAdminTools = $false }
            if (Test-Skip "DeKMS") { $optDeKMS = $false }
            if (Test-Skip "InputTuning") { $optInputTuning = $false }

            $confirmToggle = $false
            do {
                Clear-Host
                $toggleText = @"
+================================== TOGGLES =================================+
|  [1] Instalar Kit Sysadmin (Winget)    : [$(if ($optAdminTools)   {'X'} else {' '})] SI / [ ] NO                   |
|  [2] Desgamificar (Eliminar Xbox)      : [$(if ($optDesgamificar) {'X'} else {' '})] SI / [ ] NO                   |
|  [3] Aplicar DNS Seguras (1.1.1.1)     : [$(if ($optDNS)          {'X'} else {' '})] SI / [ ] NO                   |
|  [4] Instalar Windhawk (Mod Manager UI): [$(if ($optWindhawk)     {'X'} else {' '})] SI / [ ] NO                   |
|  [5] Limpiar activador KMS (DeKMS)     : [$(if ($optDeKMS)        {'X'} else {' '})] SI / [ ] NO                   |
|  [6] Input Tuning (latencia raton/tec) : [$(if ($optInputTuning)  {'X'} else {' '})] SI / [ ] NO                   |
|  [0] CONFIRMAR Y EJECUTAR                                                  |
+============================================================================+
"@
                Write-Host $toggleText -ForegroundColor Cyan
                $toggleChoice = Read-Host "Elige [0-6]"
                switch ($toggleChoice) {
                    "1" { $optAdminTools = -not $optAdminTools }
                    "2" { $optDesgamificar = -not $optDesgamificar }
                    "3" { $optDNS = -not $optDNS }
                    "4" { $optWindhawk = -not $optWindhawk }
                    "5" { $optDeKMS = -not $optDeKMS }
                    "6" { $optInputTuning = -not $optInputTuning }
                    "0" { $confirmToggle = $true }
                    default { Write-Host "  [WARN] Opcion invalida." -ForegroundColor DarkYellow }
                }
            } while (-not $confirmToggle)

            if ($optAdminTools) { $ctx.SkipList.Remove("AdminTools")  | Out-Null } else { Add-Skip "AdminTools" }
            if ($optDeKMS) { $ctx.SkipList.Remove("DeKMS")       | Out-Null } else { Add-Skip "DeKMS" }
            # FIX-C27: aplicar decision de InputTuning del toggle
            if ($optInputTuning) { $ctx.SkipList.Remove("InputTuning") | Out-Null } else { Add-Skip "InputTuning" }
            $script:UseGamingMode = -not $optDesgamificar
            $script:UseSetSecureDNS = $optDNS
            $script:UseInstallWindhawk = $optWindhawk
        }
    }

    #endregion -- MENU INTERACTIVO

    #region -- APLICAR SKIPS POR MODO -----------------------------------------

    switch ($Mode) {
        "Lite" {
            foreach ($s in @("HyperV", "Xbox", "Power", "SSD", "DiskSpace", "NICTuning", "MSITuning", "VBSTuning", "DevEnv", "AdminTools", "InputTuning")) {
                # FIX-BUG01/04
                Add-Skip $s
            }
        }
        "DevEdu" { Add-Skip "HyperV" }  # FIX-BUG07: HyperV solo en Deep o explícito
        "Deep" { $ctx.AggressiveDisk = $true 
		 Add-Skip HyperV
	} 
    }
    if ($SkipAdminTools.IsPresent) { Add-Skip "AdminTools" }
    # FIX-C27: solo omitir InputTuning en modo no-interactivo sin GamingMode
    #          (en interactivo lo controla el toggle explicitamente)
    if (-not $script:UseGamingMode -and -not $Interactive.IsPresent) {
        Add-Skip "InputTuning"
        Write-Log "[INFO] InputTuning omitido: requiere -GamingMode o -Interactive." "DarkYellow"
    }

    #endregion

    #region -- PREFLIGHT CHECKS -----------------------------------------------

    # FIX-C09: Check es verdaderamente solo lectura: cortocircuitar ANTES del preflight
    if ($Mode -eq "Check") {
        Write-Log "[Check] Modo auditoria: preflight, backup y cachés omitidos." "DarkGray"
        # saltar directamente a Invoke-ModuleCheck al final del bloque
    }
    else {

        # FIX-C04: proteger Read-Host de reboot pendiente con guarda isUnattended
        if ($Mode -ne "Restore" -and -not $script:IsDryRun -and (Test-PendingReboot)) {
            # FIX-BUG10
            if ($Force.IsPresent) {
                Write-Warning "[[!]] Reboot pendiente. -Force activo: continuando."
            }
            else {
                $isUnattended = -not [Environment]::UserInteractive
                if ($isUnattended) {
                    Write-Warning "[[!]] Reboot pendiente en sesion no interactiva. Continuando automaticamente."
                }
                else {
                    Write-Warning "[[!]] Hay un reinicio pendiente. Reinicia antes de continuar."
                    $continueAny = Read-Host "Continuar de todos modos? [s/N]"
                    if ($continueAny -notmatch "^[sS]$") { Exit-Script 2 }
                }
            }
        }

        if ($script:IsDryRun) {
            Write-Log "[DRY-RUN] Backup de registro omitido." "DarkYellow"
        }
        elseif ($Mode -eq "Restore") {
            Write-Log "[INFO] Backup omitido en modo Restore." "DarkYellow"
        }
        else {
            Backup-Registry
        }

        if (Test-SafeMode) {
            Write-Host "[ERROR] Manolito no debe ejecutarse en modo seguro." -ForegroundColor Red
            Exit-Script 1
        }

        if (Test-AVInterference) {
            Write-Warning "[[!]] EDR de terceros detectado (CrowdStrike/CarbonBlack). Algunas operaciones pueden fallar."
        }

        if (-not $script:IsDryRun -and $Mode -ne "Restore") {
            $ctx.ProvisionedCache = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
            $ctx.InstalledCache = Get-AppxPackage -AllUsers  -ErrorAction SilentlyContinue
        }

    } # fin bloque non-Check

    $dryLabel = if ($script:IsDryRun) { " (DRY-RUN)" } else { "" }
    $skipLabel = if ($ctx.SkipList.Count -gt 0) { " | Skip: $($ctx.SkipList -join ',')" } else { "" }
    $psLabel = if ($PS7Plus) { "PS7+" } else { "PS$PSMajor" }
    Write-Log "================================================================" "Green"
    Write-Log "Manolito v2.5.5 -- Modo: $Mode$dryLabel$skipLabel | $psLabel" "Green"
    Write-Log "Licencia: GNU GPLv3 (uso comercial requiere acuerdo)" "Yellow"
    Write-Log "OS: $OSCaption  |  Build: $WinBuild  |  SKU: $SKULabel" "DarkGray"
    Write-Log "Log: $LogFile  |  Transcript: $TranscriptPath" "DarkGray"
    if (-not $script:IsDryRun -and $Mode -notin @("Restore", "Check")) {
        Write-Log "Backup registro: $BackupDir" "DarkGray"
    }
    Write-Log "================================================================" "Green"

    #endregion

    #region -- MODO RESTORE ---------------------------------------------------

    function Invoke-RestoreMode {
        Write-Log "MODO RESTORE: revirtiendo al estado Windows por defecto..." "Yellow"

        # FIX-C08: advertir si ResetBase fue aplicado (irreversible por DISM)
        if ($ctx.ResetBaseApplied) {
            Write-Log "  [!] ADVERTENCIA: DISM /ResetBase fue aplicado en esta sesion." "Yellow"
            Write-Log "      La capacidad de desinstalar updates anteriores NO puede restaurarse." "Yellow"
        }

        Set-RegistryValue $REG_WU_AU "AUOptions"                     4
        Set-RegistryValue $REG_WU_AU "NoAutoUpdate"                  0
        Set-RegistryValue $REG_WU_AU "NoAutoRebootWithLoggedOnUsers" 0
        Set-RegistryValue $REG_DATACOLLECTION  "AllowTelemetry"      1
        Set-RegistryValue $REG_DATACOLLECTION2 "AllowTelemetry"      1
        Set-RegistryValue $REG_DATACOLLECTION2 "MaxTelemetryAllowed" 1
        Start-ServiceSafe "DiagTrack"
        Start-ServiceSafe "SysMain"

        # FIX-C05: reactivar servicios Xbox
        foreach ($xsvc in @("XblAuthManager", "XblGameSave", "XboxGipSvc", "XboxNetApiSvc")) {
            Start-ServiceSafe $xsvc
        }

        # FIX-C06: deshabilitar Hyper-V si fue habilitado por el modulo
        if (-not $script:IsDryRun) {
            $hvFeat = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -ErrorAction SilentlyContinue
            if ($null -ne $hvFeat -and $hvFeat.State -eq "Enabled") {
                Write-Log "   [Restore] Deshabilitando Hyper-V..." "DarkGray"
                Disable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -NoRestart -ErrorAction SilentlyContinue | Out-Null
                if (-not $ctx.RebootRequired.Contains("Restore-HyperV")) { $ctx.RebootRequired.Add("Restore-HyperV") }
                Write-Log "   [Restore] Hyper-V deshabilitado. Reinicio requerido." "Yellow"
            }
        }

        # FIX-C07: revertir VBS/HVCI y bcdedit
        Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" "EnableVirtualizationBasedSecurity" 1
        Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" "RequirePlatformSecurityFeatures"   1
        Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" 1
        if (-not $script:IsDryRun) {
            $bcdRest = & bcdedit /set hypervisorlaunchtype auto 2>&1 | Out-String
            Write-Log "   [Restore] bcdedit hypervisorlaunchtype auto: $($bcdRest.Trim())" "DarkGray"
        }
        else { Write-Log "   [DRY-RUN] bcdedit /set hypervisorlaunchtype auto" "DarkGray" }

        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 1
        Set-RegistryValue $REG_COPILOT_USER    "TurnOffWindowsCopilot"    0
        Set-RegistryValue $REG_COPILOT_MACHINE "TurnOffWindowsCopilot"    0
        Set-RegistryValue $REG_EXPLORER_ADV    "ShowCopilotButton"        1
        Set-PrivacyConsent -Value "Allow"
        Set-RegistryValue $REG_POLICIES_SYSTEM "NoConnectedUser"          0
        Set-RegistryValue $REG_SYSTEM_POLICIES "NoMicrosoftAccount"       0
        Set-RegistryValue $REG_WORKPLACE_JOIN  "BlockAADWorkplaceJoin"    0
        Set-RegistryValue $REG_MSA             "DisableUserAuth"          0
        Set-RegistryValue $REG_OOBE            "DisablePrivacyExperience" 0
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 1
        Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 0
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 0
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 0

        # FIX-C24: revertir OneDrive policy, GameDVR y AppCapture
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" 0
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"  "AllowGameDVR"        1
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 1

        # FIX-C25: revertir RealTimeIsUniversal
        if (-not $script:IsDryRun) {
            Remove-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" `
                -Name "RealTimeIsUniversal" -ErrorAction SilentlyContinue
            Write-Log "   [Restore] RealTimeIsUniversal eliminado (vuelta a hora local HW)." "DarkGray"
        }

        if (-not $script:IsDryRun) {
            Remove-ItemProperty -LiteralPath $REG_EDGE_POLICIES -Name "HubsSidebarEnabled"           -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $REG_EDGE_POLICIES -Name "EdgeShoppingAssistantEnabled" -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $REG_EDGE_POLICIES -Name "StartupBoostEnabled"          -ErrorAction SilentlyContinue
        }

        if (-not $script:IsDryRun) {
            $restAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue |
                Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false })
            $dnsFromDisk = @{}
            if (Test-Path $DNSBackupFile) {
                try {
                    $raw = Get-Content $DNSBackupFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    $raw.PSObject.Properties | ForEach-Object { $dnsFromDisk[$_.Name] = $_.Value }
                    Write-Log "   [Restore] DNS backup cargado desde: $DNSBackupFile" "DarkGray"
                }
                catch {
                    Write-Log "   [Restore][WARN] No se pudo leer $DNSBackupFile. Usando DHCP." "DarkYellow"
                }
            }
            else {
                Write-Log "   [Restore] dns_backup.json no existe. Aplicando DHCP." "DarkYellow"
            }
            foreach ($ra in $restAdapters) {
                $backup = if ($dnsFromDisk.ContainsKey($ra.Name)) { $dnsFromDisk[$ra.Name] }
                elseif ($ctx.DNSBackup.ContainsKey($ra.Name)) { $ctx.DNSBackup[$ra.Name] }
                else { $null }
                if ($null -ne $backup -and @($backup.IPv4).Count -gt 0) {
                    $allDNS = @($backup.IPv4) + @($backup.IPv6 | Where-Object { $_ })
                    Set-DnsClientServerAddress -InterfaceAlias $ra.Name -ServerAddresses $allDNS -ErrorAction SilentlyContinue
                    Write-Log "   [Restore] DNS restaurado en $($ra.Name): $($allDNS -join ', ')" "DarkGray"
                }
                else {
                    Set-DnsClientServerAddress -InterfaceAlias $ra.Name -ResetServerAddresses -ErrorAction SilentlyContinue
                    Write-Log "   [Restore] DNS -> DHCP en $($ra.Name)" "DarkGray"
                }
            }
        }

        # FIX-C32: re-habilitar tareas telemetria estaticas
        foreach ($t in $TelemetryTasks) { Enable-ScheduledTaskSafe $t.Path $t.Name }
        # FIX-C32: re-habilitar tareas telemetria dinamicas (barrido por path)
        if (-not $script:IsDryRun) {
            foreach ($ceipPath in @(
                    "\Microsoft\Windows\Application Experience\",
                    "\Microsoft\Windows\Customer Experience Improvement Program\"
                )) {
                @(Get-ScheduledTask -TaskPath $ceipPath -ErrorAction SilentlyContinue |
                    Where-Object { $_.State -eq 'Disabled' }) | ForEach-Object {
                    $_ | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
                    Write-Log "   [Restore] Task re-habilitada: $($_.TaskName)" "DarkGray"
                }
            }
        }

        Write-Log "================================================================" "Green"
        Write-Log "Restore completado. Reinicia para aplicar los cambios." "Green"
        Write-Log "NOTA: Apps desinstaladas, DISM /ResetBase y cambios DISM NO se revierten." "Yellow"
        if ($ctx.RebootRequired.Count -gt 0) {
            Write-Log "  [!] REINICIO REQUERIDO: $($ctx.RebootRequired -join ', ')" "Yellow"
        }
        Exit-Script 0
    }

    if ($Mode -eq "Restore") {
        Write-Host ""
        Write-Host "+==========================================================+" -ForegroundColor Yellow
        Write-Host "|  [!]  RESTAURACION AL ESTADO WINDOWS POR DEFECTO         |" -ForegroundColor Yellow
        Write-Host "|  Revertira: WU, Telemetria, Servicios, DNS, Edge,        |" -ForegroundColor Yellow
        Write-Host "|             Xbox, VBS, HyperV, GameDVR, RTC UTC, etc.    |" -ForegroundColor Yellow
        Write-Host "|  NO revertira: apps desinstaladas ni DISM /ResetBase.    |" -ForegroundColor Yellow
        Write-Host "+==========================================================+" -ForegroundColor Yellow
        if ($Force.IsPresent) {
            Write-Log "[Restore] -Force activo: confirmacion automatica." "DarkYellow"
        }
        else {
            # FIX-C04: guarda isUnattended tambien en Restore
            $isUnattended = -not [Environment]::UserInteractive
            if ($isUnattended) {
                Write-Log "[Restore] Sesion no interactiva: confirmacion automatica." "DarkYellow"
            }
            else {
                $confirmRestore = Read-Host "Confirmar restauracion? [s/N]"
                if ($confirmRestore -notmatch "^[sS]$") {
                    Write-Log "Restauracion cancelada." "DarkYellow"; Exit-Script 0
                }
            }
        }
        Invoke-RestoreMode
    }

    #endregion -- MODO RESTORE

    #region -- ACTIVACION -----------------------------------------------------

    if ($Mode -ne "Check" -and -not $script:IsDryRun -and -not (Test-Skip "Activation") -and $script:ProductKey -match "XXXXX") {
        if ($Force.IsPresent) {
            Add-Skip "Activation"
            Write-Log "[INFO] Activation omitida: -Force activo y clave no configurada." "DarkYellow"
        }
        else {
            $isUnattended = -not [Environment]::UserInteractive
            if ($isUnattended) {
                Add-Skip "Activation"
                Write-Log "[INFO] Activation omitida: sesion no interactiva y clave no configurada." "DarkYellow"
            }
            else {
                $promptKey = Read-Host "Introduce tu clave de producto (Enter para omitir):"
                if ($promptKey.Trim()) { $script:ProductKey = $promptKey.Trim() }
                else { Add-Skip "Activation"; Write-Log "[INFO] Licencia omitida por usuario." "DarkYellow" }
            }
        }
    }
    if ($script:IsDryRun -and -not (Test-Skip "Activation")) {
        Add-Skip "Activation"; Write-Log "[DRY-RUN] Activation omitida." "DarkYellow"
    }

    #endregion

    #region -- MODO CHECK -----------------------------------------------------

    function Invoke-ModuleCheck {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        $results.Add((Invoke-Check -Name "VBS / Memory Integrity" -RequiresAdmin $true -ScriptBlock {
                    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard `
                        -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
                    if ($null -eq $dg) { return @{ Status = "SKIP"; Detail = "Win32_DeviceGuard no disponible." } }
                    $state = [int]$dg.VirtualizationBasedSecurityState
                    $label = switch ($state) { 0 { "Disabled" } 1 { "Enabled-NotRunning" } 2 { "Enabled-Running" } default { "State=$state" } }
                    if ($state -eq 0) { return @{ Status = "OK"; Detail = "VBS deshabilitado ($label)." } }
                    else { return @{ Status = "WARN"; Detail = "VBS activo ($label). Usa -DisableVBS en Deep." } }
                }))

        $results.Add((Invoke-Check -Name "Ultimate Performance Plan" -RequiresAdmin $false -ScriptBlock {
                    $schemeOut = & powercfg.exe /getactivescheme 2>&1 | Out-String
                    $ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
                    if ($schemeOut -match "([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})") {
                        if ($Matches[1].ToLower() -eq $ultimateGuid) { return @{ Status = "OK"; Detail = "Ultimate Performance activo." } }
                        $namePart = if ($schemeOut -match "\(([^)]+)\)") { $Matches[1].Trim() } else { $Matches[1] }
                        return @{ Status = "WARN"; Detail = "Plan activo: $namePart." }
                    }
                    return @{ Status = "WARN"; Detail = "No se pudo leer el plan activo." }
                }))

        $nvGpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "NVIDIA" } | Select-Object -First 1
        if ($null -ne $nvGpu) {
            $results.Add((Invoke-Check -Name "NVIDIA Telemetry" -RequiresAdmin $false -ScriptBlock {
                        $svc = Get-Service "NvTelemetryContainer" -ErrorAction SilentlyContinue
                        if ($null -eq $svc) { return @{ Status = "OK"; Detail = "NvTelemetryContainer no instalado." } }
                        if ($svc.Status -eq "Running") { return @{ Status = "FAIL"; Detail = "NvTelemetryContainer corriendo." } }
                        return @{ Status = "OK"; Detail = "NvTelemetryContainer: $($svc.Status)." }
                    }))
        }
        else {
            $results.Add([PSCustomObject]@{ Name = "NVIDIA Telemetry"; Status = "SKIP"; Detail = "Sin GPU NVIDIA." })
        }

        $results.Add((Invoke-Check -Name "Hibernacion" -RequiresAdmin $false -ScriptBlock {
                    $props = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -ErrorAction SilentlyContinue
                    if ($null -eq $props -or $null -eq $props.PSObject.Properties["HibernateEnabled"]) {
                        return @{ Status = "OK"; Detail = "HibernateEnabled ausente (deshabilitada)." }
                    }
                    $val = [int]$props.HibernateEnabled
                    if ($val -eq 0) { return @{ Status = "OK"; Detail = "HibernateEnabled=0." } }
                    else { return @{ Status = "WARN"; Detail = "HibernateEnabled=$val. Espacio en SSD." } }
                }))

        # FIX-C26: Check Nagle sin break, reportar estado por cada NIC activa
        $results.Add((Invoke-Check -Name "Nagle Algorithm (todas las NICs)" -RequiresAdmin $false -ScriptBlock {
                    $ifaceRoot = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
                    $nics = @(Get-NetAdapter -ErrorAction SilentlyContinue |
                        Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false })
                    if ($nics.Count -eq 0) { return @{ Status = "SKIP"; Detail = "Sin adaptadores fisicos activos." } }

                    $allOff = $true; $detail = ""
                    foreach ($nic in $nics) {
                        $nicIPs = @(
                            Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                            Select-Object -ExpandProperty IPAddress |
                            Where-Object { $_ -and $_ -ne "0.0.0.0" }
                        )
                        if ($nicIPs.Count -eq 0) { $detail += "$($nic.Name):NO-IP "; continue }
                        $nagleOff = $false
                        foreach ($guid in @(Get-ChildItem -LiteralPath $ifaceRoot -ErrorAction SilentlyContinue)) {
                            $p = Get-ItemProperty -LiteralPath $guid.PSPath -ErrorAction SilentlyContinue
                            $dhcpIP = if ($null -ne $p -and $null -ne $p.PSObject.Properties["DhcpIPAddress"]) { $p.DhcpIPAddress } else { "" }
                            $static = if ($null -ne $p -and $null -ne $p.PSObject.Properties["IPAddress"]) { @($p.IPAddress) } else { @() }
                            $allIPs = (@($dhcpIP) + $static) | Where-Object { $_ -and $_ -ne "0.0.0.0" }
                            if ($allIPs | Where-Object { $_ -in $nicIPs }) {
                                $freq = if ($null -ne $p.PSObject.Properties["TcpAckFrequency"]) { [int]$p.TcpAckFrequency } else { -1 }
                                $nodelay = if ($null -ne $p.PSObject.Properties["TCPNoDelay"]) { [int]$p.TCPNoDelay } else { -1 }
                                $nagleOff = ($freq -eq 1 -and $nodelay -eq 1)
                                break
                            }
                        }
                        $detail += "$($nic.Name):$(if ($nagleOff) {'OFF'} else {'ON'}) "
                        if (-not $nagleOff) { $allOff = $false }
                    }
                    $status = if ($allOff) { "OK" } else { "WARN" }
                    return @{ Status = $status; Detail = $detail.Trim() }
                }))

        $colW = 42
        $sep = "+" + ("-" * ($colW + 2)) + "+" + ("-" * 8) + "+" + ("-" * 46) + "+"
        Write-Log "" "White"
        Write-Log $sep "DarkGray"
        Write-Log ("| {0,-$colW} | {1,-6} | {2,-44} |" -f "CHECK", "STATUS", "DETAIL") "White"
        Write-Log $sep "DarkGray"
        $cOK = 0; $cWarn = 0; $cFail = 0; $cSkip = 0
        foreach ($r in $results) {
            $color = switch ($r.Status) {
                "OK" { $cOK++; "Green" }
                "WARN" { $cWarn++; "Yellow" }
                "FAIL" { $cFail++; "Red" }
                "SKIP" { $cSkip++; "DarkGray" }
                default { "White" }
            }
            $nameCell = if ($r.Name.Length -gt $colW) { $r.Name.Substring(0, $colW - 1) + "~" } else { $r.Name }
            $detailCell = if ($r.Detail.Length -gt 44) { $r.Detail.Substring(0, 43) + "~" } else { $r.Detail }
            Write-Log ("| {0,-$colW} | {1,-6} | {2,-44} |" -f $nameCell, $r.Status, $detailCell) $color
        }
        Write-Log $sep "DarkGray"
        $sc = if ($cFail -gt 0) { "Red" } elseif ($cWarn -gt 0) { "Yellow" } else { "Green" }
        Write-Log ("[Check] OK=$cOK WARN=$cWarn FAIL=$cFail SKIP=$cSkip | Total=$($results.Count)") $sc
    }

    # FIX-C09: Check ejecuta directamente sin pasar por preflight/backup/caches
    if ($Mode -eq "Check") { Invoke-ModuleCheck; Exit-Script 0 }

    #endregion -- MODO CHECK

    #region -- MODULOS PRINCIPALES --------------------------------------------

    # FIX-C02: solo limpiar si el valor esta en la lista negra explicita
    # FIX-C03: deteccion KMS locale-agnostic via CIM
    # FIX-C20: desatendido solo via [Environment]::UserInteractive
    # FIX-C21: verificar Stop-Service sppsvc realmente detuvo el servicio
    # FIX-C23: Remove-Item con ErrorAction Stop + try/catch
    function Invoke-ModuleDeKMS {
        # FIX-C03: leer KMS via CIM (locale-agnostic)
        $currentKMS = ""
        try {
            $sls = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop
            $currentKMS = if ($null -ne $sls -and $sls.KeyManagementServiceMachine) {
                $sls.KeyManagementServiceMachine.Trim()
            }
            else { "" }
        }
        catch {
            # Fallback a slmgr si CIM no esta disponible
            $dlvRaw = & cscript //Nologo "$env:SystemRoot\System32\slmgr.vbs" /dlv 2>&1 | Out-String
            if ($dlvRaw -match "KMS\s+machine\s+name[^:]*:\s*(.+)") { $currentKMS = $Matches[1].Trim() }
            elseif ($dlvRaw -match "Nombre.*maquina.*KMS[^:]*:\s*(.+)") { $currentKMS = $Matches[1].Trim() }
        }

        # FIX-C02: solo actuar si el valor esta en la lista negra
        #          Todo lo que NO esta en blacklist se preserva (FQDN corp, VPN, etc.)
        $isBlacklisted = Test-KMSValueIrregular $currentKMS
        if ($currentKMS -and -not $isBlacklisted) {
            Write-Log "   [DeKMS] KMS configurado ($currentKMS) no esta en lista negra. Preservado." "Yellow"
            return
        }
        if ($currentKMS) { Write-Log "   [DeKMS] KMS irregular detectado: $currentKMS" "Yellow" }
        else { Write-Log "   [DeKMS] Sin servidor KMS configurado." "DarkGray" }
        if ($script:IsDryRun) { $ctx.DryRunActions.Add("[DeKMS] Limpieza KMS simulada"); return }

        if ($currentKMS) {
            if ($WinBuild -ge 26040) {
                Write-Log "   [DeKMS] Build ${WinBuild}: grace period KMS no renovable." "Yellow"
            }
            # FIX-C20: desatendido solo via UserInteractive (no host.Name)
            $isUnattended = $Force.IsPresent -or (-not [Environment]::UserInteractive)
            if (-not $isUnattended) {
                $confirm = Read-Host "   Confirmar limpieza KMS? [s/N]"
                if ($confirm -notmatch "^[sS]$") { Write-Log "   [DeKMS] Cancelado." "Yellow"; return }
            }
            else {
                Write-Log "   [DeKMS] Modo desatendido: confirmacion automatica." "DarkYellow"
            }
        }

        # FIX-C21: verificar que sppsvc realmente se detuvo
        $svcBefore = Get-Service sppsvc -ErrorAction SilentlyContinue
        $sppWasRunning = ($null -ne $svcBefore -and
            $svcBefore.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running)
        $sppStopped = $false

        try {
            Stop-Service sppsvc -Force -ErrorAction SilentlyContinue
            # FIX-C21: re-leer estado post-Stop antes de marcar la bandera
            $svcAfter = Get-Service sppsvc -ErrorAction SilentlyContinue
            $sppStopped = ($null -ne $svcAfter -and
                $svcAfter.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Stopped)
            if (-not $sppStopped) {
                Write-Log "   [DeKMS][WARN] sppsvc no se detuvo (estado: $($svcAfter.Status)). Intentando continuar." "DarkYellow"
            }

            & cscript //Nologo "$env:SystemRoot\System32\slmgr.vbs" /ckms 2>&1 | Out-Null

            $SPP = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform"
            $rootP = Get-ItemProperty -LiteralPath $SPP -ErrorAction SilentlyContinue
            if ($null -ne $rootP -and $null -ne $rootP.PSObject.Properties['KeyManagementServiceName']) {
                if (Test-KMSValueIrregular $rootP.KeyManagementServiceName) {
                    Remove-ItemProperty -LiteralPath $SPP -Name "KeyManagementServiceName" -ErrorAction SilentlyContinue
                    Write-Log "   [DeKMS] KMS eliminado de raiz SPP." "DarkGray"
                }
            }
            foreach ($subName in @("Tokens", "Cache")) {
                $subPath = "$SPP\$subName"
                $subP = Get-ItemProperty -LiteralPath $subPath -ErrorAction SilentlyContinue
                if ($null -ne $subP -and $null -ne $subP.PSObject.Properties['KeyManagementServiceName']) {
                    if (Test-KMSValueIrregular $subP.KeyManagementServiceName) {
                        Remove-ItemProperty -LiteralPath $subPath -Name "KeyManagementServiceName" -ErrorAction SilentlyContinue
                        Write-Log "   [DeKMS] KMS eliminado de $subName." "DarkGray"
                    }
                }
            }

            foreach ($svcName in @("KMS4k", "SppExtComObjPatcher", "vlmcsd", "KMService", "KMSELDI", "KMSAutoS", "KMSAuto")) {
                if (Get-Service $svcName -ErrorAction SilentlyContinue) {
                    Stop-Service $svcName -Force -ErrorAction SilentlyContinue
                    & sc.exe delete $svcName 2>&1 | Out-Null
                    Write-Log "   [DeKMS] Servicio eliminado: $svcName" "Yellow"
                }
            }

            Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -match "HEU_KMSAuto|KMSpico|vlmcsd|KMSAuto|KMSELDI" } |
            ForEach-Object {
                $tp = if ($_.TaskPath) { $_.TaskPath } else { "\" }
                Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $tp -Confirm:$false -ErrorAction SilentlyContinue
                Write-Log "   [DeKMS] Tarea eliminada: $($_.TaskName)" "Yellow"
            }

            # FIX-C23: Remove-Item con ErrorAction Stop + try/catch por archivo
            foreach ($f in @(
                    "$env:SystemRoot\System32\SppExtComObjPatcher.dll",
                    "$env:SystemRoot\System32\vlmcs.exe",
                    "$env:SystemRoot\System32\AutoKMS.exe",
                    "$env:ProgramFiles\KMSAuto\KMSAuto.exe"
                )) {
                if (Test-Path $f) {
                    try {
                        Remove-Item $f -Force -ErrorAction Stop
                        Write-Log "   [DeKMS] Archivo eliminado: $f" "Yellow"
                    }
                    catch {
                        Write-Log "   [DeKMS][WARN] No se pudo eliminar $f : $($_.Exception.Message)" "DarkYellow"
                    }
                }
            }

            try {
                $badConsumers = Get-CimInstance -Namespace root\subscription `
                    -ClassName __EventConsumer -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "KMS|SPP|vlmcsd|SECOH" }
                foreach ($c in $badConsumers) {
                    $escapedName = [regex]::Escape($c.Name)
                    Get-CimInstance -Namespace root\subscription `
                        -ClassName __FilterToConsumerBinding -ErrorAction SilentlyContinue |
                    Where-Object { $_.Consumer -match $escapedName } |
                    ForEach-Object {
                        $_ | Remove-CimInstance -ErrorAction SilentlyContinue
                        Write-Log "   [DeKMS] WMI Binding eliminado: $($c.Name)" "Yellow"
                    }
                    $c | Remove-CimInstance -ErrorAction SilentlyContinue
                    Write-Log "   [DeKMS] WMI Consumer eliminado: $($c.Name)" "Yellow"
                }
            }
            catch {
                Write-Log "   [DeKMS][WARN] WMI cleanup: $($_.Exception.Message)" "DarkYellow"
            }

            $ctx.DeKMSCleaned = $true
            Write-Log "   [DeKMS] Limpieza completada." "Green"
        }
        finally {
            if ($sppStopped -and $sppWasRunning) {
                Start-Service sppsvc -ErrorAction SilentlyContinue
                $svcRestored = Get-Service sppsvc -ErrorAction SilentlyContinue
                if ($null -ne $svcRestored -and $svcRestored.Status -eq 'Running') {
                    Write-Log "   [DeKMS] sppsvc restaurado a Running." "DarkGray"
                }
                else {
                    Write-Log "   [DeKMS][WARN] sppsvc no pudo restaurarse a Running." "DarkYellow"
                }
            }
            elseif (-not $sppWasRunning) {
                Write-Log "   [DeKMS] sppsvc no restaurado: estaba detenido antes." "DarkGray"
            }
        }
    }

    # FIX-C01: filtrar SoftwareLicensingProduct por GUID de Windows OS
    # FIX-C03: stderr de cscript capturado en tmpErr
    function Invoke-ModuleActivation {
        if ($script:ProductKey -match "^XXXXX") {
            Write-Log "   Clave no configurada. Omitiendo activacion." "DarkYellow"; return
        }
        $slmgr = "$env:SystemRoot\System32\slmgr.vbs"

        Write-Log "   Instalando clave de producto..." "DarkGray"
        $ipkResult = & cscript //Nologo $slmgr /ipk $script:ProductKey 2>&1 | Out-String
        if ($ipkResult -match "0x[0-9A-Fa-f]{8}") {
            $hresult = $Matches[0]
            if ($hresult -ne "0x00000000") {
                throw "slmgr /ipk fallo con HRESULT $hresult : $($ipkResult.Trim())"
            }
        }

        Write-Log "   Activando (timeout ${ActivationTimeoutSec}s)..." "DarkGray"
        $tmpOut = Join-Path $env:TEMP "slmgr_ato_$PID.txt"
        $tmpErr = Join-Path $env:TEMP "slmgr_ato_err_$PID.txt"
        $atoProc = Start-Process "cscript.exe" `
            -ArgumentList "//Nologo `"$slmgr`" /ato" `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput $tmpOut `
            -RedirectStandardError  $tmpErr `
            -ErrorAction Stop
        try {
            $completed = $atoProc.WaitForExit($ActivationTimeoutSec * 1000)
            if (-not $completed) {
                Stop-Process -Id $atoProc.Id -Force -ErrorAction SilentlyContinue
                throw "Timeout en slmgr /ato (>${ActivationTimeoutSec}s). Aumenta -ActivationTimeoutSec."
            }
        }
        catch [System.InvalidOperationException] { }

        $atoResult = (Get-Content $tmpOut -ErrorAction SilentlyContinue | Out-String) +
        (Get-Content $tmpErr -ErrorAction SilentlyContinue | Out-String)
        Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue

        if ($atoResult -match "0x[0-9A-Fa-f]{8}") {
            $hresult = $Matches[0]
            if ($hresult -ne "0x00000000") {
                throw "slmgr /ato fallo con HRESULT $hresult : $($atoResult.Trim())"
            }
        }

        # FIX-C01: GUID de ApplicationId exclusivo del OS Windows
        #          (55c92734-d682-4d71-983e-d6ec3f16059f)
        #          Evita falso positivo si Office u otro producto esta licenciado
        $windowsAppId = "55c92734-d682-4d71-983e-d6ec3f16059f"
        $licProduct = Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ApplicationId -eq $windowsAppId -and
            $_.PartialProductKey -and
            $_.LicenseStatus -eq 1
        } | Select-Object -First 1
        if ($null -ne $licProduct) {
            Write-Log "   Windows activado correctamente (OS LicenseStatus=1)." "Green"
        }
        else {
            throw "Fallo de validacion CIM post-activacion (OS ApplicationId). Verifica con: slmgr /xpr"
        }
    }

    # FIX-C15: forzar NoAutoUpdate=0 para no dejar WU desactivado
    function Invoke-ModuleUpdates {
        Set-RegistryValue $REG_WU_AU "AUOptions"                     3
        Set-RegistryValue $REG_WU_AU "NoAutoUpdate"                  0   # FIX-C15
        Set-RegistryValue $REG_WU_AU "NoAutoRebootWithLoggedOnUsers" 1
        Set-RegistryValue $REG_WU_AU "ScheduledInstallDay"           0
        Set-RegistryValue $REG_WU_AU "ScheduledInstallTime"          3
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "DisableWindowsUpdateAccess" 0
        Set-RegTracked -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" `
            -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord
        Write-Log "   [A15] WU configurado (NoAutoUpdate=0, AUOptions=3, drivers protegidos)." "DarkGray"
    }

    function Invoke-ModuleDefender {
        Set-RegistryValue $REG_DEFENDER_SPYNET "SpynetReporting"      0
        Set-RegistryValue $REG_DEFENDER_SPYNET "SubmitSamplesConsent" 2
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" "DisableAntiSpyware" 0
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableBehaviorMonitoring" 0
    }

    # FIX-C10: verificar estado post-Enable con Get-WindowsOptionalFeature
    function Invoke-ModuleHyperV {
        if ($script:IsDryRun) { Write-Log "  [DRY-RUN] HyperV: Enable-WindowsOptionalFeature" "DarkGray"; return }
        $feature = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -ErrorAction SilentlyContinue
        if ($null -ne $feature -and $feature.State -ne "Enabled") {
            Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
            # FIX-C10: re-consultar estado real post-Enable
            $featurePost = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -ErrorAction SilentlyContinue
            if ($null -ne $featurePost -and $featurePost.State -eq "Enabled") {
                if (-not $ctx.RebootRequired.Contains("HyperV")) { $ctx.RebootRequired.Add("HyperV") }
                Write-Log "   Hyper-V habilitado correctamente. Reinicio requerido." "Yellow"
            }
            else {
                $st = if ($null -ne $featurePost) { $featurePost.State } else { "N/A" }
                Write-Log "   [WARN] Hyper-V puede no haberse habilitado (estado post: $st)." "DarkYellow"
            }
        }
        else { Write-Log "   Hyper-V ya estaba habilitado o no disponible." "DarkGray" }
    }

    # FIX-B05: ConcurrentBag para errores de runspaces paralelos
    function Invoke-ModuleBloatware {
        $bloatList = @(
            "*Microsoft.BingNews*", "*Microsoft.BingWeather*", "*Microsoft.BingFinance*",
            "*Microsoft.BingSports*", "*Microsoft.MicrosoftSolitaireCollection*",
            "*Microsoft.MicrosoftMahjong*", "*Microsoft.MicrosoftJigsawPuzzles*",
            "*Microsoft.ZuneMusic*", "*Microsoft.ZuneVideo*",
            "*Microsoft.3DBuilder*", "*Microsoft.Print3D*",
            "*Microsoft.MixedReality.Portal*", "*Microsoft.Microsoft3DViewer*",
            "*Microsoft.Getstarted*", "*Microsoft.WindowsFeedbackHub*",
            "*Microsoft.WindowsMaps*", "*Microsoft.Messaging*",
            "*Microsoft.People*", "*Microsoft.SkypeApp*",
            "*Microsoft.Wallet*", "*Microsoft.StorePurchaseApp*",
            "*Disney*", "*EclipseManager*", "*ActiproSoftwareLLC*",
            "*AdobeSystemsIncorporated.AdobePhotoshopExpress*",
            "*Duolingo*", "*PandoraMediaInc*", "*CandyCrush*", "*BubbleWitch*",
            "*Wunderlist*", "*Flipboard*", "*Twitter*", "*Facebook*",
            "*Spotify*", "*Netflix*", "*TikTok*", "*HiddenCity*"
        )
        if ($PS7Plus) {
            $localProv = $ctx.ProvisionedCache
            $localInst = $ctx.InstalledCache
            $warnBag = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            $bloatList | ForEach-Object -Parallel {
                $pat = $_; $inst = $using:localInst; $bag = $using:warnBag
                $pkgNames = if ($null -ne $inst) {
                    @($inst | Where-Object { $_.Name -like $pat } | Select-Object -ExpandProperty PackageFullName)
                }
                else {
                    @(Get-AppxPackage -Name $pat -AllUsers -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty PackageFullName)
                }
                foreach ($pkgName in $pkgNames) {
                    try { Remove-AppxPackage -Package $pkgName -AllUsers -ErrorAction Stop }
                    catch {
                        $msg = $_.Exception.Message -replace '\n', ''
                        if ($msg -notmatch "0x80070032") { $bag.Add("[WARN] Bloatware: $pkgName : $msg") }
                    }
                }
            } -ThrottleLimit 4
            foreach ($warnMsg in $warnBag) { Write-Log $warnMsg "DarkYellow" }
            $b09Removed = ($bloatList.Count - $warnBag.Count)
            Write-Log "   [Bloatware] Limpieza completada ($b09Removed paquetes eliminados)." "DarkGray"  # FIX-BUG09
            if ($null -ne $localProv) {
                foreach ($pat in $bloatList) {
                    $localProv | Where-Object { $null -ne $_.DisplayName -and $_.DisplayName -like $pat } | ForEach-Object { # FIX-BUG02
                        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
                    }
                }
            }
        }
        else { foreach ($app in $bloatList) { Remove-AppxSafe $app } }
    }

    function Invoke-ModuleOneDrive {
        if ($script:IsDryRun) { Write-Log "  [DRY-RUN] OneDrive: desinstalacion simulada." "DarkGray"; return }
        @(Get-Process "OneDrive" -ErrorAction SilentlyContinue) | ForEach-Object { try { $_.Kill() } catch {} }
        Start-Sleep -Milliseconds 500
        $odUninstalled = $false
        foreach ($setup in @(
                "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
                "$env:SystemRoot\System32\OneDriveSetup.exe",
                "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
            )) {
            if (Test-Path $setup) {
                $proc = Start-Process $setup -ArgumentList "/uninstall" -NoNewWindow -PassThru -Wait -ErrorAction SilentlyContinue
                if ($null -ne $proc -and $proc.ExitCode -eq 0) {
                    Write-Log "   [OneDrive] Desinstalado desde: $setup" "DarkGray"
                    $odUninstalled = $true; break
                }
                else {
                    $ec = if ($null -ne $proc) { $proc.ExitCode } else { "N/A" }
                    Write-Log "   [OneDrive][WARN] $setup ExitCode=$ec." "DarkYellow"
                }
            }
        }
        if (-not $odUninstalled) { Write-Log "   [OneDrive][WARN] Ninguna ruta exitosa." "DarkYellow" }
        Remove-AppxSafe "*Microsoft.OneDrive*"
        @(
            "$env:USERPROFILE\OneDrive",
            "$env:LOCALAPPDATA\Microsoft\OneDrive",
            "$env:PROGRAMDATA\Microsoft OneDrive"
        ) | Where-Object { Test-Path $_ } | ForEach-Object {
            try { Remove-Item $_ -Recurse -Force -ErrorAction Stop; Write-Log "   Carpeta eliminada: $_" "DarkGray" }
            catch { Write-Log "   [WARN] No se pudo eliminar: $_ -- $($_.Exception.Message)" "DarkYellow" }
        }
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" 1
        Write-Log "   OneDrive: politica de bloqueo aplicada." "Green"
    }

    function Invoke-ModuleXbox {
        if ($script:UseGamingMode) { Write-Log "   [Xbox] GamingMode activo: conservando Xbox." "Yellow"; return }
        @(
            "*Microsoft.XboxApp*", "*Microsoft.XboxGameOverlay*", "*Microsoft.XboxGamingOverlay*",
            "*Microsoft.XboxIdentityProvider*", "*Microsoft.XboxSpeechToTextOverlay*",
            "*Microsoft.GamingApp*", "*Microsoft.Xbox.TCUI*"
        ) | ForEach-Object { Remove-AppxSafe $_ }
        foreach ($svc in @("XblAuthManager", "XblGameSave", "XboxGipSvc", "XboxNetApiSvc")) { Stop-ServiceSafe $svc }
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0
    }

    # FIX-B02: max VRAM entre todas las GPUs
    # FIX-C12: capturar exit code de powercfg y loguear WARN si falla
    # FIX-C19: evitar duplicar Ultimate Perf Plan si ya existe copia previa
    function Invoke-ModulePower {
        # FIX-C12: powercfg con verificacion de exit code
        & powercfg.exe /hibernate off 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log "   [WARN] powercfg /hibernate off fallo (ec=$LASTEXITCODE)." "DarkYellow" }
        else { Write-Log "   [Power] Hibernacion off." "DarkGray" }

        & powercfg.exe /change standby-timeout-ac 120 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log "   [WARN] powercfg standby-timeout-ac fallo (ec=$LASTEXITCODE)." "DarkYellow" }

        & powercfg.exe /change monitor-timeout-ac 15 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log "   [WARN] powercfg monitor-timeout-ac fallo (ec=$LASTEXITCODE)." "DarkYellow" }
        else { Write-Log "   [Power] Standby 120min. Monitor 15min." "DarkGray" }

        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        if ($null -ne $battery) {
            Write-Log "   [A1] Ultimate Perf Plan omitido: bateria detectada." "Yellow"
        }
        else {
            if ($script:IsDryRun) {
                Write-Log "   [DRY-RUN] Ultimate Perf Plan: check/create." "DarkGray"
            }
            else {
                $ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
                # FIX-C19: buscar si ya existe una copia del plan antes de duplicar
                $listOut = & powercfg.exe /list 2>&1 | Out-String
                $existingCopy = $null
                if ($listOut -match "Power Scheme GUID:\s+([a-f0-9\-]{36})\s+\(Ultimate Performance\)") {
                    $existingCopy = $Matches[1].Trim()
                }
                elseif ($listOut -match "([a-f0-9\-]{36}).*Ultimate") {
                    $existingCopy = $Matches[1].Trim()
                }
                if ($null -ne $existingCopy) {
                    & powercfg.exe /setactive $existingCopy 2>&1 | Out-Null
                    Write-Log "   [A1] Ultimate Perf Plan existente activado ($existingCopy)." "DarkGray"
                }
                else {
                    $dupOut = & powercfg.exe /duplicatescheme $ultimateGuid 2>&1 | Out-String
                    if ($LASTEXITCODE -ne 0) {
                        Write-Log "   [A1][WARN] powercfg /duplicatescheme fallo (ec=$LASTEXITCODE)." "DarkYellow"
                    }
                    elseif ($dupOut -match "([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})") {
                        & powercfg.exe /setactive $Matches[1] 2>&1 | Out-Null
                        Write-Log "   [A1] Ultimate Perf Plan creado y activado ($($Matches[1]))." "DarkGray"
                    }
                    else {
                        Write-Log "   [A1][WARN] Ultimate Perf Plan no disponible en este build." "DarkYellow"
                    }
                }
            }
        }

        if ($Mode -eq "Deep") {
            if ($script:IsDryRun) { Write-Log "   [DRY-RUN] PlatformAoAcOverride=0" "DarkGray" }
            else {
                $sleepStates = & powercfg.exe /a 2>&1 | Out-String
                if ($sleepStates -match "S3") {
                    Set-RegTracked -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" `
                        -Name "PlatformAoAcOverride" -Value 0 -Type DWord
                    Write-Log "   [A2] Modern Standby deshabilitado (S3 disponible)." "DarkGray"
                }
                else { Write-Log "   [A2] Modern Standby omitido: S3 no disponible." "Yellow" }
            }
        }

        $mmcssPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-RegTracked -Path $mmcssPath -Name "SystemResponsiveness"   -Value 0          -Type DWord
        Set-RegTracked -Path $mmcssPath -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord
        Write-Log "   [A4] MMCSS: SystemResponsiveness=0, NetworkThrottlingIndex=0xFFFFFFFF (sin throttling)." "DarkGray"  # FIX-BUG08: clarificado formato hex

        if ($script:UseGamingMode -and $WinBuild -ge 19041) {
            if ($script:IsDryRun) { Write-Log "   [DRY-RUN] HAGS: max VRAM entre todas las GPUs." "DarkGray" }
            else {
                # FIX-B02: max VRAM de todas las subkeys
                $gpuClassRoot = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
                $maxVramBytes = 0L
                foreach ($subKey in @(Get-ChildItem -LiteralPath $gpuClassRoot -ErrorAction SilentlyContinue |
                        Where-Object { $_.PSChildName -match "^\d{4}$" })) {
                    $props = Get-ItemProperty -LiteralPath $subKey.PSPath -ErrorAction SilentlyContinue
                    $vramVal = if ($null -ne $props) { $props."HardwareInformation.MemorySize" } else { $null }
                    if ($null -ne $vramVal) {
                        $vb = [long]$vramVal
                        if ($vb -gt $maxVramBytes) { $maxVramBytes = $vb }
                    }
                }
                $maxVramGB = [math]::Round($maxVramBytes / 1GB, 1)
                if ($maxVramBytes -ge 8GB) {
                    Set-RegTracked -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" `
                        -Name "HwSchMode" -Value 2 -Type DWord
                    Write-Log "   [A7] HAGS habilitado (max VRAM: ${maxVramGB}GB)." "DarkGray"
                }
                else {
                    Write-Log "   [A7] HAGS omitido: max VRAM ${maxVramGB}GB < 8GB." "Yellow"
                }
            }
        }

        if ($Mode -eq "Deep" -or $script:UseGamingMode) {
            Set-RegTracked -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" `
                -Name "Win32PrioritySeparation" -Value 38 -Type DWord
            Write-Log "   [A18] Win32PrioritySeparation=38." "DarkGray"
        }
    }

    function Invoke-ModuleUI {
        Set-RegistryValue "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" "(Default)" "" "String"
        Set-RegistryValue $REG_EXPLORER_ADV "TaskbarAl" 0
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0
        if (-not $script:IsDryRun) {
            try {
                Remove-ItemProperty -LiteralPath $REG_EXPLORER_ADV -Name "TaskbarDa" -ErrorAction SilentlyContinue
                New-ItemProperty -LiteralPath $REG_EXPLORER_ADV -Name "TaskbarDa" -Value 0 `
                    -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            }
            catch { Write-Log "   [WARN] TaskbarDa no modificable en Build $WinBuild." "DarkYellow" }
        }
        Set-RegistryValue $REG_COPILOT_USER    "TurnOffWindowsCopilot"    1
        Set-RegistryValue $REG_COPILOT_MACHINE "TurnOffWindowsCopilot"    1
        Set-RegistryValue $REG_EXPLORER_ADV    "TaskbarMn"                0
        Set-RegistryValue $REG_EXPLORER_ADV    "ShowCopilotButton"        0
        Set-RegistryValue $REG_EDGE_POLICIES   "HubsSidebarEnabled"           0
        Set-RegistryValue $REG_EDGE_POLICIES   "EdgeShoppingAssistantEnabled" 0
        Set-RegistryValue $REG_EDGE_POLICIES   "StartupBoostEnabled"          0
        $searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        Set-RegistryValue $searchPath "BingSearchEnabled"    0
        Set-RegistryValue $searchPath "SearchboxTaskbarMode" 1
        Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1
        foreach ($cdn in @(
                "SubscribedContent-338389Enabled", "SubscribedContent-310093Enabled",
                "SubscribedContent-338388Enabled", "SubscribedContent-353698Enabled",
                "SilentInstalledAppsEnabled", "SystemPaneSuggestionsEnabled", "SoftLandingEnabled"
            )) { Set-RegistryValue $REG_CDM $cdn 0 }
        $desktopPath = "HKCU:\Control Panel\Desktop"
        Set-RegTracked -Path $desktopPath -Name "WaitToKillAppTimeout" -Value "5000" -Type String
        Set-RegTracked -Path $desktopPath -Name "HungAppTimeout"       -Value "3000" -Type String
        Set-RegTracked -Path $desktopPath -Name "AutoEndTasks"         -Value "1"    -Type String
        Set-RegTracked -Path "HKLM:\SYSTEM\CurrentControlSet\Control" `
            -Name "WaitToKillServiceTimeout" -Value "5000" -Type String
        Write-Log "   [A8] Kill timeouts: App=5s, Hung=3s, Service=5s, AutoEndTasks=1." "DarkGray"
    }

    # FIX-C22: quitar SilentlyContinue de Disable-ScheduledTask dentro del try
    function Invoke-ModuleTelemetry {
        Set-RegistryValue $REG_DATACOLLECTION  "AllowTelemetry"        0
        Set-RegistryValue $REG_DATACOLLECTION2 "AllowTelemetry"        0
        Set-RegistryValue $REG_DATACOLLECTION2 "MaxTelemetryAllowed"   0
        Set-RegistryValue $REG_SYSTEM_POLICIES "EnableActivityFeed"    0
        Set-RegistryValue $REG_SYSTEM_POLICIES "PublishUserActivities" 0
        Set-RegistryValue $REG_SYSTEM_POLICIES "UploadUserActivities"  0
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0

        foreach ($svc in @("DiagTrack", "utcsvc", "dmwappushservice", "diagnosticshub.standardcollector.service")) {
            Stop-ServiceSafe $svc
        }

        if ($script:IsDryRun) {
            Write-Log "   [DRY-RUN] Disable tasks: $($TelemetryTasks.Count) tareas." "DarkGray"
            $ctx.DryRunActions.Add("[A11] Telemetry tasks batch")
        }
        else {
            foreach ($t in $TelemetryTasks) {
                # FIX-C22: sin SilentlyContinue; los errores reales llegan al catch
                try {
                    Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null
                    Write-Log "   [A11] Task off: $($t.Name)" "DarkGray"
                }
                catch { Write-Log "   [A11][WARN] $($t.Name): $($_.Exception.Message)" "DarkGray" }
            }

            foreach ($ceipPath in @(
                    "\Microsoft\Windows\Application Experience\",
                    "\Microsoft\Windows\Customer Experience Improvement Program\"
                )) {
                @(Get-ScheduledTask -TaskPath $ceipPath -ErrorAction SilentlyContinue |
                    Where-Object { $_.State -ne 'Disabled' }) |
                ForEach-Object {
                    $t = $_
                    $tName = if ($null -ne $t -and $t.PSObject.Properties['TaskName']) { $t.TaskName } else { '(unknown)' }
                    try {
                        Disable-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null
                        Write-Log "   [A11-Dyn] Task off: $tName" "DarkGray"
                    }
                    catch { Write-Log "   [A11-Dyn][WARN] $tName : $($_.Exception.Message)" "DarkYellow" }
                }
            }
        }

        if ($WinBuild -ge 26100) {
            Set-RegTracked -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1 -Type DWord
            Set-RegTracked -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1 -Type DWord
            Write-Log "   [A10] Windows Recall deshabilitado." "DarkGray"
        }

        if ($Mode -eq "Deep") {
            $nvGpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "NVIDIA" } | Select-Object -First 1
            if ($null -ne $nvGpu) {
                Stop-ServiceSafe "NvTelemetryContainer"
                Set-RegTracked -Path "HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client" `
                    -Name "OptInOrOutPreference" -Value 0 -Type DWord
                if (-not $script:IsDryRun) {
                    foreach ($nvTask in @("NvTmMon", "NvTmRep", "NvTmRepOnLogon")) {
                        try { Disable-ScheduledTask -TaskName $nvTask -ErrorAction Stop | Out-Null }
                        catch { Write-Log "   [A11-NV][WARN] $nvTask : $($_.Exception.Message)" "DarkGray" }
                    }
                }
            }
        }

        if ($Mode -in @("DevEdu", "Deep")) {
            $offPath = "HKCU:\SOFTWARE\Policies\Microsoft\Office\16.0\Common"
            Set-RegTracked -Path $offPath -Name "disabletelemetry" -Value 1 -Type DWord
            Set-RegTracked -Path $offPath -Name "sendtelemetry"    -Value 3 -Type DWord
            # FIX-C16: mensaje de log corregido (no "deshabilitada total", sino reducida)
            Write-Log "   [A13] Office telemetria reducida al minimo requerido (sendtelemetry=3, agente local off)." "DarkGray"
        }

    }

    function Invoke-ModuleSSD {
        Stop-ServiceSafe "SysMain"
        Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnablePrefetcher" 0
        Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnableSuperfetch" 0
        Set-RegistryValue $REG_LONGPATHS "NtfsDisable8dot3NameCreation" 1
        Set-RegistryValue $REG_LONGPATHS "LongPathsEnabled"             1
        if ($script:IsDryRun) { $ctx.DryRunActions.Add("[A14] fsutil disablelastaccess 1") }
        else {
            $laOut = & fsutil.exe behavior set disablelastaccess 1 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { Write-Log "   [WARN] fsutil disablelastaccess fallo (ec=$LASTEXITCODE)." "DarkYellow" }
            else { Write-Log "   [A14] disablelastaccess=1: $($laOut.Trim())" "DarkGray" }
        }
    }

    # FIX-C14: Privacy usa $IsEducationSku directamente para NoMicrosoftAccount
    #          independientemente del orden de ejecucion con OfflineOS
    function Invoke-ModulePrivacy {
        Set-PrivacyConsent -Value "Deny"
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1
        Set-RegistryValue $REG_POLICIES_SYSTEM "NoConnectedUser"       3
        Set-RegistryValue $REG_WORKPLACE_JOIN  "BlockAADWorkplaceJoin" 1
        Set-RegistryValue $REG_MSA             "DisableUserAuth"       1
        Set-RegistryValue $REG_OOBE            "DisablePrivacyExperience" 1
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0
        Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1
        Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1
        # FIX-C14: valor de NoMicrosoftAccount basado en SKU, no en flag de orden de ejecucion
        if ($IsEducationSku) {
            Set-RegistryValue $REG_SYSTEM_POLICIES "NoMicrosoftAccount" 3
            Write-Log "   [Privacy] NoMicrosoftAccount=3 (Education SKU, independiente de orden OfflineOS)." "DarkGray"
        }
        else {
            Set-RegistryValue $REG_SYSTEM_POLICIES "NoMicrosoftAccount" 1
            Write-Log "   [Privacy] NoMicrosoftAccount=1 (Pro/Enterprise)." "DarkGray"
        }
    }

    # FIX-B06: $IsEducationSku como condicion principal
    function Invoke-ModuleOfflineOS {
        if (-not $IsEducationSku) {
            Write-Log "   [OfflineOS] Omitido: solo para Education (SKU=$OSSku)." "Yellow"; return
        }
        Set-RegistryValue $REG_POLICIES_SYSTEM "NoConnectedUser"       3
        Set-RegistryValue $REG_WORKPLACE_JOIN  "BlockAADWorkplaceJoin" 1
        Set-RegistryValue $REG_SYSTEM_POLICIES "NoMicrosoftAccount"    3
        $ctx.OfflineOSApplied = $true
        Write-Log "   [OfflineOS] NoMicrosoftAccount=3 (Education)." "DarkGray"
        Set-RegistryValue $REG_MSA  "DisableUserAuth"          1
        Set-RegistryValue $REG_OOBE "DisablePrivacyExperience" 1
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0
    }

    function Invoke-ModuleCleanup {
        if ($script:IsDryRun) { Write-Log "  [DRY-RUN] Cleanup: CleanMgr + temp files." "DarkGray"; return }
        # FIX-BUG11: cleanmgr eliminado — bloqueaba indefinidamente (0 CPU/disco) en sistemas limpios
        foreach ($tp in @($env:TEMP, $env:TMP, "$env:SystemRoot\Temp")) {
            if (Test-Path $tp) {
                Get-ChildItem -Path $tp -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer } |
                ForEach-Object { try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch {} }
            }
        }
        Write-Log "   Archivos temporales eliminados." "DarkGray"
    }
    
    # FIX-C29: verificar estado post-Disable
    function Invoke-ModuleOptionalFeatures {
        if ($script:IsDryRun) { Write-Log "  [DRY-RUN] OptionalFeatures: DISM." "DarkGray"; return }
        foreach ($f in @("WorkFolders-Client", "Printing-XPSServices-Features", "WindowsMediaPlayer")) {
            $feat = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
            if ($null -ne $feat -and $feat.State -eq "Enabled") {
                # FIX-C29: verificar estado post-Disable
                Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction SilentlyContinue | Out-Null
                $featPost = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
                if ($null -ne $featPost -and $featPost.State -ne "Enabled") {
                    Write-Log "   Feature deshabilitada: $f (estado: $($featPost.State))" "DarkGray"
                }
                else {
                    $st = if ($null -ne $featPost) { $featPost.State } else { "N/A" }
                    Write-Log "   [WARN] $f puede no haberse deshabilitado (estado post: $st)." "DarkYellow"
                }
            }
        }
    }



    # FIX-C08: marcar flag ResetBaseApplied antes de ejecutar DISM
    function Invoke-ModuleDiskSpace {
        if (-not $ctx.AggressiveDisk) { Write-Log "   DiskSpace agresivo solo en Deep." "DarkYellow"; return }
        if ($script:IsDryRun) { Write-Log "  [DRY-RUN] DISM /StartComponentCleanup /ResetBase." "DarkGray"; return }
        Write-Host ""
        Write-Host "+============================================================+" -ForegroundColor Yellow
        Write-Host "|  [!]  DISM /ResetBase: operacion IRREVERSIBLE              |" -ForegroundColor Yellow
        Write-Host "|  Elimina capacidad de desinstalar updates anteriores.      |" -ForegroundColor Yellow
        Write-Host "|  Restore NO podra revertir este cambio.                    |" -ForegroundColor Yellow
        Write-Host "+============================================================+" -ForegroundColor Yellow
        if (Test-PendingReboot) { Write-Log "   [DiskSpace][WARN] Reboot pendiente. DISM puede fallar (ec=0x800F0A82). Reinicia primero." "DarkYellow" }  # FIX-BUG12
        & dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "   [WARN] DISM /ResetBase fallo (ec=$LASTEXITCODE)." "DarkYellow"
        }
        else {
            $ctx.ResetBaseApplied = $true
            Write-Log "   DISM /StartComponentCleanup /ResetBase completado." "Green"
        }
    }

    function Invoke-ModuleExplorerPerf {
        Set-RegistryValue $REG_EXPLORER_ADV "LaunchTo"              1
        Set-RegistryValue $REG_EXPLORER_ADV "HideFileExt"           0
        Set-RegistryValue $REG_EXPLORER_ADV "Hidden"                1
        Set-RegistryValue $REG_EXPLORER_ADV "ShowSuperHidden"       0
        Set-RegistryValue $REG_EXPLORER_ADV "NavPaneExpandToCurrentFolder" 1
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2
        $mask = [byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)
        if (-not $script:IsDryRun) {
            try {
                $regPath = "HKCU:\Control Panel\Desktop"
                if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
                Set-ItemProperty -LiteralPath $regPath -Name "UserPreferencesMask" `
                    -Value $mask -Type Binary -Force -ErrorAction Stop
                Write-Log "   UserPreferencesMask aplicado como [byte[]]." "DarkGray"
            }
            catch { Write-Log "   [WARN] UserPreferencesMask: $($_.Exception.Message)" "DarkYellow" }
        }
        else { Write-Log "   [DRY-RUN] UserPreferencesMask = [0x90,0x12,0x03,0x80,...]" "DarkGray" }
        Write-Log "   Explorer: Este equipo, extensiones visibles, efectos minimos." "DarkGray"
    }

    function Invoke-ModuleDevEnv {
        Set-RegistryValue $REG_LONGPATHS "LongPathsEnabled" 1
        Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "NtfsDisableLastAccessUpdate" 1
        if ($script:IsDryRun) { Write-Log "  [DRY-RUN] DevEnv: winget installs." "DarkGray"; return }
        foreach ($tool in @(
                "Git.Git", "Microsoft.VisualStudioCode", "Python.Python.3",
                "OpenJS.NodeJS.LTS", "Microsoft.WindowsTerminal"
            )) {
            # FIX-C30: [regex]::Escape para evitar que el punto sea comodin regex
            $installed = & winget list --id $tool --exact --accept-source-agreements 2>&1 | Out-String
            if ($installed -notmatch [regex]::Escape($tool)) {
                # FIX-C11: capturar LASTEXITCODE post-install
                & winget install --id $tool --exact --silent `
                    --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "   Instalado: $tool" "DarkGray"
                }
                else {
                    Write-Log "   [WARN] $tool : winget install fallo (ec=$LASTEXITCODE)." "DarkYellow"
                }
            }
            else { Write-Log "   Ya instalado: $tool" "DarkGray" }
        }
    }

    function Invoke-ModuleAdminTools {
        if ($script:IsDryRun) { Write-Log "  [DRY-RUN] AdminTools: winget installs." "DarkGray"; return }
        $hasNet = $false
        try {
            $tcp = [System.Net.Sockets.TcpClient]::new()
            $tcp.Connect("winget.azureedge.net", 443)
            $hasNet = $tcp.Connected
            $tcp.Close()
        }
        catch { }
        if (-not $hasNet) {
            Write-Log "   [AdminTools][WARN] Sin conectividad a winget.azureedge.net:443." "DarkYellow"; return
        }
        foreach ($tool in @(
                "Microsoft.Sysinternals.ProcessExplorer", "Microsoft.Sysinternals.Autoruns",
                "WiresharkFoundation.Wireshark", "7zip.7zip", "Notepad++.Notepad++",
                "voidtools.Everything", "Greenshot.Greenshot"
            )) {
            # FIX-C30: [regex]::Escape en -notmatch
            $installed = & winget list --id $tool --exact --accept-source-agreements 2>&1 | Out-String
            if ($installed -notmatch [regex]::Escape($tool)) {
                # FIX-C11: capturar LASTEXITCODE
                & winget install --id $tool --exact --silent `
                    --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "   Instalado: $tool" "DarkGray"
                }
                else {
                    Write-Log "   [WARN] $tool : winget install fallo (ec=$LASTEXITCODE)." "DarkYellow"
                }
            }
            else { Write-Log "   Ya instalado: $tool" "DarkGray" }
        }
        if ($script:UseInstallWindhawk) {
            & winget install --id RamenSoftware.Windhawk --exact --silent `
                --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Log "   Windhawk instalado." "DarkGray" }
            else { Write-Log "   [WARN] Windhawk: winget fallo (ec=$LASTEXITCODE)." "DarkYellow" }
        }
        Set-RegTracked -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" `
            -Name "RealTimeIsUniversal" -Value 1 -Type DWord
        Write-Log "   [A16] RealTimeIsUniversal=1." "DarkGray"
    }

    # FIX-C13: verificar DNS post-Set con Get-DnsClientServerAddress
    # FIX-C33: guard clause si no hay adaptadores fisicos activos
    function Invoke-ModuleDNS {
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false })

        # FIX-C33: guard clause explicita con warning
        if ($adapters.Count -eq 0) {
            Write-Log "   [DNS] Sin adaptadores fisicos activos. Modulo omitido (no-op)." "DarkYellow"
            return
        }

        foreach ($adapter in $adapters) {
            $ipv4 = @(Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty ServerAddresses)
            $ipv6 = @(Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv6 -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty ServerAddresses)
            $ctx.DNSBackup[$adapter.Name] = @{ IPv4 = $ipv4; IPv6 = $ipv6 }
        }
        if (-not $script:IsDryRun) {
            try {
                $ctx.DNSBackup | ConvertTo-Json -Depth 4 |
                Set-Content -LiteralPath $DNSBackupFile -Encoding UTF8 -ErrorAction Stop
                Write-Log "   [DNS] Backup persistido: $DNSBackupFile" "DarkGray"
            }
            catch {
                Write-Log "   [DNS][WARN] No se pudo persistir backup: $($_.Exception.Message)" "DarkYellow"
            }
        }
        if (-not $script:UseSetSecureDNS) {
            Write-Log "   [DNS] -SetSecureDNS no activo. Backup guardado, sin cambios aplicados." "DarkYellow"
            return
        }
        $targetDNS = @("1.1.1.1", "9.9.9.9")
        foreach ($adapter in $adapters) {
            Set-DnsClientServerAddress -InterfaceAlias $adapter.Name `
                -ServerAddresses $targetDNS -ErrorAction SilentlyContinue
            # FIX-C13: verificar que los DNS se escribieron correctamente
            $actual = @(Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 `
                    -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
            $verified = ($actual.Count -ge 1 -and $actual[0] -eq "1.1.1.1")
            if ($verified) {
                Write-Log "   [DNS] $($adapter.Name): $($actual -join ', ') [verificado]" "DarkGray"
            }
            else {
                Write-Log "   [DNS][WARN] $($adapter.Name): DNS aplicados pero verificacion no coincide (actual: $($actual -join ', '))." "DarkYellow"
            }
        }
    }

    #endregion -- MODULOS PRINCIPALES

    #region -- DISPATCHER -----------------------------------------------------

    Invoke-Step "DeKMS"            "Limpieza de activadores KMS irregulares" { Invoke-ModuleDeKMS }
    Invoke-Step "Activation"       "Activacion de Windows" { Invoke-ModuleActivation }
    Invoke-Step "Updates"          "Configurando Windows Update" { Invoke-ModuleUpdates }
    Invoke-Step "Defender"         "Ajustando Windows Defender" { Invoke-ModuleDefender }
    Invoke-Step "HyperV"           "Habilitando Hyper-V" { Invoke-ModuleHyperV }
    Invoke-Step "Bloatware"        "Eliminando bloatware preinstalado" { Invoke-ModuleBloatware }
    Invoke-Step "OneDrive"         "Desinstalando OneDrive" { Invoke-ModuleOneDrive }
    Invoke-Step "Xbox"             "Eliminando apps Xbox" { Invoke-ModuleXbox }
    Invoke-Step "Power"            "Optimizando energia y rendimiento" { Invoke-ModulePower }
    Invoke-Step "UI"               "Restaurando interfaz clasica" { Invoke-ModuleUI }
    Invoke-Step "Telemetry"        "Desactivando telemetria del sistema" { Invoke-ModuleTelemetry }
    Invoke-Step "SSD"              "Optimizando para SSD" { Invoke-ModuleSSD }
    Invoke-Step "OfflineOS"        "Aislando identidad cloud (Education)" { Invoke-ModuleOfflineOS }
    Invoke-Step "Privacy"          "Aplicando politicas de privacidad" { Invoke-ModulePrivacy }
    Invoke-Step "Cleanup"          "Limpiando archivos temporales" { Invoke-ModuleCleanup }
    Invoke-Step "OptionalFeatures" "Deshabilitando features opcionales" { Invoke-ModuleOptionalFeatures }
    Invoke-Step "DiskSpace"        "Limpieza agresiva de disco (Deep)" { Invoke-ModuleDiskSpace }
    Invoke-Step "ExplorerPerf"     "Optimizando Explorer" { Invoke-ModuleExplorerPerf }
    Invoke-Step "DevEnv"           "Instalando entorno de desarrollo" { Invoke-ModuleDevEnv }
    Invoke-Step "AdminTools"       "Instalando herramientas sysadmin" { Invoke-ModuleAdminTools }
    Invoke-Step "DNS"              "Configurando DNS seguros" { Invoke-ModuleDNS }

    if ($Mode -in @("Deep", "DevEdu") -or $script:UseGamingMode) {
        Invoke-Step "NICTuning"    "Optimizacion NIC (Nagle, FlowControl, EEE)" { Invoke-ModuleNICTuning }
        Invoke-Step "MSITuning"    "Message Signaled Interrupts GPU/NVMe" { Invoke-ModuleMSITuning }
    }
    Invoke-Step "InputTuning"      "Latencia de entrada (raton y teclado)" { Invoke-ModuleInputTuning }
    if ($Mode -eq "Deep" -and $DisableVBS.IsPresent) {
        Invoke-Step "VBSTuning"    "Deshabilitar VBS/HVCI (requiere reboot)" { Invoke-ModuleVBSTuning }
    }

    #endregion -- DISPATCHER

    #region -- RESUMEN FINAL --------------------------------------------------

    Write-Log "" "White"
    Write-Log "================================================================" "Green"
    Write-Log "Manolito v2.5.5 -- Ejecucion completada." "Green"
    Write-Log "  Pasos OK   : $($ctx.StepsOk)"   "Green"
    Write-Log "  Pasos FAIL : $($ctx.StepsFail)" $(if ($ctx.StepsFail -gt 0) { "Red" } else { "Green" })
    if ($ctx.FailedModules.Count -gt 0) {
        Write-Log "  Modulos con error: $($ctx.FailedModules -join ', ')" "Red"
    }
    if ($ctx.RebootRequired.Count -gt 0) {
        Write-Log "  [!] REINICIO REQUERIDO: $($ctx.RebootRequired -join ', ')" "Yellow"
    }
    if ($ctx.ResetBaseApplied) {
        Write-Log "  [!] DISM /ResetBase aplicado: cambio IRREVERSIBLE." "Yellow"
    }
    Write-Log "  Log:        $LogFile"        "DarkGray"
    Write-Log "  Transcript: $TranscriptPath" "DarkGray"
    if ($script:IsDryRun -and $ctx.DryRunActions.Count -gt 0) {
        Write-Log "  DryRun acciones simuladas: $($ctx.DryRunActions.Count)" "DarkGray"
    }
    Write-Log "================================================================" "Green"

    if ($Verify.IsPresent) { Invoke-Verify }

    #endregion

}
finally {
    if ($script:TranscriptStarted) {
        Stop-Transcript -ErrorAction SilentlyContinue
    }
    if ($acquired -and $null -ne $_mutex) {
        try { $_mutex.ReleaseMutex() } catch { }
        $_mutex.Dispose()
    }
}
