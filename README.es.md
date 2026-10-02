<img src="Resources/images/Tracklet%20Logo%20Light.png" width="88" alt="Icono de Tracklet">

# Tracklet

[English](README.md) · [Español](README.es.md)

**Tu música, siempre a mano.** Una pequeña aplicación nativa de macOS para acompañar Spotify, con widgets de escritorio en tres tamaños.

Conecta Spotify, elige tu estilo y mantén tu música cerca sin abrir un reproductor completo.

## Qué puedes hacer

- Ver canción, artista, álbum, portada, progreso y dispositivo de reproducción.
- Pausar, reanudar, avanzar y retroceder desde la app; usar controles y repetición en el widget grande.
- Elegir widgets pequeños, medianos o grandes, estilos de apariencia y portadas a color, desenfocadas o monocromáticas.
- Conservar la última canción cuando Spotify deja de reportar reproducción, identificada como **Last played**.
- Usar una ventana compacta y redimensionable, con acentos azules e iconos claro/oscuro.

Construido con Swift, SwiftUI, WidgetKit y APIs nativas de Apple. Sin frameworks externos en la aplicación.

## Antes de empezar

| Requisito | Detalles |
| --- | --- |
| macOS | La app declara macOS 13 como mínimo; los widgets de escritorio requieren macOS 14. |
| Mac | La descarga incluye binarios Apple Silicon e Intel. Probado localmente en Apple Silicon con macOS 27; faltan pruebas en otros sistemas. |
| Spotify | Los controles requieren Premium y un dispositivo disponible. Tracklet no reproduce audio por sí mismo. |
| Acceso de desarrollador | Si la aplicación Spotify está en development mode, tu cuenta debe estar en su lista de usuarios autorizados. Consulta las [reglas de Spotify](https://developer.spotify.com/documentation/web-api/concepts/quota-modes). |

## Descarga y primeros pasos

Visita [Releases](https://github.com/eSneakin/Tracklet/releases) para ver compilaciones disponibles y las [notas de versión](RELEASE_NOTES.md) para conocer los cambios.

> **Compilación de desarrollo:** la versión 1.0 está firmada con Apple Development, no con Developer ID, y no está notarizada. Pasa la verificación de integridad, pero Gatekeeper la rechaza en la comprobación local. Todavía no es un instalador de distribución general. Si macOS la bloquea, compila una copia firmada con tu propio equipo o espera una versión notarizada; no desactives Gatekeeper.

Para una instalación de desarrollo autorizada:

1. Descomprime la descarga. Cierra cualquier copia anterior y mueve `Tracklet.app` a **Aplicaciones**.
2. Abre Tracklet y pulsa **Connect** para autorizar Spotify.
3. Reproduce una canción en Spotify. Tracklet la detectará y guardará su primer estado.
4. Abre la galería de widgets de macOS, busca **Tracklet** y elige un tamaño.
5. Ajusta la portada en **Widget** y el estilo en **Appearance**.

Mantén Tracklet en ejecución para sincronizar periódicamente. Cerrar una ventana no es lo mismo que salir de la app: salir detiene sus consultas. Los controles del widget pueden pedir a macOS que inicie la app para ejecutar una acción.

El repositorio sigue privado y la primera release está en borrador, por lo que el acceso es limitado. Prepararlo como código abierto no convierte automáticamente sus descargas en públicas.

## Cómo se comporta la reproducción

- **Playing:** el progreso avanza localmente; la app consulta Spotify aproximadamente cada 30 segundos y después de las acciones.
- **Paused:** conserva portada y datos; el progreso se detiene.
- **Last played:** Spotify no devuelve reproducción y Tracklet conserva la última canción y posición confirmadas, sin fingir que sigue sonando.
- **Play:** primero comprueba la sesión actual. Si Spotify confirma un dispositivo activo sin canción, puede recuperar una canción guardada con URI válido. No reconstruye una cola perdida ni activa un dispositivo no disponible.
- **Anterior:** desde tres segundos reinicia el contenido actual; antes de ese punto pide el contenido anterior.
- **Disconnect:** elimina las credenciales y borra el estado de reproducción de esa cuenta.

WidgetKit decide cuándo actualizar los widgets. Una barra animada es un temporizador local, no una petición a Spotify cada segundo.

## Compilar tu propia copia

### 1. Descarga el código

```sh
git clone https://github.com/eSneakin/Tracklet.git
cd Tracklet
open Tracklet.xcodeproj
```

Esta versión se validó con Xcode 27, también utilizado para compilar el icono de Icon Composer. Configura tu equipo y firma en [Configuration/Tracklet.xcconfig](Configuration/Tracklet.xcconfig). App y extensión deben compartir equipo y un App Group compatible.

### 2. Configura Spotify

Crea tu aplicación en el [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) y registra `tracklet://callback` como Redirect URI.

La configuración está en [SpotifyConfiguration.swift](Sources/Tracklet/Configuration/SpotifyConfiguration.swift). Para tu compilación, define `SpotifyClientID` y `SpotifyRedirectURI` en [Tracklet-Info.plist](Configuration/Tracklet-Info.plist), o usa `SPOTIFY_CLIENT_ID` y `SPOTIFY_REDIRECT_URI` en el entorno de ejecución de desarrollo. El Client ID incluido es público, pero no concede acceso a tu cuenta. Nunca añadas un client secret.

### 3. Compila y verifica

```sh
xcodebuild -project Tracklet.xcodeproj -scheme Tracklet \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .build/release ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' build

swift test
ruby Scripts/check-app-icon.rb .build/release/Build/Products/Release/Tracklet.app
```

La app queda en `.build/release/Build/Products/Release/Tracklet.app`, con extensión e iconos incluidos. Instala ese bundle: `swift run` por sí solo no instala el widget.

El proyecto Xcode está incluido. Regenerarlo es opcional: `Scripts/generate-xcode-project.rb` requiere la gema Ruby `xcodeproj` y reemplaza el proyecto al ejecutarse.

## Dónde está cada cosa

| Ruta | Responsabilidad |
| --- | --- |
| `Sources/Tracklet/Features` | Pantallas y estado observable de reproducción/configuración |
| `Sources/Tracklet/Services/Spotify` | Autenticación, peticiones API y acciones de reproducción |
| `Sources/Tracklet/Models` | Modelos tipados de cuenta y reproducción |
| `Sources/Tracklet/Storage` | Credenciales y preferencias de la app |
| `Sources/Tracklet/Shared` | Almacenamiento de snapshots e intents compartidos con el widget |
| `TrackletWidgetExtension` | Diseños del widget y proveedor de timelines |
| `Configuration`, `Resources`, `Tests` | Firma/versión, iconos y verificaciones automatizadas |

## Problemas comunes

| Qué ocurre | Qué probar |
| --- | --- |
| “Open Spotify to continue” | Abre Spotify y empieza a reproducir en el dispositivo que quieras controlar. |
| Error de permisos / 403 | Revisa Premium, usuarios autorizados y permisos. Si cambiaron los scopes, usa Disconnect y Connect otra vez. |
| Widget desactualizado | Abre Tracklet, revisa conexión y espera a WidgetKit. Tras una actualización, puede ayudar quitar y volver a añadir el widget. |
| Aparece una versión anterior | Sal de Tracklet y abre la copia de Aplicaciones. Evita ejecutar otra copia de desarrollo a la vez. |
| Falla el inicio sin internet | Recupera la conexión y vuelve a conectar la cuenta si hace falta. La restauración completamente offline sigue pendiente. |

## Privacidad y seguridad

Los tokens permanecen en Keychain. Las preferencias usan UserDefaults; los estados de reproducción y miniaturas usan un contenedor App Group. Los snapshots del widget no contienen access tokens ni refresh tokens. Las acciones pasan por el servicio Spotify de la app principal.

Las descargas no incluyen la sesión ni la caché de reproducción del desarrollador. Tracklet contacta Spotify para autenticación, perfil, reproducción e imágenes. Es un proyecto independiente, no una aplicación oficial de Spotify.

## Ayúdanos a mejorar Tracklet

Ideas, errores, mejoras de documentación y comentarios de accesibilidad son bienvenidos en [Issues](https://github.com/eSneakin/Tracklet/issues).

Incluye versión de macOS, arquitectura del Mac, versión de Tracklet, pasos para reproducir el error y resultado esperado/real. Oculta datos personales en capturas. Nunca publiques tokens, códigos de autorización, exportaciones de Keychain ni claves privadas de firma.

Para contribuir código, conversa primero sobre cambios grandes, mantén las PR enfocadas, reutiliza los servicios existentes y ejecuta las verificaciones anteriores. Actualiza ambas guías cuando cambie el comportamiento. Revisa el estado de la licencia antes de aportar código.

## Licencia y publicación

El código y la documentación originales de Tracklet se ofrecen bajo la [licencia MIT](LICENSE), copyright 2026 Enmanuel Lopez (eSneakin). Puedes usarlos, modificarlos y redistribuirlos, incluso comercialmente, conservando los avisos de autoría y licencia. El software se ofrece sin garantías, conforme al texto de la licencia.

Esta concesión no cambia las licencias de referencias, contenido ni marcas de terceros; consulta los [avisos de terceros](THIRD_PARTY_NOTICES.md).

Antes de una publicación general: revisar material de referencia y marcas de terceros, decidir la visibilidad del repositorio, configurar firma Developer ID y [notarizar la app](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
