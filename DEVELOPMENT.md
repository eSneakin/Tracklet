# Tracklet developer guide / Guía de desarrollo

## English

Welcome! You do not need to understand every file before making a useful change. Start with the flow below, then find the component that owns the behavior you want to change. For installation and Spotify setup, use the [English README](README.md).

### Follow one click

```text
App button or widget intent
    → PlaybackViewModel: validate state and prevent duplicate actions
    → SpotifyPlaybackService: express the playback operation
    → SpotifyAPIClient: send the authenticated request
    → Spotify: return the result
    → refreshed PlaybackState → app UI + shared snapshot → widget
```

The important boundary: a view describes what appears on screen; it does not construct HTTP requests or handle tokens. The widget reads a saved snapshot, while its buttons ask the host app to perform an action.

### A few names worth knowing

| Name | Think of it as… |
| --- | --- |
| Runtime / composition root | The place that creates and connects services, so each screen does not create its own session. |
| ViewModel | The bridge between visible UI and operations such as loading playback. |
| DTO (Data Transfer Object) | A structure matching Spotify's JSON response. It is translated into Tracklet's own model before reaching the UI. |
| Domain model | Tracklet's representation of a song or playback state, independent of Spotify's response format. |
| App Intent | An action macOS can invoke, such as a widget's Play button. It is not a separate Spotify client. |
| Timeline | The entries WidgetKit uses to decide what a widget displays over time; not a continuously running app loop. |
| Atomic write | Replacing a complete saved file in one operation, so another process does not read a half-written snapshot. |
| Target membership | Which executable a source file belongs to: the main app, the widget extension, or both. |

### Who owns what?

Start at `TrackletRuntime`: it creates one authentication service, API client, playback model and widget publisher. The window and App Intents reuse that runtime.

- **Authentication:** `SpotifyAuthService` owns PKCE, token refresh and cancellation. Concurrent callers share one refresh. Generation checks prevent a late login/refresh from restoring a disconnected account. `CredentialStore` is the only Keychain boundary; updates do not delete the old entry first.
- **Networking:** `SpotifyAPIClient` sends all Web API requests. Reads and commands share one 401 refresh/retry and a `Retry-After` deadline. DTOs are mapped by `SpotifyPlaybackService`; views never decode Spotify JSON.
- **Playback state:** `PlaybackViewModel.state` describes visible content; `isRefreshing` and `isPerformingPlaybackAction` describe separate operations. Background refresh never clears confirmed playback. An empty response retains last-played metadata, but never claims an old device is active. Commands revalidate Spotify first.
- **Account isolation:** `WidgetSnapshotPublisher` observes authentication even without App Group storage. Snapshots carry an account ID; another account cannot restore that history. Disconnect clears visible and shared playback.
- **Preferences and artwork:** `SettingsViewModel` persists preferences. The app uses `trackletArtworkStyle`; the widget uses `WidgetArtworkImage` to bake monochrome into image pixels before remote rendering. A local SwiftUI preview is not sufficient to validate WidgetKit effects. Original cached images remain unchanged when switching styles.
- **Widgets:** the provider reads atomic snapshots and cached thumbnails only. Spotify requests and credentials stay in the host app. App Intents invoke the same playback actions as the window.
- **Icons:** `Resources/AppIcon.icon` is compiled into both targets, including legacy `.icns` fallbacks. Default is light; Dark is dark. macOS selects icon style independently from window appearance. Do not replace the Dock icon at runtime or force global system appearance.

### Check a change

Run these from the repository root. The build command below targets Apple Silicon (`arm64`); adjust the destination for an Intel development Mac.

```sh
swift test
xcodebuild -project Tracklet.xcodeproj -scheme Tracklet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode build
ruby Scripts/check-app-icon.rb
```

`swift test` checks behavior without a real account. `xcodebuild` checks the app and extension together. The icon script checks their packaged resources. A successful test run does not prove that a live Spotify device or the desktop gallery works: those need a manual check too.

