# Directrices de Contribución para Manolito

El desarrollo de Manolito se rige por principios estrictos de ingeniería de sistemas y arquitectura de Zero Trust. Si deseas proponer una mejora o enviar un Pull Request (PR), debes cumplir con los siguientes estándares técnicos.

## Filosofía del Proyecto
1. **Cero Dependencias:** No se aceptarán PRs que requieran la descarga de módulos externos de la galería de PowerShell, ejecutables de terceros compilados o frameworks de interfaz gráfica (WPF/WinForms).
2. **Idempotencia:** Cualquier cambio en el sistema debe evaluar el estado actual antes de aplicar la modificación.
3. **Control de Errores:** El script opera bajo `Set-StrictMode -Version Latest`. Todo código nuevo debe ser compatible con esta directiva. Las operaciones de entrada/salida (I/O) o registro deben estar encapsuladas en bloques `try/catch`.

## Proceso para Pull Requests (PR)
1. Haz un *fork* del repositorio y crea una rama para tu feature/fix (`git checkout -b feature/nombre-mejora`).
2. Implementa tu código siguiendo la estructura modular de `Invoke-Step`.
3. Valida tu código ejecutando el script en modo de simulación (`.\manolito.ps1 -DryRun`) para garantizar que la salida de auditoría es correcta.
4. Envía el PR explicando detalladamente el vector de ataque del bloatware/telemetría que estás mitigando y en qué *builds* de Windows 11 lo has testeado.

## Aviso Legal (Dual License)
Al enviar un Pull Request a este repositorio, aceptas que tus contribuciones se integren bajo la licencia **GNU GPLv3** del proyecto y cedes los derechos necesarios para su inclusión en la arquitectura de Licenciamiento Dual detallada en el `README.md`.
