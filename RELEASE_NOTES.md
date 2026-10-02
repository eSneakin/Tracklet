# Tracklet 1.0 — Development build / Compilación de desarrollo

## English

Your Spotify playback, close at hand: a native macOS app and widgets in small, medium, and large sizes.

### Highlights

- Spotify OAuth with PKCE and credentials in Keychain.
- Artwork, track details, local progress, and playback device.
- Previous, Play/Pause, Next, and repeat in the large widget.
- Previous restarts at three seconds or more; before that, it requests the previous item.
- Last playback preserved per account, frozen when unavailable, and cleared on Disconnect.
- Appearance/artwork preferences, light/dark icons, and visible version 1.0.

### Download and install

`Tracklet-1.0-macOS-universal-development.zip` includes the Release app, embedded widget, and these notes. Verify it with `SHA256SUMS.txt`.

**Development artifact, not a final installer.** Signed with Apple Development; not notarized. Signature integrity passes, but the local Gatekeeper assessment returns `rejected`. General distribution still needs Developer ID signing and notarization. [Apple's requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

For authorized testing: extract the ZIP, quit any old copy, and move `Tracklet.app` to Applications. Connect Spotify, play a song once, and add Tracklet from the macOS widget gallery. If macOS blocks the build, do not disable Gatekeeper; use a locally signed build or wait for a notarized release.

### Requirements and limits

- Universal Apple Silicon + Intel binaries. App minimum declared: macOS 13; widgets: macOS 14.
- Locally tested on Apple Silicon with macOS 27. Intel and older systems still need physical testing.
- Spotify Premium and an available playback device for controls. Development-mode Spotify apps require allowlisted users. [Spotify access rules](https://developer.spotify.com/documentation/web-api/concepts/quota-modes).
- 24 automated tests passed with mock Spotify; universal build and nested signatures verified.
- Last played does not restore a lost queue or wake devices. Fully offline startup is not guaranteed.
- No developer tokens, session, preferences, or playback cache included.

Read the [English guide](https://github.com/eSneakin/Tracklet/blob/main/README.md) for setup, source builds, troubleshooting, privacy, and contributing. Tracklet's original code and documentation, including this 1.0 release, are licensed under [MIT](https://github.com/eSneakin/Tracklet/blob/main/LICENSE). The archive includes `LICENSE` and `THIRD_PARTY_NOTICES.md`; third-party material is not relicensed.

## Español

Tu reproducción de Spotify, siempre a mano: una app nativa macOS y widgets pequeños, medianos y grandes.

### Novedades

- Spotify OAuth con PKCE y credenciales en Keychain.
- Portada, datos de canción, progreso local y dispositivo.
- Anterior, Play/Pause, Next y repetición en el widget grande.
- Anterior reinicia desde tres segundos; antes de ese punto solicita el contenido anterior.
- Última reproducción conservada por cuenta, congelada cuando no está disponible y borrada al desconectar.
- Preferencias visuales, iconos claro/oscuro y versión 1.0 visible.

### Descarga e instalación

`Tracklet-1.0-macOS-universal-development.zip` incluye app Release, widget integrado y estas notas. Comprueba el archivo con `SHA256SUMS.txt`.

**Artefacto de desarrollo, no instalador final.** Firmado con Apple Development; sin notarizar. La integridad de la firma pasa, pero Gatekeeper devuelve `rejected` en la comprobación local. Para distribución general faltan firma Developer ID y notarización. [Requisitos de Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Para pruebas autorizadas: extrae el ZIP, cierra cualquier copia anterior y mueve `Tracklet.app` a Aplicaciones. Conecta Spotify, reproduce una canción una vez y añade Tracklet desde la galería de widgets. Si macOS bloquea la copia, no desactives Gatekeeper; compila con tu firma o espera una versión notarizada.

### Requisitos y límites

- Binarios universales Apple Silicon + Intel. Mínimo declarado de la app: macOS 13; widgets: macOS 14.
- Probado localmente en Apple Silicon con macOS 27. Intel y versiones anteriores necesitan pruebas físicas.
- Spotify Premium y dispositivo disponible para controles. Las aplicaciones Spotify en development mode requieren usuarios autorizados. [Reglas de Spotify](https://developer.spotify.com/documentation/web-api/concepts/quota-modes).
- 24 tests con Spotify simulado; build universal y firmas de app/extensión verificados.
- Last played no recupera una cola perdida ni activa dispositivos. El inicio completamente offline no está garantizado.
- No incluye tokens, sesión, preferencias ni caché de reproducción del desarrollador.

Consulta la [guía en español](https://github.com/eSneakin/Tracklet/blob/main/README.es.md) para configurar, compilar, resolver problemas, conocer la privacidad y colaborar. El código y la documentación originales de Tracklet, incluida esta versión 1.0, se ofrecen bajo [MIT](https://github.com/eSneakin/Tracklet/blob/main/LICENSE). La descarga incluye `LICENSE` y `THIRD_PARTY_NOTICES.md`; no se cambia la licencia de material de terceros.