For an installed app with widgets already displayed, these additional diagnostics help distinguish packaging from runtime problems:

```sh
ruby Scripts/check-widget-runtime.rb 5m
xcrun clang -fobjc-arc -framework AppKit Scripts/check-installed-icon.m \
  -o /tmp/tracklet-check-icon && /tmp/tracklet-check-icon
```

Tests use fake HTTP responses and in-memory credentials, never a real Spotify account. Rendering tests check actual pixels for monochrome artwork. Icon checks inspect both compiled bundles. Manual checks still matter: installed app, widget gallery, system icon styles, and real Spotify devices.

A useful manual pass takes one song: connect, play, pause, skip, and try Previous on either side of three seconds. Watch a background refresh without clicking anything; the card should stay visible and progress should continue. Check all three widget sizes, each artwork style, and finally Disconnect. Never use a real token in a test fixture.

### Advanced diagnostics: icons and widget registration

`check-installed-icon.m` is an optional macOS-specific diagnostic, not app code. It uses private IconServices APIs to compare lookup by app identifier against lookup by bundle URL, in default and current system icon styles. `Assets.car` is the compiled asset catalog: a valid catalog does not guarantee that macOS resolves the correct icon by app identifier. These APIs can change; the diagnostic never changes icon preferences or clears caches. A passing result does not replace visual gallery verification. Do not disable SIP (System Integrity Protection) to restart a protected service, and do not assume a reboot will repair a persistent icon cache entry.

Runtime checks require all three sizes to have been displayed. Their saved timeline files do not prove that every widget is showing fresh data; inspect the desktop too. Do not use `pluginkit -r` to remove a development extension while WidgetKit still references it: the cached executable can crash at startup with `Invalid bundle record for current process`. Diagnose the exact host app's registration before attempting a repair. Keep development copies registered while in use; never clear global caches to fix one app. A registered installed copy alone does not prove WidgetKit is running that copy.

After adding a source file, update Xcode target membership as well as SwiftPM. Files in `Shared`, playback/preferences models and the theme compile into both targets. `Scripts/generate-xcode-project.rb` documents membership; regeneration replaces the project, so review its diff.

### Where to extend behavior

- **New API read:** add the endpoint in `SpotifyAPIClient`, decode a DTO, then map it in `SpotifyPlaybackService`. Keep refresh/retry/rate limits in the existing HTTP request path. `SpotifyCollectionDTO` deliberately shares album/show decoding; it is not the UI model.
- **New playback action:** extend `PlaybackAction`, its `AppEnum` labels and the service dispatcher. Route UI/intents through `PlaybackViewModel` so device revalidation, duplicate-click protection and confirmation remain shared.
- **New preference:** update the shared models and settings binding. Preserve JSON compatibility and add a round-trip/migration test before changing saved fields. Credentials never belong in this model.
- **Visible playback:** use `State.playback` to read the payload without duplicating the playing/paused/history switch. Initial loading, background refresh and action progress remain separate concepts.
- **Visual changes:** app buttons and widget buttons intentionally have different implementations (hover/AppKit versus App Intent rendering). Share domain behavior, not platform-specific interaction code. Run `render-widget-previews.swift` for layouts and empty states; also inspect the real desktop widgets.

The icon diagnostic now checks 10 sizes at 1×/2× in both default and current system style. A past gallery failure persisted after reboot because a cached raster was wrong; replacing the affected cache entry and restarting NotificationCenter resolved it locally. Do not ship cache mutations or private IconServices calls in Tracklet, and never copy a cache UUID from another machine.

## Español

¡Bienvenido! No necesitas entender todos los archivos para aportar una mejora. Empieza por el recorrido siguiente y busca después el componente responsable del comportamiento que quieres cambiar. Para instalar y configurar Spotify, consulta el [README en español](README.es.md).

### Sigue el recorrido de un clic

