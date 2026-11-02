package com.heyzell.orpheus

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.net.Uri
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaControllerCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.view.KeyEvent
import android.widget.RemoteViews
import androidx.media.session.MediaButtonReceiver
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

/**
 * Native Android AppWidgetProvider for Orpheus (Immersive 4x3 full-art widget).
 */
class OrpheusWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        try {
            for (appWidgetId in appWidgetIds) {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Unhandled exception in onUpdate", t)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle?
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        try {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        } catch (t: Throwable) {
            Log.e(TAG, "Unhandled exception in onAppWidgetOptionsChanged", t)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        try {
            super.onReceive(context, intent)
            if (intent.action == ACTION_TOGGLE_LIKE) {
                handleToggleLike(context)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Unhandled exception in onReceive", t)
        }
    }

    companion object {
        const val TAG = "OrpheusWidgetProvider"
        const val ACTION_TOGGLE_LIKE = "com.heyzell.orpheus.ACTION_TOGGLE_LIKE"

        /**
         * Safely loads, center-crops to target aspect ratio, subsamples, and rounds a bitmap from disk.
         * Crucially, the rounded corners (24dp) are applied directly to the final cropped canvas bounds,
         * ensuring the corner curves match the widget container without being sliced off by centerCrop.
         */
        fun loadOptimizedBitmap(
            filePath: String?,
            reqWidth: Int = 400,
            reqHeight: Int = 400,
            cornerRadiusDp: Float = 0f,
            context: Context? = null
        ): Bitmap? {
            if (filePath.isNullOrEmpty()) return null
            return try {
                val file = File(filePath)
                if (!file.exists() || !file.canRead() || file.length() == 0L) return null

                // 1. Decode bounds only
                val options = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeFile(file.absolutePath, options)
                if (options.outWidth <= 0 || options.outHeight <= 0) return null

                // 2. Compute the optimal inSampleSize (power of 2)
                var inSampleSize = 1
                if (options.outHeight > reqHeight || options.outWidth > reqWidth) {
                    val halfHeight = options.outHeight / 2
                    val halfWidth = options.outWidth / 2
                    while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
                        inSampleSize *= 2
                    }
                }

                // 3. Decode bitmap
                val decodeOptions = BitmapFactory.Options().apply {
                    this.inSampleSize = inSampleSize
                    inPreferredConfig = if (cornerRadiusDp > 0f) Bitmap.Config.ARGB_8888 else Bitmap.Config.RGB_565
                    inDither = true
                }
                val rawBitmap = BitmapFactory.decodeFile(file.absolutePath, decodeOptions) ?: return null

                if (cornerRadiusDp > 0f && context != null) {
                    val cornerRadiusPx = cornerRadiusDp * context.resources.displayMetrics.density
                    toCropRoundedBitmap(rawBitmap, reqWidth, reqHeight, cornerRadiusPx)
                } else {
                    rawBitmap
                }
            } catch (e: Throwable) {
                Log.w(TAG, "Failed to load bitmap from $filePath: ${e.message}")
                null
            }
        }

        private fun toCropRoundedBitmap(
            source: Bitmap,
            targetWidth: Int,
            targetHeight: Int,
            cornerRadiusPx: Float
        ): Bitmap {
            val output = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

            // 1. Draw rounded rectangle mask
            val rect = RectF(0f, 0f, targetWidth.toFloat(), targetHeight.toFloat())
            canvas.drawRoundRect(rect, cornerRadiusPx, cornerRadiusPx, paint)

            // 2. Compute centerCrop transformation
            val srcWidth = source.width.toFloat()
            val srcHeight = source.height.toFloat()
            val scale = maxOf(targetWidth.toFloat() / srcWidth, targetHeight.toFloat() / srcHeight)
            val dx = (targetWidth.toFloat() - srcWidth * scale) * 0.5f
            val dy = (targetHeight.toFloat() - srcHeight * scale) * 0.5f

            val matrix = android.graphics.Matrix().apply {
                setScale(scale, scale)
                postTranslate(dx, dy)
            }

            // 3. Draw source bitmap masked strictly inside the rounded rect
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(source, matrix, paint)

            return output
        }

        fun buildMediaPendingIntent(context: Context, action: Long, keyCode: Int, requestCode: Int): PendingIntent? {
            return try {
                MediaButtonReceiver.buildMediaButtonPendingIntent(context, action)
                    ?: run {
                        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                            component = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
                            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
                        }
                        PendingIntent.getBroadcast(
                            context,
                            requestCode,
                            intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                    }
            } catch (t: Throwable) {
                Log.w(TAG, "MediaButtonReceiver error for action $action; using fallback intent", t)
                try {
                    val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                        component = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
                        putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
                    }
                    PendingIntent.getBroadcast(
                        context,
                        requestCode,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                } catch (inner: Throwable) {
                    null
                }
            }
        }

        /**
         * Centralized logic to toggle like state:
         * 1. Inverts boolean optimistically in SharedPreferences.
         * 2. Immediately updates all widgets.
         * 3. Dispatches background event to Dart / AudioService to persist state.
         */
        fun handleToggleLike(context: Context) {
            try {
                val widgetData = HomeWidgetPlugin.getData(context)
                val currentLiked = widgetData.getBoolean("is_liked", false)
                val newLiked = !currentLiked
                widgetData.edit().putBoolean("is_liked", newLiked).apply()
                Log.i(TAG, "Optimistic like toggled: $newLiked")
            } catch (e: Throwable) {
                Log.e(TAG, "Error toggling like state in SharedPreferences", e)
            }

            // Immediately update both widgets with new icon
            updateAllWidgets(context)

            // Notify Dart via HomeWidgetBackgroundReceiver
            try {
                val bgIntent = Intent().apply {
                    setClassName(context.packageName, "es.antonborri.home_widget.HomeWidgetBackgroundReceiver")
                    action = "es.antonborri.home_widget.action.BACKGROUND"
                    data = Uri.parse("orpheus://toggle_like")
                }
                context.sendBroadcast(bgIntent)
            } catch (e: Throwable) {
                Log.w(TAG, "Could not send HomeWidgetBackgroundReceiver broadcast: ${e.message}")
            }

            // Also forward via MediaBrowser to AudioService customAction("toggle_like") if connected
            try {
                var browser: MediaBrowserCompat? = null
                browser = MediaBrowserCompat(
                    context.applicationContext,
                    ComponentName(context.packageName, "com.ryanheise.audioservice.AudioService"),
                    object : MediaBrowserCompat.ConnectionCallback() {
                        override fun onConnected() {
                            try {
                                val token = browser?.sessionToken
                                if (token != null) {
                                    val controller = MediaControllerCompat(context, token)
                                    controller.transportControls.sendCustomAction("toggle_like", null)
                                }
                            } catch (e: Throwable) {
                                Log.w(TAG, "Failed to send customAction to MediaController: ${e.message}")
                            } finally {
                                browser?.disconnect()
                            }
                        }
                        override fun onConnectionFailed() {
                            browser?.disconnect()
                        }
                    },
                    null
                )
                browser.connect()
            } catch (e: Throwable) {
                Log.w(TAG, "Could not initiate MediaBrowser for like action: ${e.message}")
            }
        }

        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            // 1. Update immersive widgets
            val immersiveComponent = ComponentName(context, OrpheusWidgetProvider::class.java)
            val immersiveIds = appWidgetManager.getAppWidgetIds(immersiveComponent)
            if (immersiveIds != null && immersiveIds.isNotEmpty()) {
                for (id in immersiveIds) {
                    updateAppWidget(context, appWidgetManager, id)
                }
            }

            // 2. Update compact widgets
            val compactComponent = ComponentName(context, OrpheusCompactWidgetProvider::class.java)
            val compactIds = appWidgetManager.getAppWidgetIds(compactComponent)
            if (compactIds != null && compactIds.isNotEmpty()) {
                for (id in compactIds) {
                    OrpheusCompactWidgetProvider.updateAppWidget(context, appWidgetManager, id)
                }
            }
        }

        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            try {
                val views = RemoteViews(context.packageName, R.layout.orpheus_widget_immersive_layout)

                var title = "Orpheus"
                var artist = "Escucha algo grandioso"
                var isPlaying = false
                var isLiked = false
                var coverPath: String? = null

                try {
                    val widgetData = HomeWidgetPlugin.getData(context)
                    title = widgetData.getString("track_title", "Orpheus") ?: "Orpheus"
                    artist = widgetData.getString("track_artist", "Escucha algo grandioso") ?: "Escucha algo grandioso"
                    isPlaying = widgetData.getBoolean("is_playing", false)
                    isLiked = widgetData.getBoolean("is_liked", false)
                    coverPath = widgetData.getString("cover_path", null)
                } catch (dataEx: Throwable) {
                    Log.w(TAG, "Could not read HomeWidget data: ${dataEx.message}")
                }

                views.setTextViewText(R.id.widget_track_title, title)
                views.setTextViewText(R.id.widget_track_artist, artist)

                // Widget es cuadrado (2×2 celdas). Usamos el menor de los dos ejes como lado del cuadrado.
                val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
                val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).takeIf { it > 0 } ?: 160
                val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT).takeIf { it > 0 } ?: 160
                val sideDp = minOf(widthDp, heightDp)
                val density = context.resources.displayMetrics.density
                val sidePx = maxOf((sideDp * density).toInt(), 540)

