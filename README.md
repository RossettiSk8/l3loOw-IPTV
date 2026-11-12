# App Streaming

Base de Flutter para Android, web y LG webOS. La pantalla inicial muestra un título destacado, películas populares y tendencias. Desde la barra superior puedes abrir la configuración de complementos para activarlos o cambiar su prioridad. El orden y los estados se guardan localmente. En TV, las flechas desplazan el foco y OK abre el control enfocado.

## Estructura

```text
lib/
├── core/
│   ├── dependencies/     # AppDependencies
│   └── network/          # Transporte HTTP y errores de estado
├── data/
│   ├── adapters/         # TMDb, Torrentio y video de prueba
│   ├── network/          # Peticiones y decodificación JSON
│   ├── repositories/     # Persistencia de configuración
│   └── streams/          # StreamManager
├── domain/
│   ├── contracts/        # StreamProviderContract, MediaRepository, AddonRepository
│   ├── entities/         # MediaItem, StreamOption, AddonEntity, StreamRequest
│   └── repositories/    # Regla de prioridad de complementos
├── presentation/
│   ├── screens/          # Inicio, detalles, reproducción y complementos
│   └── widgets/          # Controles reutilizables para mando y puntero
└── main.dart
```

La presentación depende de los contratos del dominio. Los adaptadores traducen sus formatos externos a entidades de Dart puro. `lib/core/dependencies/app_dependencies.dart` concentra el ensamblaje y administra el cliente HTTP.

## Consultar el catálogo y resolver streams

