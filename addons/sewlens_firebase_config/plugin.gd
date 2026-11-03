@tool
extends EditorPlugin

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = FirebasePlistExport.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class FirebasePlistExport extends EditorExportPlugin:
	const STAGED := "res://addons/sewlens_firebase_config/GoogleService-Info.plist"

	func _get_name() -> String:
		return "SewLensFirebasePlist"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformIOS

	func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		if not features.has("ios"):
			return
		var source := ProjectSettings.globalize_path("res://").path_join("ios/GoogleService-Info.plist")
		if FileAccess.file_exists(source):
			var src := FileAccess.open(source, FileAccess.READ)
			if src:
				var bytes := src.get_buffer(src.get_length())
				src.close()
				var dst := FileAccess.open(ProjectSettings.globalize_path(STAGED), FileAccess.WRITE)
				if dst:
					dst.store_buffer(bytes)
					dst.close()
		if not FileAccess.file_exists(STAGED):
			push_error("SewLens: GoogleService-Info.plist missing. Expected ios/GoogleService-Info.plist")
			return
		add_ios_bundle_file(STAGED)
