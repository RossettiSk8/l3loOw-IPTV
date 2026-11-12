# Adaptación de video_player_android

Código de producción de video_player_android 2.12.2, distribuido bajo la licencia BSD incluida. Se conservan las implementaciones de textura y vista nativa. En Android TV, ambas construyen ExoPlayer mediante `HardwareVideoDecoders`, que filtra los decodificadores de video según las capacidades informadas por Media3. Para códecs sin decodificador de hardware, el reproductor puede intentar otra fuente.

Al actualizar la dependencia, vuelve a aplicar la política en las dos fábricas y comprueba la reproducción en Android TV.
