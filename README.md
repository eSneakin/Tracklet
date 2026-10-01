# Tracklet

Aplicación nativa de macOS y widgets de escritorio para controlar Spotify.

## Versión 1.0

- Autenticación OAuth con PKCE y credenciales en Keychain.
- Canción, portada, progreso y dispositivo; Previous, Play/Pause, Next y repetición en el widget grande.
- Widgets pequeño, mediano y grande; preferencias de apariencia y artwork.
- Última reproducción conservada por cuenta, sin simular reproducción activa. Disconnect elimina ese estado.
- Iconos claro/oscuro, ventana redimensionable y feedback de interacción.

## Descarga e instalación

Consulta las [releases](https://github.com/eSneakin/Tracklet/releases). El repositorio es privado: sus descargas requieren acceso al repositorio; los borradores no son publicaciones finales.

La compilación inicial es **de desarrollo, firmada con Apple Development y sin notarizar**. No está validada para distribución general: Gatekeeper puede rechazarla y su funcionamiento en otros Macs no está garantizado. Una distribución final requiere Developer ID y notarización. [Documentación de Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Para las copias de prueba autorizadas:

1. Descomprime el ZIP y copia `Tracklet.app` a Aplicaciones, cerrando antes la copia anterior.
2. Abre Tracklet y conecta Spotify.
3. Reproduce una canción para guardar el primer estado.
4. Añade Tracklet desde la galería de widgets de macOS y elige tamaño.

Paquete universal `arm64` + `x86_64`. La app declara macOS 13 como mínimo; los widgets requieren macOS 14. Validación local realizada en Apple Silicon, macOS 27; Intel y versiones anteriores necesitan pruebas reales.

Los controles requieren Spotify Premium y un reproductor disponible. Si la aplicación de Spotify Developer está en development mode, cada usuario debe estar autorizado en su Dashboard. [Permisos de usuarios de Spotify](https://developer.spotify.com/documentation/web-api/concepts/quota-modes).

## Compilar

Usa Xcode 27, empleado para validar esta versión y compilar el icono de Icon Composer. Configura tu equipo y firma en `Configuration/Tracklet.xcconfig`. App y widget deben compartir equipo y App Group.

```sh
xcodebuild -project Tracklet.xcodeproj -scheme Tracklet \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .build/release ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' build

swift test
ruby Scripts/check-app-icon.rb .build/release/Build/Products/Release/Tracklet.app
```

Resultado: `.build/release/Build/Products/Release/Tracklet.app`, con extensión e iconos incluidos. `swift run` no sustituye al bundle para instalar widgets.

El proyecto Xcode está incluido. `Scripts/generate-xcode-project.rb` solo se utiliza para regenerarlo intencionalmente; requiere la gema `xcodeproj` y reemplaza el proyecto.

## Configuración y datos

- Versión y firma: `Configuration/Tracklet.xcconfig`.
- Client ID público, redirect y scopes: `Sources/Tracklet/Configuration/SpotifyConfiguration.swift`. Admite overrides `SpotifyClientID` / `SpotifyRedirectURI` en Info.plist o `SPOTIFY_CLIENT_ID` / `SPOTIFY_REDIRECT_URI` en el entorno de desarrollo. Registrar `tracklet://callback` en Spotify Dashboard.
- Tokens: Keychain, nunca en el ZIP ni en el snapshot del widget. No se utiliza client secret.
- Preferencias: UserDefaults; snapshot y miniaturas: contenedor App Group.
- La app actualiza Spotify cada 30 segundos y tras acciones. El progreso se calcula localmente; WidgetKit controla cuándo presenta actualizaciones.

## Limitaciones conocidas

- Play intenta reanudar la sesión real. Si Spotify confirma un dispositivo activo sin canción, puede restaurar una canción guardada con URI válido; no reconstruye una cola perdida ni transfiere dispositivos.
- Sin dispositivo activo, conserva la información y solicita abrir Spotify.
- Restaurar la sesión al arrancar depende de obtener el perfil de Spotify; el arranque sin red todavía necesita endurecimiento. No se promete funcionamiento offline completo.
- Antes de distribuir: firma/notarización, pruebas en otros Macs y revisión de acceso/permisos de la aplicación Spotify.
