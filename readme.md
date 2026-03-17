#
```text

 ███╗   ███╗ █████╗ ██████╗  ██████╗ ██╗     ██╗████████╗ ██████╗ 
 ████╗ ████║██╔══██╗██╔══██╗██╔═══██╗██║     ██║╚══██╔══╝██╔═══██╗
 ██╔████╔██║███████║██║  ██║██║   ██║██║     ██║   ██║   ██║   ██║
 ██║╚██╔╝██║██╔══██║██║  ██║██║   ██║██║     ██║   ██║   ██║   ██║
 ██║ ╚═╝ ██║██║  ██║██║  ██║╚██████╔╝███████╗██║   ██║   ╚██████╔╝
 ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝    ╚═════╝ 
──────────────────────────────────────────────────────────────────────
              . . . Xciter . . . P R E S E N T S . . .

Target OS  : Windows 11 Pro, Enterprise & Education (22000 - 26100+)
Framework  : PowerShell 5.1 / 7.x (Multithreaded)
Payload    : Manolito v2.4 - The Offline Armor Update
Protection : MS Telemetry, Cloud Identity, KMS Hijackers, Bloatware
──────────────────────────────────────────────────────────────────────

//--[ I N F O ]------------------------------------------------------\\

La telemetría no se negocia. El bloatware no se tolera.

Manolito ha evolucionado. Dejo atrás los scripts de limpieza básicos para 
entregar un framework de aprovisionamiento diseñado bajo principios 
de Confianza Cero. Retomamos el control absoluto de las ediciones 
profesionales de Windows 11, extirpando la telemetría comercial y aislando
el sistema de la infraestructura en la nube de Microsoft o de los
backdoors de KMS toxicos que circulan y convierten tu pc en un bot esclavo.

Sin frameworks pesados de GUI. Sin dependencias. Sin fallos silenciosos.
Ingeniería de sistemas pura basada en PowerShell, control de concurrencia y 
auditoría estricta. Y por supuesto, sin pagar un duro...

//--[ C O R E   P A Y L O A D S ]------------------------------------\\

+ [!] Módulo OfflineOS: Blindaje total contra la identidad Cloud. Bloquea el
  Azure AD Join, fulmina los prompts de OOBE y fuerza la creación de cuentas
  locales mediante políticas restrictivas de sistema (NoMicrosoftAccount).
+ [!] DeKMS Hunter: Módulo forense de limpieza. Rastrea y destruye activadores
  KMS irregulares (KMSpico, HEU) ocultos en perfiles de servicio (S-1-5-20),
  limpiando el terreno para la inyección de licencias corporativas legítimas.
+ [!] Multithreaded Appx Purge: Erradicación del ecosistema comercial (TikTok,
  Spotify, Netflix). Utiliza Runspaces paralelos en PS7+ con protección 
  transaccional contra condiciones de carrera en el motor DISM.
+ [!] Secure DNS (Dual-Stack): Enrutamiento forzado de tráfico IPv4 e IPv6 
  hacia resolutores de confianza (Cloudflare/Quad9) en adaptadores físicos.
+ [!] Sysadmin Bootstrapper: Inyección automatizada vía Winget (7-Zip, PuTTY, 
  Notepad++, Sysinternals, Windhawk) evadiendo firewalls corporativos.
+ [!] Strict Architecture: Control de concurrencia (Mutex), gestión de estado 
  mediante try/finally y logs forenses consolidados en ejecución desatendida.

//--[ U S A G E   &   D E P L O Y M E N T ]--------------------------\\

Lanzamiento directo desde consola (requiere privilegios de Administrador).
Si tu entorno bloquea la ejecución, utiliza:
`powershell.exe -ExecutionPolicy Bypass -File .\manolito.ps1`

* [ Modo Interactivo (GUI de consola retro + Toggles) ]
  .\manolito.ps1 -Interactive

* [ Despliegue Silencioso (Ideal para Intune / SCCM) ]
  .\manolito.ps1 -Mode DevEdu -Skip AdminTools

* [ Modo Destructor (Limpieza DISM /ResetBase, Irreversible) ]
  .\manolito.ps1 -Mode Deep -SetSecureDNS -InstallWindhawk

* [ QA / Auditoría (Simulación sin escritura en disco/registro) ]
  .\manolito.ps1 -Mode DevEdu -DryRun

//--[ L E G A L   &   L I C E N S E   ( D U A L ) ]------------------\\

Manolito es software libre de código abierto. Se distribuye bajo los 
términos de la licencia [GNU GPLv3](LICENSE).

Esto significa que eres completamente libre de usarlo, estudiarlo, 
compartirlo y modificarlo para uso personal, doméstico o en instituciones 
educativas públicas.

[!!!] AVISO PARA EMPRESAS Y PROVEEDORES IT (MSP) [!!!]
La licencia GPLv3 es estricta (Copyleft). El uso de este software en 
entornos corporativos, empresariales, o por parte de técnicos informáticos 
para dar soporte lucrativo a terceros, OBLIGA LEGALMENTE a liberar el 
código fuente de cualquier ecosistema derivado en el que se integre.

Si deseas utilizar Manolito de forma comercial en tu empresa SIN estar 
sujeto a las obligaciones de la GPLv3 sobre tu propia propiedad intelectual, 
debes adquirir una Licencia Comercial.

Contacta con el autor a través de GitHub para consultar los planes de 
Licenciamiento Comercial e integraciones Enterprise.
──────────────────────────────────────────────────────────────────────
[ EOF ] - Stay secure. Stay offline.
