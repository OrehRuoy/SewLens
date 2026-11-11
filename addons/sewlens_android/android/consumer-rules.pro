# Godot calls these by reflection. R8 must keep the names and the annotation.
-keepattributes RuntimeVisibleAnnotations,AnnotationDefault
-keepclassmembers class * extends org.godotengine.godot.plugin.GodotPlugin {
    @org.godotengine.godot.plugin.UsedByGodot <methods>;
    public java.util.List getPluginMethods();
}
