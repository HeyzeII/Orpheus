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
            } else if (call.method == "getNotificationDiagnostics") {
                val report = mutableMapOf<String, Any?>()
                
                // 1. Check Notification Channel & General Permissions
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                    val channel = nm.getNotificationChannel(AUDIO_CHANNEL_ID)
                    if (channel != null) {
                        report["channelExists"] = true
                        report["channelImportance"] = channel.importance
                        report["channelLockscreenVisibility"] = channel.lockscreenVisibility
                        report["channelBypassDnd"] = channel.canBypassDnd()
                        report["channelShowBadge"] = channel.canShowBadge()
                        report["channelId"] = channel.id
                        report["channelName"] = channel.name.toString()
                    } else {
                        report["channelExists"] = false
                    }
                    
                    report["areNotificationsEnabled"] = nm.areNotificationsEnabled()
                } else {
                    report["channelExists"] = null
                    report["channelMsg"] = "API level lower than 26"
                }

                // 2. AudioService Runtime Auditor using reflection
                try {
                    val serviceClass = Class.forName("com.ryanheise.audioservice.AudioService")
                    fun getFieldSafely(targetClass: Class<*>, fieldName: String): java.lang.reflect.Field? {
                        var cur: Class<*>? = targetClass
                        while (cur != null) {
                            val f = cur.declaredFields.firstOrNull { it.name == fieldName }
                            if (f != null) return f
                            cur = cur.superclass
                        }
                        return null
                    }

                    val instanceField = getFieldSafely(serviceClass, "instance")
                    val serviceInstance = if (instanceField != null) {
                        instanceField.isAccessible = true
                        instanceField.get(null)
                    } else null
                    
                    if (serviceInstance != null) {
                        report["serviceRunning"] = true
                        
                        // Inspect mediaSession via reflection
                        try {
                            val mediaSessionField = getFieldSafely(serviceClass, "mediaSession")
                            val mediaSession = if (mediaSessionField != null) {
                                mediaSessionField.isAccessible = true
                                mediaSessionField.get(serviceInstance)
                            } else null

                            if (mediaSession != null) {
                                val isActiveMethod = mediaSession.javaClass.getMethod("isActive")
                                report["mediaSessionActive"] = isActiveMethod.invoke(mediaSession) as? Boolean ?: false
                            } else {
                                report["mediaSessionActive"] = false
                            }
                        } catch (e: Exception) {
                            report["mediaSessionError"] = e.toString()
                        }
                        
                        // Inspect notificationCreated
                        try {
                            val notifCreatedField = getFieldSafely(serviceClass, "notificationCreated")
                            if (notifCreatedField != null) {
                                notifCreatedField.isAccessible = true
                                report["notificationCreated"] = notifCreatedField.get(serviceInstance) as? Boolean ?: false
                            } else {
                                report["notificationCreated"] = false
                            }
                        } catch (e: Exception) {
                            report["notificationCreatedError"] = e.toString()
                        }

                        // Inspect metadata
                        try {
                            val metadataField = getFieldSafely(serviceClass, "mediaMetadata")
                            val metadata = if (metadataField != null) {
                                metadataField.isAccessible = true
                                metadataField.get(serviceInstance)
                            } else null

                            if (metadata != null) {
                                report["metadataLoaded"] = true
                                val getDescriptionMethod = metadata.javaClass.getMethod("getDescription")
                                val desc = getDescriptionMethod.invoke(metadata)
                                if (desc != null) {
                                    val getTitleMethod = desc.javaClass.getMethod("getTitle")
                                    val getSubtitleMethod = desc.javaClass.getMethod("getSubtitle")
                                    report["metadataTitle"] = getTitleMethod.invoke(desc)?.toString()
                                    report["metadataArtist"] = getSubtitleMethod.invoke(desc)?.toString()
                                }
                            } else {
                                report["metadataLoaded"] = false
                            }
                        } catch (e: Exception) {
                            report["metadataError"] = e.toString()
                        }
                        
                        // Inspect artBitmap
                        try {
                            val artBitmapField = getFieldSafely(serviceClass, "artBitmap")
                            val artBitmap = if (artBitmapField != null) {
                                artBitmapField.isAccessible = true
                                artBitmapField.get(serviceInstance) as? android.graphics.Bitmap
                            } else null

                            if (artBitmap != null) {
                                report["artBitmapLoaded"] = true
                                report["artBitmapWidth"] = artBitmap.width
                                report["artBitmapHeight"] = artBitmap.height
                            } else {
                                report["artBitmapLoaded"] = false
                            }
                        } catch (e: Exception) {
                            report["artBitmapError"] = e.toString()
                        }
                        
                        // Inspect notificationChannelId
                        try {
                            val serviceChannelIdField = getFieldSafely(serviceClass, "notificationChannelId")
                            if (serviceChannelIdField != null) {
                                serviceChannelIdField.isAccessible = true
                                report["serviceNotificationChannelId"] = serviceChannelIdField.get(serviceInstance) as? String
                            }
                        } catch (e: Exception) {
                            report["serviceNotificationChannelIdError"] = e.toString()
                        }

                        // Inspect playing
                        try {
                            val playingField = getFieldSafely(serviceClass, "playing")
                            if (playingField != null) {
                                playingField.isAccessible = true
                                report["servicePlaying"] = playingField.get(serviceInstance) as? Boolean ?: false
                            }
                        } catch (e: Exception) {
                            report["servicePlayingError"] = e.toString()
                        }
                        
                        // Inspect processingState
                        try {
                            val procStateField = getFieldSafely(serviceClass, "processingState")
                            if (procStateField != null) {
                                procStateField.isAccessible = true
                                val procState = procStateField.get(serviceInstance)
                                report["serviceProcessingState"] = procState?.toString()
                            }
                        } catch (e: Exception) {
                            report["serviceProcessingStateError"] = e.toString()
                        }
                    } else {
                        report["serviceRunning"] = false
                    }
                } catch (e: Exception) {
                    report["serviceRunning"] = false
                    report["serviceError"] = e.toString()
                }
                
                result.success(report)
            } else {
                result.notImplemented()
            }
        }
    }
}

