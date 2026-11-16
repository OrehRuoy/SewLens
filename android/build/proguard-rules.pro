# SewLens release shrinking. R8 runs because the release buildType sets minifyEnabled.
# Godot, its plugins, Play Billing, and Firebase are loaded by name from the
# manifest, JNI, or @UsedByGodot reflection, so their names must survive.

-keepattributes RuntimeVisibleAnnotations,AnnotationDefault,Signature,InnerClasses,EnclosingMethod

# Godot engine and the plugin interface. Native code looks these up by name.
-keep class org.godotengine.** { *; }
-keep interface org.godotengine.** { *; }
-keep class com.godot.game.GodotApp { *; }

# Every Godot Android plugin in this project, including methods Godot calls by name.
-keep class * extends org.godotengine.godot.plugin.GodotPlugin { *; }
-keepclassmembers class * extends org.godotengine.godot.plugin.GodotPlugin {
    public <init>(org.godotengine.godot.Godot);
    @org.godotengine.godot.plugin.UsedByGodot <methods>;
    public java.util.List getPluginMethods();
    public java.util.Set getPluginSignals();
    public java.lang.String getPluginName();
}
# Inner classes too. A keep on the outer class left SewLensBilling.Listener renamed.
-keep class app.sewlens.** { *; }

# Play Billing and the in-app review sheet. BillingClient is wired by reflection.
-keep class com.android.billingclient.** { *; }
-keep interface com.android.billingclient.** { *; }
-keep class com.google.android.play.core.** { *; }

# Firebase Analytics and Crashlytics, called from SewLensAnalytics.
-keep class com.google.firebase.analytics.** { *; }
-keep class com.google.firebase.crashlytics.** { *; }
-keep class com.google.firebase.installations.** { *; }

# JNI method names, and classes Android loads by the name stored in the manifest.
-keepclasseswithmembernames class * {
    native <methods>;
}
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}
