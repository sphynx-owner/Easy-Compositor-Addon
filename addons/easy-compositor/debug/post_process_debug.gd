@tool
class_name DebugCompositorEffect
extends EnhancedCompositorEffect

@export_storage var overlay_stage : RDShaderFile = preload("res://addons/easy-compositor/debug/shader_stages/debug_overlay.glsl")

## wether to display debug views for velocity and depth 
## buffers
@export var draw_debug : bool = false

## currently 0 - 1, flip between velocity buffers
## and depth buffers debug views
@export var debug_page : int = 0

var past_color : StringName = "past_color"

@export var freeze : bool = false

func _init():
	context = DEBUG_CONTEXT
	
	debug = true


func _validate_property(property: Dictionary) -> void:
	if property.name == "debug":
		property.usage &= ~PROPERTY_USAGE_EDITOR


func _enhanced_render_callback(render_size: Vector2i):
	rd_instance.rd.draw_command_begin_label("Debug", Color(1.0, 1.0, 1.0, 1.0))
	
	var float_push_constants: PackedFloat32Array = [
		0,
		0,
		0, 
		0, 
	]
	
	var int_push_constant : PackedInt32Array = [
		freeze,
		draw_debug,
		debug_page,
		0
	]
	
	var color_image: RID = get_color_texture()
	
	ensure_texture(past_color)
	
	var past_color_image: RID = get_texture(past_color)
	
	dispatch_stage(
		overlay_stage, 
		[
			get_image_uniform(past_color_image, 0),
			get_image_uniform(color_image, 1),
			get_sampler_uniform(color_image, 2)
		],
		get_push_constants(float_push_constants, int_push_constant),
		get_groups_count(Vector3i(render_size.x, render_size.y, 1), DEFAULT_GROUP_SIZE), 
		"Debug Overlay"
	)
	
	rd_instance.rd.draw_command_end_label()
