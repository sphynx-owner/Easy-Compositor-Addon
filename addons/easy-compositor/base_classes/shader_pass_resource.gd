@tool
extends Resource
class_name ShaderStageResource

@export var shader_file : RDShaderFile:
	set(value):
		if shader_file == value:
			return
		
		if shader_file and shader_file.changed.is_connected(emit_changed):
			shader_file.changed.disconnect(emit_changed)
		
		shader_file = value
		
		if shader_file and !shader_file.changed.is_connected(emit_changed):
			shader_file.changed.connect(emit_changed)
		
		emit_changed()


func _init(p_shader_file = null):
	shader_file = p_shader_file
