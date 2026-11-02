package com.heyzell.orpheus

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.view.KeyEvent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Native Android AppWidgetProvider for Orpheus (Compact Horizontal 4x1 widget - Tidal style).
 */
class OrpheusCompactWidgetProvider : AppWidgetProvider() {

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
            if (intent.action == OrpheusWidgetProvider.ACTION_TOGGLE_LIKE) {
                OrpheusWidgetProvider.handleToggleLike(context)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Unhandled exception in onReceive", t)
        }
    }

    companion object {
        const val TAG = "OrpheusCompactWidgetProvider"

        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            try {
                val views = RemoteViews(context.packageName, R.layout.orpheus_widget_compact_layout)

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

                views.setTextViewText(R.id.widget_compact_track_title, title)
                views.setTextViewText(R.id.widget_compact_track_artist, artist)

                // Render cover art with rounded corners (12dp)
                val coverBitmap = OrpheusWidgetProvider.loadOptimizedBitmap(
                    filePath = coverPath,
                    reqWidth = 160,
                    reqHeight = 160,
                    cornerRadiusDp = 12f,
                    context = context
                )
                if (coverBitmap != null) {
                    views.setImageViewBitmap(R.id.widget_compact_cover_image, coverBitmap)
                } else {
                    views.setImageViewResource(R.id.widget_compact_cover_image, R.drawable.widget_immersive_background)
                }

                views.setImageViewResource(
                    R.id.widget_compact_btn_play_pause,
                    if (isPlaying) R.drawable.ic_pause else R.drawable.ic_play
                )

                views.setImageViewResource(
                    R.id.widget_compact_btn_like,
                    if (isLiked) R.drawable.ic_heart_filled else R.drawable.ic_heart_outline
                )

                // Wire playback controls
                val prevIntent = OrpheusWidgetProvider.buildMediaPendingIntent(
                    context, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 201
                )
                if (prevIntent != null) views.setOnClickPendingIntent(R.id.widget_compact_btn_prev, prevIntent)

                val playPauseIntent = OrpheusWidgetProvider.buildMediaPendingIntent(
                    context, PlaybackStateCompat.ACTION_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 202
                )
                if (playPauseIntent != null) views.setOnClickPendingIntent(R.id.widget_compact_btn_play_pause, playPauseIntent)

                val nextIntent = OrpheusWidgetProvider.buildMediaPendingIntent(
                    context, PlaybackStateCompat.ACTION_SKIP_TO_NEXT, KeyEvent.KEYCODE_MEDIA_NEXT, 203
                )
                if (nextIntent != null) views.setOnClickPendingIntent(R.id.widget_compact_btn_next, nextIntent)

                // Wire Like button
                val likeIntent = Intent(context, OrpheusCompactWidgetProvider::class.java).apply {
                    action = OrpheusWidgetProvider.ACTION_TOGGLE_LIKE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                }
                val likePendingIntent = PendingIntent.getBroadcast(
                    context,
                    appWidgetId + 5000,
                    likeIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_compact_btn_like, likePendingIntent)

                // Wire launch intent on metadata and cover
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launchIntent != null) {
                    launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    val appPendingIntent = PendingIntent.getActivity(
                        context,
                        appWidgetId + 4000,
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    views.setOnClickPendingIntent(R.id.widget_compact_cover_image, appPendingIntent)
                    views.setOnClickPendingIntent(R.id.widget_compact_metadata_container, appPendingIntent)
                }

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (t: Throwable) {
                Log.e(TAG, "Critical failure during updateAppWidget for id $appWidgetId: ${t.message}", t)
                applyFallback(context, appWidgetManager, appWidgetId)
            }
        }

        fun applyFallback(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            try {
                val views = RemoteViews(context.packageName, R.layout.orpheus_widget_compact_layout)
                views.setTextViewText(R.id.widget_compact_track_title, "Orpheus")
                views.setTextViewText(R.id.widget_compact_track_artist, "Escucha algo grandioso")
                views.setImageViewResource(R.id.widget_compact_cover_image, R.drawable.widget_immersive_background)
                views.setImageViewResource(R.id.widget_compact_btn_play_pause, R.drawable.ic_play)
                views.setImageViewResource(R.id.widget_compact_btn_like, R.drawable.ic_heart_outline)
                views.setImageViewResource(R.id.widget_compact_btn_prev, R.drawable.ic_skip_previous)
                views.setImageViewResource(R.id.widget_compact_btn_next, R.drawable.ic_skip_next)

                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launchIntent != null) {
                    launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    val appPendingIntent = PendingIntent.getActivity(
                        context,
                        appWidgetId,
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    views.setOnClickPendingIntent(R.id.widget_compact_container, appPendingIntent)
                }

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (fallbackError: Throwable) {
                Log.e(TAG, "Fatal failure applying fallback widget layout for id $appWidgetId", fallbackError)
            }
        }
    }
}
