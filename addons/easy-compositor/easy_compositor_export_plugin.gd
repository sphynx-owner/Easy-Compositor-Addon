@tool
extends EditorExportPlugin


func _get_name() -> String:
	return "Easy Compositor Export Plugin"


func _export_file(path: String, type: String, features: PackedStringArray) -> void:
	if path.ends_with(".glsl"):
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		
		if !file:
			return
		
		add_file(path.replace(".glsl", ".glsl.txt"), file.get_as_text().to_utf8_buffer(), false)