Con `TMDB_READ_ACCESS_TOKEN` configurado, el inicio consulta películas populares y tendencias semanales en TMDb. En su ausencia usa un catálogo de demostración local con imágenes de los cortos abiertos de Blender Studio. [Popularidad y tendencias de TMDb](https://developer.themoviedb.org/docs/popularity-and-trending) · [Catálogo de Blender Studio](https://studio.blender.org/films/)

Créditos del catálogo local. Imágenes © Blender Foundation | Blender Studio. Se muestran los archivos originales del catálogo oficial con recorte de encuadre en la interfaz. Consulta la licencia general y las condiciones específicas de cada corto. [Licencias de Blender Studio](https://studio.blender.org/terms-and-conditions/#blender-studio-licences) · [Sprite Fright](https://studio.blender.org/projects/sprite-fright/pages/about/) · [Agent 327](https://studio.blender.org/projects/agent-327/pages/about/)

`MediaRepository.search` busca películas o series en TMDb por título, con paginación. `posterPath` contiene la ruta relativa devuelta por TMDb. Las solicitudes de series identifican un episodio por temporada y número. Torrentio acepta un ID IMDb directamente o resuelve el ID de TMDb a IMDb. [Búsquedas en TMDb](https://developer.themoviedb.org/docs/finding-data) · [Rutas de imágenes](https://developer.themoviedb.org/docs/image-basics)

Este ejemplo resuelve los enlaces de una película obtenida del catálogo.

```dart
final result = await dependencies.streams.resolve(
  StreamRequest.movie(movie),
  mode: StreamChainMode.firstAvailable,
  addonIds: {'torrentio'},
);
final options = result.playableOptions;
final failures = result.failures;
```

- En cada consulta, `StreamManager` lee la configuración guardada con `SharedPreferencesAsync`, ordena los complementos activos por prioridad ascendente y aplica el filtro opcional `addonIds`. Los cambios de Complementos se aplican a la siguiente consulta y se conservan al reabrir la app.
- `collectAll` reúne las opciones y conserva la de mayor prioridad cuando se repite un enlace o la misma referencia BitTorrent. `firstAvailable` respeta la prioridad de los complementos y ordena sus fuentes HTTP(S) por semillas, resolución y tasa de bits anunciada o estimada a partir del tamaño. Una fuente con cero semillas se reserva como respaldo. Los fallos y tiempos de espera permiten continuar la cadena.
- Para añadir un proveedor, implementa `StreamProviderContract` y registra su definición y adaptador en `AppDependencies.create`. La configuración conserva el orden de los complementos conocidos y agrega los nuevos al final.
- Torrentio viene desactivado. El adaptador usa el recurso `stream` del servicio y extrae la resolución, el tamaño y el origen que anuncia Torrentio. Las referencias BitTorrent quedan en `result.options`. El reproductor usa `result.playableOptions`, con enlaces HTTP(S) que no requieren encabezados especiales. Los enlaces progresivos marcados como incompatibles con web se filtran. [Configuración oficial de Torrentio](https://torrentio.strem.fun/configure) · [Protocolo de complementos de Stremio](https://stremio.github.io/stremio-addon-sdk/protocol.html)
- **Reproducir** abre el reproductor con el primer enlace reproducible según la prioridad de los complementos. En **Complementos**, activa **Modo desarrollador** para mostrar **Ver enlaces** en la ficha e inspeccionar las fuentes de Torrentio y seleccionar las reproducibles. El ajuste se guarda en el dispositivo y está desactivado por defecto. El catálogo de demostración incluye reproducción de *Charge* y *Big Buck Bunny* mediante el complemento **Video de prueba**. [Charge](https://video.blender.org/videos/watch/04da454b-9893-4184-98f3-248d00625efe) · [Big Buck Bunny](https://video.blender.org/videos/watch/bf1f3fb5-b119-4f9f-9930-8e20e892b898)
- El reproductor abre directamente la URL elegida. **Manual** ordena las resoluciones fijas de mayor a menor y conserva la posición si ambas fuentes permiten buscar. **Automático** usa la adaptación del motor con manifiestos HLS o DASH compatibles. Para archivos progresivos, usa el búfer y una estimación del rendimiento entre variantes del mismo montaje. El add-on puede declararlas con `variantGroup` e indicar `height` y `bitrate` en bits por segundo. *Charge* ofrece dos variantes para probar este modo. [Selección adaptativa de Media3](https://developer.android.com/reference/androidx/media3/exoplayer/trackselection/AdaptiveTrackSelection)
- En el arranque automático, el reproductor puede probar hasta tres fuentes en un presupuesto de inicialización de 20 segundos. La barra de carga indica la conexión, el cambio de fuente o el relleno del búfer durante la reproducción. Los umbrales del búfer nativo siguen a cargo del motor de cada plataforma.
- El menú **Manual** ofrece todas las resoluciones fijas anunciadas por las fuentes, con independencia del tamaño de la ventana y del monitor. La reproducción depende del códec, el perfil y el motor de reproducción.
- **Audio** muestra las pistas que expone el motor de cada plataforma. **Subtítulos** muestra los archivos externos SRT y WebVTT publicados con el enlace y los lee en memoria. En web, el servidor de subtítulos debe permitir el acceso desde el origen de la aplicación. [Pistas de audio de Flutter](https://pub.dev/packages/video_player/changelog) · [Subtítulos en las opciones de Stremio](https://stremio.github.io/stremio-addon-sdk/api/responses/stream.html)
- Android y web usan `video_player`. En LG, el complemento oficial `video_player_webos` usa el plano de vídeo del sistema y requiere `transparent: true` en `webos/meta/appinfo.json`. [Complementos oficiales de LG](https://github.com/lg-flutter-webos/plugins/blob/main/doc/plugin-list.md)

Para pruebas de desarrollo, pasa `--dart-define=TMDB_READ_ACCESS_TOKEN=...` al ejecutar o compilar y, si corresponde, `--dart-define=TORRENTIO_BASE_URL=https://...`. Se acepta la base del servicio o la URL de su manifiesto, incluidos los enlaces `stremio://` que genera Torrentio. Para reproducir contenido se necesita una configuración que devuelva enlaces HTTP(S). Los valores de `--dart-define` se incluyen en el binario. Mantén las credenciales privadas de producción en un backend. [Autenticación de TMDb](https://developer.themoviedb.org/docs/authentication-application)

## Explorar el catálogo

En móvil, desliza el carrusel de destacados y pulsa **Ver detalles** para abrir la ficha. El menú de tres puntos de la ficha permite guardar o quitar títulos de **Biblioteca** en este dispositivo. **Buscar** filtra por título, género o tipo al escribir y admite consultas sin tildes.

En pantallas amplias, las pestañas y los chips organizan el catálogo cargado y **Reproducir** en el banner abre directamente la fuente prioritaria. *La última frecuencia*, *Correo del cielo*, *Estación Mareas* y *El jardín de las luciérnagas* son títulos ficticios de demostración.

## IPTV y canales en vivo

En **Ajustes → IPTV / Canales en vivo**, importa una URL M3U o M3U8 y activa el interruptor de IPTV. El acceso **TV en vivo** aparecerá en Inicio. El dispositivo conserva las listas importadas y el estado del interruptor.

**Purgar enlaces rotos** elimina las entradas que devuelven HTTP 404 o 410 al comprobarlas. La purga conserva las entradas cuya comprobación es inconclusa. El reproductor abre directamente la URL del canal seleccionado.

## Gestión de energía

Al ir a segundo plano, la app pausa la reproducción, cancela la inicialización pendiente y cierra el cliente HTTP de la app cuando queda ocioso. El video se puede reanudar desde sus controles. Android y los navegadores compatibles solicitan pantalla activa solo durante la reproducción en primer plano. En web, la disponibilidad depende del navegador y de un contexto seguro. [Screen Wake Lock](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API)

El reproductor Android TV limita Media3 a decodificadores de video anunciados como acelerados por hardware. Si la fuente requiere un códec sin soporte, el arranque automático puede probar otro enlace. En PC, la versión web delega la decodificación al navegador. LG webOS usa su motor multimedia nativo. [Información de códecs de Media3](https://developer.android.com/reference/androidx/media3/exoplayer/mediacodec/MediaCodecInfo)

La decodificación de imágenes del catálogo usa límites por tamaño de vista y densidad de pantalla. Los máximos son 768 × 1152 píxeles para pósteres y 1920 × 1080 para panorámicas.

## Ejecutar y compilar

### Vista previa y pruebas

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

La suite automatizada usa respuestas HTTP simuladas para Torrentio. La validación en vivo es opcional y consulta únicamente el manifiesto público y los metadatos de *Big Buck Bunny*.

```sh
dart run test/live/torrentio_probe.dart
```

### Android

Con el SDK de Android y el JDK configurados, ejecuta la compilación desde la raíz del proyecto.

```sh
flutter build apk --debug
```

El APK de prueba se genera en `build/app/outputs/flutter-apk/app-debug.apk`. Para distribuir una versión de producción, configura su firma y usa `flutter build apk --release`. [Configuración de Android](https://docs.flutter.dev/platform-integration/android/setup) · [Firma y publicación](https://docs.flutter.dev/deployment/android)

### LG webOS TV

El runner de `webos/` usa el SDK nativo de LG. Requiere **webOS TV 26 Re:New o posterior** y un entorno Linux con Flutter-webOS, su NDK y la CLI de LG. El complemento oficial de persistencia de LG está fijado por revisión en `pubspec.yaml`. [Compatibilidad de LG](https://webostv.developer.lge.com/news/flutter-for-webos-tv-is-now-available-for-developers) · [Guía del SDK de LG](https://github.com/lg-flutter-webos/flutter-webos/blob/main/doc/getting-started.md)

```sh
flutter-webos doctor -v
flutter-webos pub get
flutter-webos build webos --release --dart-define=WEBOS_BUILD_NUMBER=1
```

El IPK se genera en `build/webos/<arquitectura>/release/ipk/`. Si los SDK de Flutter estándar y LG resuelven versiones distintas, ejecuta `pub get` con el SDK que se usará para compilar. La plantilla del runner y su licencia están en `webos/`.

### Actualizaciones internas

Al abrir l3loOw en Android o LG webOS TV, la app consulta el manifiesto fijo
en segundo plano y abre un diálogo si hay una versión más reciente.
**Ajustes → Versión y actualizaciones → Buscar actualizaciones** consulta el
mismo manifiesto. La URL se define en
[`AppConstants.otaManifestUrl`](lib/core/dependencies/app_constants.dart).

Para publicar, sube primero los binarios a un release público de
`RossettiSk8/l3loOw-IPTV` y después actualiza `version.json` en la raíz de
`main`. En el JSON usa las URL de los archivos adjuntos de ese repositorio
con el tag correspondiente.
[Archivos adjuntos de GitHub Releases](https://docs.github.com/en/rest/releases/releases)

```json
{
  "schema": 1,
  "publishedAt": "2026-11-12",
  "releaseNotes": ["Arranque más rápido", "Mejoras en la navegación con el mando"],
  "mandatory": false,
  "android": {
    "version": "1.0.1",
    "build": 2,
    "url": "https://github.com/RossettiSk8/l3loOw-IPTV/releases/download/v1.0.1/l3loOw-1.0.1.apk",
    "bytes": 12345678,
    "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
  },
  "webos": {
    "version": "1.0.1",
    "url": "https://github.com/RossettiSk8/l3loOw-IPTV/releases/download/v1.0.1/com.appstreaming.app_1.0.1_all.ipk",
    "bytes": 12345678,
    "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
  }
}
```

Sustituye los tamaños y hashes de ejemplo por los valores de los archivos.
La fecha (`publishedAt`), las novedades (`releaseNotes`) y el indicador
`mandatory` son opcionales. Puedes definirlos en el nivel raíz o
sobrescribirlos por plataforma. Con `mandatory: true`, el diálogo indica que
la versión es incompatible y bloquea el acceso al catálogo hasta actualizar
o salir de la aplicación.
Cada plataforma es opcional en el manifiesto.

- **Android y Android TV.** Publica un APK universal con el mismo identificador
  y firma de la instalación anterior, y un `versionCode` superior que coincida
  con `build`. El usuario confirma en el instalador de Android. Si el sistema
  solicita autorizar esta fuente, vuelve a pulsar **Actualizar ahora** después
  de conceder el permiso. Este flujo está pensado para la distribución directa.
  [Permiso de instalación de Android](https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls())
- **LG webOS TV.** Actualiza `webos/meta/appinfo.json` antes de empaquetar.
  Si registras una compilación independiente, inclúyela al empaquetar con
  `--dart-define=WEBOS_BUILD_NUMBER=1`, usando el número de esa compilación.
  l3loOw compara la versión del paquete y muestra la ruta del IPK. Distribuye
  en LG Apps o usa `ares-install -d <dispositivo> <archivo.ipk>` desde el equipo
  autorizado de desarrollo. SI Server pertenece al flujo administrado de los
  equipos Signage que lo admiten y se configura fuera de esta app.
  [Distribución de LG Apps](https://webostv.developer.lge.com/distribute/app-approval-process)
  · [Instalación con la CLI de LG](https://webostv.developer.lge.com/develop/tools/cli-dev-guide)
