@tool
extends EditorPlugin

var export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["sewlens_android/sewlens_android.aar"])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"com.google.firebase:firebase-analytics:22.5.0",
			"com.google.firebase:firebase-crashlytics:19.4.4",
			"com.android.billingclient:billing:8.3.0",
			"com.google.android.play:review:2.0.2",
		])

	func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		# Written into src/release/AndroidManifest.xml on every Gradle export.
		# The plugin AAR manifest is not enough: Godot replaces the release manifest
		# and does not always merge queries from an .aar.
		# screen.portrait is implied as required by screenOrientation=portrait.
		# Declaring it here, inside the manifest Godot rewrites on every export,
		# keeps Play from treating portrait as required hardware. tools:replace
		# wins if another manifest still marks the feature required.
		return "<uses-permission android:name=\"com.android.vending.BILLING\"/>\n<uses-feature android:name=\"android.hardware.screen.portrait\" android:required=\"false\" tools:replace=\"android:required\"/>\n<queries>\n<package android:name=\"com.android.vending\"/>\n<intent>\n<action android:name=\"com.android.vending.billing.InAppBillingService.BIND\"/>\n</intent>\n</queries>"

	func _get_name() -> String:
		return "SewLensAndroid"
