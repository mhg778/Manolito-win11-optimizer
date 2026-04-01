```text
______________________________________________________________________
|                                                                      |
|  ███╗   ███╗ █████╗ ███╗  ██╗ ██████╗ ██╗     ██╗████████╗ ██████╗   |
|  ████╗ ████║██╔══██╗████╗ ██║██╔═══██╗██║     ██║╚══██╔══╝██╔═══██╗  |
|  ██╔████╔██║███████║██╔██╗██║██║   ██║██║     ██║   ██║   ██║   ██║  |
|  ██║╚██╔╝██║██╔══██║██║╚████║██║   ██║██║     ██║   ██║   ██║   ██║  |
|  ██║ ╚═╝ ██║██║  ██║██║ ╚███║╚██████╔╝███████╗██║   ██║   ╚██████╔╝  |
|  ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚══╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝    ╚═════╝   |
|______________________________________________________________________|
 [ GUIA DE USUARIO FINAL ] - [ v2.8.1 THE ENGINE UPDATE ]
```

 //--[ 01. ¿QUE ES MANOLITO ENGINE? ]--------------------------------\

 Manolito es un optimizador de Windows 11 (Build 22000+) diseñado para 
 Administradores de Sistemas y Power Users. No es 
 un script convencional; es un motor asíncrono multihilo que orquesta 
 modificaciones profundas del sistema mediante una base de datos 
 declarativa en formato JSON.

 La misión: Recuperar el control. Sin telemetría. Sin bloatware. 
 Sin procesos basura.

 //--[ 02. REQUISITOS DE ACCESO ]-------------------------------------\

 [!] OS: Windows 11 (PRO/EDU/ENT Build 22000 o superior).
 [!] PRIVILEGIOS: Acceso de Administrador (elevación requerida).
 [!] ESTRUCTURA: Los archivos "manolito.ps1" y "manolito.json" deben 
     habitar el mismo directorio para que el motor arranque.

 //--[ 03. INSTRUCCIONES DE LANZAMIENTO ]----------------------------\

 1. Sitúate en la carpeta del motor.
 2. Ejecuta "manolito.ps1" con PowerShell.
 3. Si la seguridad de Redmond te bloquea, usa el bypass táctico:
    Set-ExecutionPolicy Bypass -Scope Process -Force; .\manolito.ps1

 //--[ 04. NIVELES OPERATIVOS (RUNLEVELS) ]--------------------------\

 El sistema clasifica las cargas útiles en 5 niveles de riesgo:

* 🟢 **[01] LITE**: Elimina Bloatware esencial y telemetría básica.
* 🔵 **[02] DEV-EDU**: Optimiza redes, elimina publicidad y limpia restos
			de activadores KMS.
* 🔴 **[03] DEEP OP**: Sintonía fina de latencia (Input Lag), activación
			MSI en GPU/NVMe y desactivación de VBS.
* 🟣 **[04] ROLLBACK**: Reversión granular a valores de fábrica.
* 🟠 **[05] NVME FIX**: Tuning crítico exclusivo para almacenamiento sólido
			(EnableNativeNVMe, ExtendNVMeHMB, DisableNVMeWriteCache). Solo 
			se activa con hardware NVMe físico detectado.

 //--[ 05. PANEL DE CONTROL Y TELEMETRIA DE INTERFAZ ]---------------\

 [!] AUDITORIA WMI: Al inicio, Manolito escanea tu hardware (Virtualización, 
     NVMe, GPU NVIDIA, Batería). El motor bloqueará automáticamente 
     payloads que puedan romper tu entorno específico.

 [!] CONSOLA CRT: Visualización en tiempo real del progreso. Gracias a 
     los Runspaces v2.8.0, la interfaz nunca se congela, permitiendo 
     una respuesta fluida incluso en tareas críticas.

 [!] DRY-RUN (Simulador): Activado por defecto. Te permite ver qué 
     haría el motor sin escribir un solo byte en el sistema.

 //--[ 06. HITOS DE RENDIMIENTO (THE MATRIX CHALLENGE) ]-------------\

 Con Manolito v2.8.0 hemos roto las leyes de Microsoft:
 -> Windows 11 estable con solo 2.0 GB de RAM totales.
 -> Consumo base en reposo reducido hasta los 1.5 GB.
 -> Actividad de CPU entre el 0% y el 7% en idle.

 //--[ 07. MANIFESTS: LA MAQUINA DEL TIEMPO ]------------------------\

 Cada ejecución real genera un "Manifest" en tu carpeta de Documentos. 
 Si algo falla:
 1. Pulsa el botón [ MANIFEST ].
 2. Selecciona la captura de estado de la sesión previa.
 3. Pulsa [ INICIAR ] y el motor reconstruirá tu sistema.

 //--[ 08. LICENCIA Y AVISO LEGAL ]----------------------------------\

 Manolito Engine es software libre bajo GNU GPLv3 para uso personal. 
 [!!!] USO CORPORATIVO/MSP: Requiere Licencia Comercial para eximirse 
 de las obligaciones de liberación de código de la GPLv3.

 TOCA COSAS SERIAS. ÚSALO BAJO TU PROPIA RESPONSABILIDAD.
──────────────────────────────────────────────────────────────────────
 [ EOF ] - Manolito v2.8.1 - Stay secure. Stay light.