```text
Botón de la app o intent del widget
    → PlaybackViewModel: validar estado y evitar acciones duplicadas
    → SpotifyPlaybackService: expresar la operación de reproducción
    → SpotifyAPIClient: enviar la petición autenticada
    → Spotify: devolver el resultado
    → PlaybackState actualizado → UI + snapshot compartido → widget
```

La separación importante: una vista describe lo que aparece en pantalla; no construye peticiones HTTP ni maneja tokens. El widget lee una copia guardada del estado y sus botones piden a la app principal que ejecute la acción.

### Nombres que conviene conocer

| Nombre | Piensa en… |
| --- | --- |
| Runtime / composition root | El lugar donde se crean y conectan servicios, evitando que cada pantalla cree su propia sesión. |
| ViewModel | El puente entre la interfaz visible y operaciones como consultar la reproducción. |
| DTO (Data Transfer Object) | Una estructura que refleja el JSON de Spotify. Se transforma al modelo de Tracklet antes de llegar a la UI. |
| Modelo de dominio | La representación propia de una canción o reproducción, independiente del formato de Spotify. |
| App Intent | Una acción que macOS puede invocar, como Play desde el widget. No es otro cliente de Spotify. |
| Timeline | Las entradas con las que WidgetKit decide qué mostrar a lo largo del tiempo; no es una app ejecutándose continuamente. |
| Escritura atómica | Reemplazar un archivo completo de una vez para que otro proceso no lea un snapshot a medio guardar. |
| Target membership | La pertenencia de un archivo a la app, la extensión del widget o ambas al compilar. |

### ¿Quién se encarga de cada cosa?

Empieza por `TrackletRuntime`: construye una sola instancia de autenticación, cliente API, modelo de reproducción y publicador del widget. Ventana y App Intents reutilizan ese runtime.

- **Autenticación:** `SpotifyAuthService` controla PKCE, renovación y cancelación. Las llamadas concurrentes comparten la renovación. La validación de generación impide que una respuesta tardía reactive una cuenta desconectada. `CredentialStore` concentra Keychain y actualiza sin borrar primero la credencial anterior.
- **Red:** `SpotifyAPIClient` concentra las peticiones Web API, un solo reintento tras 401 y la espera de `Retry-After`. `SpotifyPlaybackService` transforma DTOs en modelos propios; las vistas no interpretan JSON de Spotify.
- **Estado:** `state` representa contenido visible; `isRefreshing` y `isPerformingPlaybackAction`, operaciones independientes. Una actualización no borra la última reproducción confirmada. Una respuesta vacía conserva historial, sin inventar un dispositivo activo. Cada acción consulta primero el estado real.
- **Cuentas:** `WidgetSnapshotPublisher` observa autenticación incluso sin almacenamiento App Group. El historial compartido pertenece a un ID de cuenta. Disconnect limpia reproducción visible y compartida.
- **Preferencias y artwork:** `SettingsViewModel` persiste preferencias. La app usa `trackletArtworkStyle`; el widget usa `WidgetArtworkImage` para convertir los píxeles a gris antes del render remoto. Una preview local de SwiftUI no basta para validar efectos en WidgetKit. Cambiar estilo no modifica las imágenes originales de la caché.
- **Widgets:** el proveedor solo lee snapshots atómicos y miniaturas. Peticiones Spotify y credenciales permanecen en la app. Los intents reutilizan sus acciones de reproducción.
- **Iconos:** ambos targets compilan `Resources/AppIcon.icon`, con `.icns` para compatibilidad. Default corresponde al claro; Dark, al oscuro. macOS permite elegir el estilo de iconos independientemente del aspecto de las ventanas. No fuerces ajustes globales ni reemplaces el icono del Dock durante ejecución.

### Comprueba un cambio

Ejecuta los comandos de la sección inglesa desde la raíz del repositorio. El comando de compilación usa Apple Silicon (`arm64`); ajusta el destino si desarrollas en un Mac Intel. `swift test` comprueba comportamiento sin una cuenta real, `xcodebuild` compila app y extensión juntas, y el script de iconos comprueba sus recursos empaquetados. Los diagnósticos adicionales requieren la app instalada y los widgets ya mostrados.

