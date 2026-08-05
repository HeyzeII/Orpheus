package com.heyzell.orpheus

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    companion object {
        // Must exactly match AudioServiceConfig.androidNotificationChannelId in main.dart.
        // audio_service's createChannel() checks "if (channel == null)" before creating —
        // so pre-creating here with IMPORTANCE_DEFAULT prevents it from downgrading to IMPORTANCE_LOW.
        private const val AUDIO_CHANNEL_ID   = "com.heyzell.orpheus.channel.playback"
        private const val AUDIO_CHANNEL_NAME = "Orpheus — Reproducción"
        private const val AUDIO_CHANNEL_DESC = "Controles de reproducción de música de Orpheus"
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationChannel()
    }

    /**
     * Pre-creates the media notification channel with the correct importance level
     * BEFORE audio_service has a chance to create it with its hardcoded IMPORTANCE_LOW.
     *
     * Why this is necessary:
     *  • audio_service 0.18.x always creates the channel with IMPORTANCE_LOW (AudioService.java:691).
     *  • On MIUI / HyperOS and several OEMs, IMPORTANCE_LOW notifications are completely hidden
     *    from the notification shade / pull-down curtain — even though the foreground service
     *    is running and the MediaSession is active (which is why Bluetooth controls still work).
     *  • Android's NotificationManager.createNotificationChannel() is idempotent for the same ID:
     *    if the channel already exists it is a no-op, preserving our higher importance.
     *  • IMPORTANCE_DEFAULT = sound disabled for media channels (we disable sound below)
     *    but still shows in the shade. VISIBILITY_PUBLIC makes the full card appear on lockscreen.
     */
    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

        // Only create if the channel doesn't already exist to avoid resetting user customizations.
        if (nm.getNotificationChannel(AUDIO_CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            AUDIO_CHANNEL_ID,
            AUDIO_CHANNEL_NAME,
            // IMPORTANCE_DEFAULT: shows in shade + status bar icon, no heads-up popup.
            // This is the minimum importance level that reliably appears in the notification
            // shade on strict OEMs (MIUI, One UI, ColorOS). IMPORTANCE_LOW is silently
            // hidden by these OEMs for third-party apps.
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = AUDIO_CHANNEL_DESC
            // Media players must not make sounds or vibrate — disable both explicitly.
            setSound(null, null)
            enableVibration(false)
            enableLights(false)
            // Show full media card on the lock screen (title, artist, artwork, controls).
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            // No badge dot on launcher icon for a background service.
            setShowBadge(false)
        }

        nm.createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.heyzell.orpheus/app_control"
        ).setMethodCallHandler { call, result ->
            if (call.method == "minimizeApp") {
                moveTaskToBack(true)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }
}

