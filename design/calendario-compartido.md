# Calendario compartido entre hogares — propuesta v0.4

Documento de diseño. No activa servicios externos ni modifica la base de datos del piloto.

## Objetivo
Permitir a dos hogares coordinar la convivencia de sus hijos sin compartir listas de compra, gastos, productos, notas privadas ni otros datos domésticos. Módulo opcional; el resto de hogares mantiene su experiencia habitual.

## Experiencia
- Vista mensual por participante, navegación por meses y recuento mensual y anual.
- Cuatro categorías exclusivas: convivencia ordinaria con cada progenitor y vacaciones con cada progenitor. También pendiente y fuera/viaje.
- Los totales de cada progenitor incluyen vacaciones en una segunda cifra; no se cuentan dos veces los días.
- Permitir rutinas semanales, fines de semana alternos, o exactamente dos fines de semana por mes (son reglas distintas).
- Seleccionar fechas inicial y final para vacaciones o intercambios. Las excepciones acordadas prevalecen sobre las rutinas; no modificar el calendario legal de referencia sin acuerdo.
- Mostrar claramente calendario previsto y cambios confirmados; un día asignado no demuestra estancia efectiva.
- Definir a qué progenitor corresponde cada categoría por hogar, sin asumir automáticamente género o rol legal.
- La unidad de recuento inicial es el día de pernocta, con posibilidad de configurar otro criterio y explicarlo en pantalla.

## Permisos y flujo
1. Un administrador invita al otro progenitor exclusivamente al módulo de convivencia, con consentimiento.
2. El destinatario acepta la invitación autenticada, limitada al calendario y participantes autorizados.
3. Los dos pueden consultar el calendario y proponer modificaciones. El otro confirma o rechaza; el estado pendiente no altera la planificación acordada.
4. Los participantes consultan solo su propio calendario y pueden comunicar cambios; no reciben acceso a las compras, gastos ni información de otros hogares.
5. Un colaborador de limpieza no tiene acceso al calendario.
6. Revocar el vínculo cancela el acceso futuro. Registrar quién propuso, aceptó o rechazó cada cambio, con fecha y hora. Definir política de conservación y eliminación de datos.

## Modelo previsto
Entidades independientes de la información de compra: calendario compartido, miembros autorizados, participantes, rutinas, excepciones confirmadas, propuestas de cambio y registro de eventos. Usar identificadores opacos. Validar permisos y transición de estado en servidor, nunca confiar en el rol indicado por el navegador. El calendario no debe aceptar escrituras de un hogar ajeno. Los cambios confirmados deben aplicarse atómicamente y controlar la revisión para evitar sobrescribir cambios concurrentes.

## Integraciones
Un cambio de convivencia puede sugerir una actualización de comensales y de necesidades de compra en cada hogar; no confirma automáticamente asistencia ni crea pedidos. Cada hogar controla sus propias sugerencias. WhatsApp e IA permanecen desactivados hasta aprobación expresa.

## Pruebas de aceptación antes del piloto real
- Acceso de administrador, participante, colaborador y cuenta sin vínculo.
- Dos hogares aislados, con vínculo limitado al calendario: intentar leer y modificar compras, gastos y datos ajenos debe fallar.
- Invitación caducada, reutilizada o revocada; propuestas aceptadas/rechazadas y escrituras simultáneas.
- Mes de cinco fines de semana, febrero bisiesto, vacaciones que cruzan mes/año y restauración de rutinas.
- Cada fecha pertenece a una única categoría; sumas mensuales y anuales correctas, pendientes incluidos.
- Vista de participante sin datos de hermanos o información doméstica privada.
- Confirmar cambios desde dos dispositivos con cuentas ficticias y verificar persistencia tras volver a entrar.
- No introducir datos reales ni activar servicios de pago hasta revisar y superar estas pruebas.

## Próximo paso técnico
Revisar y probar la implementación mensual existente en la demo y en el piloto autenticado. Diseñar la migración del calendario compartido de forma compatible con el esquema privado ya instalado. No ejecutar migraciones destructivas ni instalar un segundo esquema alternativo sin reconciliarlo con el actual.
