# Manolito v2.8.0

```text
 ███╗   ███╗ █████╗ ███╗  ██╗ ██████╗ ██╗     ██╗████████╗ ██████╗ 
 ████╗ ████║██╔══██╗████╗ ██║██╔═══██╗██║     ██║╚══██╔══╝██╔═══██╗
 ██╔████╔██║███████║██╔██╗██║██║   ██║██║     ██║   ██║   ██║   ██║
 ██║╚██╔╝██║██╔══██║██║╚████║██║   ██║██║     ██║   ██║   ██║   ██║
 ██║ ╚═╝ ██║██║  ██║██║ ╚███║╚██████╔╝███████╗██║   ██║   ╚██████╔╝
 ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚══╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝    ╚═════╝ 
──────────────────────────────────────────────────────────────────────
     . . . Xciter . . . P R E S E N T S . . .  [ MANOLITO v2.8.0 ]

Target OS  : Windows 11 (Build 22000 - 26200+)
Framework  : PowerShell 5.1 (WPF Asynchronous + Runspaces)
Payload    : The Engine Update (Data-Driven Architecture)
Protection : MS Telemetry, Cloud Identity, KMS Hunter, Bloatware
──────────────────────────────────────────────────────────────────────

![Manolito UI Hero](assets/manolito-ui.png)

//--[ I N F O ]------------------------------------------------------\

Manolito ha evolucionado de un script de limpieza a un Framework de 
Aprovisionamiento Declarativo diseñado bajo principios de Zero Trust. 
Redmond y yo no somos amigos.
La telemetría no la tolero y el bloatware no lo consiento. 

Esta versión 2.8.0 introduce un motor asíncrono multihilo que separa 
la interfaz gráfica de la ejecución pesada, garantizando fluidez total 
mientras se extirpan componentes tóxicos del sistema.

//--[ M I L E S T O N E : W I N 1 1   L I G H T S P E E D ]----------\

Hemos pulverizado los requisitos mínimos oficiales de Microsoft (4GB RAM). 
Manolito Engine permite ejecutar Windows 11 de forma estable y ágil 
con recursos drásticamente reducidos:

* **RAM Challenge**: Operatividad total en máquinas con solo **2.0 GB de RAM**.
* **Consumo Base**: Reducción del uso de memoria hasta los **1.1 GB**.
* **CPU Idle**: Uso de procesador estabilizado entre el **0% y el 7%**.
* **Matrix Bug**: La purga es tan profunda que el sistema reporta **0.0 PB** de reserva para hardware.

![Windows 11 2GB Milestone](assets/win11_2gb.jpg)

//--[ C O R E   A R C H I T E C T U R E ]----------------------------\

    [!] Zero-Lag WPF UI: Interfaz asíncrona construida sobre Runspaces 
	nativos. Las tareas corren en hilos secundarios para 
	evitar bloqueos visuales.

    [!] Auditoría WMI en Tiempo Real: El motor detecta hardware 
	específico (NVMe, GPUs NVIDIA, Batería, VMs) y bloquea 
	automáticamente payloads incompatibles.

    [!] Manifest Time-Machine: Captura una fotografía técnica del 
	equipo antes de alterarlo, permitiendo un Rollback milimétrico.

//--[ R U N L E V E L S ]--------------------------------------------\

* 🟢 **[01] LITE**: Elimina Bloatware esencial y telemetría básica.
* 🔵 **[02] DEV-EDU**: Optimiza redes, elimina publicidad y limpia restos de activadores KMS.
* 🔴 **[03] DEEP OP**: Sintonía fina de latencia (Input Lag), activación MSI en GPU/NVMe y desactivación de VBS.
* 🟣 **[04] ROLLBACK**: Reversión granular a valores de fábrica.

//--[ U S A G E ]----------------------------------------------------\

Requiere `manolito.ps1` y `manolito.json` en el mismo directorio.
Se requieren privilegios de Administrador.

Lanzamiento con bypass de política:
`powershell.exe -ExecutionPolicy Bypass -File .\manolito.ps1`

O siemplemente haz click en el .bat...

![Execution Animation](assets/Animation.gif)

//--[ U S A G E & D O C U M E N T A T I O N ]--------------------\

El motor requiere la presencia de manolito.ps1 y manolito.json en el mismo directorio.
Se requieren privilegios de Administrador.

Para evadir las políticas de restricción de ejecución en tu entorno:
powershell.exe -ExecutionPolicy Bypass -File .\manolito.ps1

📖 Consulta el Manual Técnico de Operación y Arquitectura. Detalles sobre cómo añadir tus
propios Payloads al JSON, explicación de los Runlevels y guía de Restauración mediante Manifests.

//--[ S U P P O R T & D O N A T I O N S ]------------------------\

Manolito es un proyecto desarrollado de forma independiente con cientos de horas de ingeniería inversa,
pruebas en laboratorio y depuración.
Si este motor te ha ayudado a rascar esos FPS extra en tu setup, ha salvado tu viejo portátil o te ha ahorrado horas de
configuración tras un formateo, considera invitar al autor a un café (o a una bebida energética para las noches en vela):

[☕] Ko-fi : https://ko-fi.com/mhg778 [💸] PayPal : https://paypal.me/mhg778

Cualquier aporte ayuda a mantener el proyecto vivo, pagar los servidores de pruebas y seguir investigando
las entrañas de Windows. ¡Gracias! 

//--[ L E G A L   &   L I C E N S E ]--------------------------------\

Manolito Engine es software libre bajo licencia **GNU GPLv3** para uso personal y educativo. 

**AVISO PARA EMPRESAS Y MSP:** El uso en entornos corporativos o para soporte lucrativo requiere una **Licencia Comercial**
para eximirse de las obligaciones Copyleft de la GPLv3. Contactar con el autor para integraciones Enterprise.

──────────────────────────────────────────────────────────────────────
[ EOF ] - Stay secure. Stay light. Stay offline.