                val coverBitmap = loadOptimizedBitmap(
                    filePath = coverPath,
                    reqWidth = sidePx,
                    reqHeight = sidePx,
                    cornerRadiusDp = 24f,
                    context = context
                )
                if (coverBitmap != null) {
                    views.setImageViewBitmap(R.id.widget_cover_image, coverBitmap)
                } else {
                    views.setImageViewResource(R.id.widget_cover_image, R.drawable.widget_immersive_background)
                }

                views.setImageViewResource(
                    R.id.widget_btn_play_pause,
                    if (isPlaying) R.drawable.ic_pause else R.drawable.ic_play
                )

                views.setImageViewResource(
                    R.id.widget_btn_like,
                    if (isLiked) R.drawable.ic_heart_filled else R.drawable.ic_heart_outline
                )

                val prevIntent = buildMediaPendingIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 101)
                if (prevIntent != null) views.setOnClickPendingIntent(R.id.widget_btn_prev, prevIntent)

                val playPauseIntent = buildMediaPendingIntent(context, PlaybackStateCompat.ACTION_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 102)
                if (playPauseIntent != null) views.setOnClickPendingIntent(R.id.widget_btn_play_pause, playPauseIntent)

                val nextIntent = buildMediaPendingIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_NEXT, KeyEvent.KEYCODE_MEDIA_NEXT, 103)
                if (nextIntent != null) views.setOnClickPendingIntent(R.id.widget_btn_next, nextIntent)

                // Wire Like button
                val likeIntent = Intent(context, OrpheusWidgetProvider::class.java).apply {
                    action = ACTION_TOGGLE_LIKE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                }
                val likePendingIntent = PendingIntent.getBroadcast(
                    context,
                    appWidgetId + 2000,
                    likeIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_btn_like, likePendingIntent)

                // Wire launch intent
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launchIntent != null) {
                    launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    val appPendingIntent = PendingIntent.getActivity(
                        context,
                        appWidgetId + 1000,
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    views.setOnClickPendingIntent(R.id.widget_cover_image, appPendingIntent)
                    views.setOnClickPendingIntent(R.id.widget_metadata_container, appPendingIntent)
                }

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (t: Throwable) {
                Log.e(TAG, "Critical failure during updateAppWidget for id $appWidgetId: ${t.message}", t)
                applyFallback(context, appWidgetManager, appWidgetId)
            }
        }

        fun applyFallback(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            try {
                val views = RemoteViews(context.packageName, R.layout.orpheus_widget_immersive_layout)
                views.setTextViewText(R.id.widget_track_title, "Orpheus")
                views.setTextViewText(R.id.widget_track_artist, "Escucha algo grandioso")
                views.setImageViewResource(R.id.widget_cover_image, R.drawable.widget_immersive_background)
                views.setImageViewResource(R.id.widget_btn_play_pause, R.drawable.ic_play)
                views.setImageViewResource(R.id.widget_btn_like, R.drawable.ic_heart_outline)
                views.setImageViewResource(R.id.widget_btn_prev, R.drawable.ic_skip_previous)
                views.setImageViewResource(R.id.widget_btn_next, R.drawable.ic_skip_next)

                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launchIntent != null) {
                    launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    val appPendingIntent = PendingIntent.getActivity(
                        context,
                        appWidgetId,
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    views.setOnClickPendingIntent(R.id.widget_container, appPendingIntent)
                }

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (fallbackError: Throwable) {
                Log.e(TAG, "Fatal failure applying fallback widget layout for id $appWidgetId", fallbackError)
            }
        }
    }
}
