# AudioService keep rules
-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.** { *; }
-keep class android.support.v4.media.** { *; }
-keep class androidx.core.app.NotificationCompat** { *; }

# Keep R drawables from obfuscation/removal
-keepclassmembers class **.R$* {
    public static <fields>;
}
