# Tracklet 1.0 — compilación de desarrollo

## Cambios

- Reproductor nativo macOS con perfil real y OAuth PKCE.
- Now Playing, portada, progreso local y dispositivo activo.
- Previous, Play/Pause y Next; Anterior reinicia desde tres segundos y retrocede antes de ese punto.
- Widgets pequeño, mediano y grande; controles y repetición en el grande.
- Última reproducción persistida por cuenta, congelada cuando Spotify no reporta playback, y eliminada al desconectar.
- Preferencias visuales, iconos claro/oscuro y versión 1.0 visible.

## Descarga

`Tracklet-1.0-macOS-universal-development.zip` contiene la app Release universal (Apple Silicon + Intel), el widget integrado y estas notas. Verifica el archivo con `SHA256SUMS.txt`.

**Firma Apple Development; sin notarizar.** No es todavía una distribución final para otros Macs. Gatekeeper puede rechazarla. Falta firma Developer ID y notarización antes de publicación general. [Requisitos de Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

La verificación local de Gatekeeper (`spctl`) devuelve `rejected`; la verificación de integridad de la firma (`codesign`) sí pasa. Este paquete se conserva como artefacto de desarrollo, no como instalador aprobado por Apple.

Extrae el ZIP, cierra la copia anterior y copia `Tracklet.app` a Aplicaciones. Abre Tracklet, conecta Spotify y reproduce una canción una vez. Después añade widgets desde la galería de macOS.

## Requisitos y verificación

- App: macOS 13 declarado; widgets: macOS 14. Probado localmente en Apple Silicon con macOS 27; Intel y sistemas anteriores pendientes de prueba física.
- Spotify Premium y dispositivo disponible para controles. En development mode, los usuarios necesitan acceso en Spotify Developer Dashboard. [Documentación de Spotify](https://developer.spotify.com/documentation/web-api/concepts/quota-modes).
- 24 tests automatizados con Spotify simulado, build universal y firma estructural verificados.
- La caché no conserva la cola de Spotify; no activa dispositivos apagados. Arranque offline completo todavía no garantizado.
- No incluye tokens, sesiones, preferencias personales ni caché de reproducción del desarrollador.
