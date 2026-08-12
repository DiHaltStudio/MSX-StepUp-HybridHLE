@tool
extends SceneTree


func _initialize() -> void:
	var settings := EditorSettings.get_singleton()
	if settings == null:
		push_error("Editor settings are unavailable")
		quit(1)
		return
	var android_sdk := OS.get_environment("ANDROID_HOME")
	var java_home := OS.get_environment("JAVA_HOME")
	if android_sdk.is_empty() or java_home.is_empty():
		push_error("ANDROID_HOME and JAVA_HOME must be set")
		quit(1)
		return
	settings.set_setting("export/android/android_sdk_path", android_sdk)
	settings.set_setting("export/android/java_sdk_path", java_home)
	settings.save()
	quit()
