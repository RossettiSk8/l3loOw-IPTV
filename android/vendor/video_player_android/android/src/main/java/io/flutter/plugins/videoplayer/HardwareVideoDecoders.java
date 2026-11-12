package io.flutter.plugins.videoplayer;

import android.app.UiModeManager;
import android.content.Context;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo;
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector;
import java.util.ArrayList;
import java.util.List;

@UnstableApi
public final class HardwareVideoDecoders {
  private HardwareVideoDecoders() {}

  public static ExoPlayer.Builder createBuilder(Context context) {
    UiModeManager mode = context.getSystemService(UiModeManager.class);
    boolean television =
        (mode != null && mode.getCurrentModeType() == Configuration.UI_MODE_TYPE_TELEVISION)
            || context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_LEANBACK);
    if (!television) {
      return new ExoPlayer.Builder(context);
    }
    DefaultRenderersFactory renderers =
        new DefaultRenderersFactory(context)
            .setMediaCodecSelector(HardwareVideoDecoders::decoderInfos)
            .setEnableDecoderFallback(true);
    return new ExoPlayer.Builder(context, renderers);
  }

  private static List<MediaCodecInfo> decoderInfos(
      String mimeType, boolean secure, boolean tunneling)
      throws androidx.media3.exoplayer.mediacodec.MediaCodecUtil.DecoderQueryException {
    List<MediaCodecInfo> defaults =
        MediaCodecSelector.DEFAULT.getDecoderInfos(mimeType, secure, tunneling);
    if (!mimeType.startsWith("video/")) {
      return defaults;
    }
    List<MediaCodecInfo> hardware = new ArrayList<>();
    for (MediaCodecInfo codec : defaults) {
      if (codec.hardwareAccelerated && !codec.softwareOnly) {
        hardware.add(codec);
      }
    }
    return hardware;
  }
}