Las pruebas usan HTTP simulado y credenciales en memoria; no controlan Spotify real. Se comprueban píxeles monocromáticos y recursos compilados de ambos bundles. Que pasen no demuestra que la galería o un dispositivo real funcionen: necesitan revisión manual.

Una prueba manual útil empieza con una canción: conecta, reproduce, pausa, avanza y prueba Anterior antes y después de tres segundos. Observa una actualización de fondo sin pulsar nada: la tarjeta debe permanecer visible y el progreso debe continuar. Revisa los tres tamaños, cada estilo de portada y, al final, Disconnect. Nunca incluyas tokens reales en datos de prueba.

### Diagnósticos avanzados: iconos y registro del widget

`check-installed-icon.m` es un diagnóstico opcional específico de macOS; no forma parte de la app. Usa APIs privadas de IconServices para comparar la carga por identificador y por ruta del bundle, con estilo predeterminado y estilo actual del sistema. `Assets.car` es el catálogo de recursos compilados: que sea válido no garantiza que macOS encuentre el icono correcto mediante el identificador de la app. Estas APIs pueden cambiar. La prueba no modifica preferencias ni limpia cachés; tampoco sustituye la revisión visual de la galería. No desactives SIP (Protección de Integridad del Sistema) para reiniciar un servicio protegido, ni asumas que reiniciar el Mac reparará una entrada persistente de caché.

La comprobación de runtime requiere haber mostrado los tres tamaños. Encontrar sus archivos de timeline no demuestra que todos muestren datos recientes: revisa también el escritorio. No retires una extensión de desarrollo con `pluginkit -r` mientras WidgetKit aún la referencia: puede arrancar la ruta almacenada y fallar con `Invalid bundle record for current process`. Diagnostica el registro de la app concreta antes de repararlo. Conserva registros de copias en uso y no borres cachés globales. Tener registrada la copia instalada no demuestra que sea la que ejecuta WidgetKit.

Al añadir archivos, actualiza membresía de targets Xcode además de SwiftPM. `Shared`, modelos de reproducción/preferencias y tema se compilan en ambos targets. El generador documenta esta selección; regenerar reemplaza el proyecto, por lo que debes revisar el diff.

### Dónde ampliar funcionalidad

- **Lectura API:** añade endpoint en `SpotifyAPIClient`, DTO y conversión en `SpotifyPlaybackService`. Reutiliza renovación, reintento y límites HTTP. `SpotifyCollectionDTO` comparte el formato de álbum/show; no es un modelo de UI.
- **Acción:** amplía `PlaybackAction`, sus etiquetas `AppEnum` y el dispatcher del servicio. UI e intents pasan por `PlaybackViewModel` para compartir validación del dispositivo, bloqueo de clics repetidos y confirmación.
- **Preferencia:** modifica modelos compartidos y binding de ajustes, manteniendo compatibilidad JSON. Añade prueba de persistencia/migración; nunca mezcles credenciales.
- **Playback visible:** consulta `State.playback` sin repetir switches de reproducción/pausa/historial. Carga inicial, actualización de fondo y acción en curso siguen separados.
- **UI:** botones de app y widget difieren intencionalmente: hover/AppKit frente a App Intents y render remoto. Comparte dominio, no interacción específica de plataforma. El script de previews incluye estados vacíos; comprueba también widgets reales.

El diagnóstico del icono comprueba 10 tamaños a 1×/2× con estilo predeterminado y estilo actual. Un fallo de galería persistió tras reiniciar por una imagen incorrecta en caché; apartar esa entrada y reiniciar NotificationCenter lo resolvió localmente. No incluyas modificaciones de caché ni APIs privadas de IconServices en la app, ni reutilices UUID de caché de otro Mac.
