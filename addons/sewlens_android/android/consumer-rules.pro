# Merged into the app when this plugin AAR is rebuilt. The app also keeps these
# in android/build/proguard-rules.pro, which covers the AAR already in the repo.
-keepattributes RuntimeVisibleAnnotations,AnnotationDefault,Signature,InnerClasses,EnclosingMethod
-keep class app.sewlens.** { *; }
-keepclassmembers class * extends org.godotengine.godot.plugin.GodotPlugin {
    public <init>(org.godotengine.godot.Godot);
    @org.godotengine.godot.plugin.UsedByGodot <methods>;
    public java.util.List getPluginMethods();
    public java.util.Set getPluginSignals();
    public java.lang.String getPluginName();
}
