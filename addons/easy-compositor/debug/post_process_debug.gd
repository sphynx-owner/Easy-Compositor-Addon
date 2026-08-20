@tool
extends EnhancedCompositorEffect
class_name DebugCompositorEffect

@export_storage var overlay_stage : ShaderStageResource = preload("res://addons/easy-compositor/debug/shader_stages/debug_overlay_shader_stage.tres")

## wether to display debug views for velocity and depth 
## buffers
@export var draw_debug : bool = false

## currently 0 - 1, flip between velocity buffers
## and depth buffers debug views
@export var debug_page : int = 0

var past_color : StringName = "past_color"

@export var freeze : bool = false

func _init():
	context = "MotionBlur"
	
	debug = true
	
	super()

func _render_callback_2(render_size : Vector2i, render_scene_buffers : RenderSceneBuffersRD, render_scene_data : RenderSceneDataRD):
	ensure_texture(past_color, render_scene_buffers)
	
	for texture in DEBUG_TEXTURE_NAMES:
		ensure_texture(texture, render_scene_buffers)
	
	rd.draw_command_begin_label("Debug", Color(1.0, 1.0, 1.0, 1.0))
	
	#if !Engine.is_editor_hint():
		#if Input.is_action_just_pressed("freeze"):
			#freeze = !freeze
		#
		#if Input.is_action_just_pressed("Z"):
			#draw_debug = !draw_debug
		#
		#if Input.is_action_just_pressed("C"):
			#debug_page = 1 if debug_page == 0 else 0
	
	var push_constant: PackedFloat32Array = [
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
	
	var byte_array: PackedByteArray = push_constant.to_byte_array()
	
	byte_array.append_array(int_push_constant.to_byte_array())
	
	var color_image: RID = render_scene_buffers.get_color_layer(0)
	var past_color_image: RID = render_scene_buffers.get_texture_slice(context, past_color, 0, 0, 1, 1)
	
	var x_groups: int = floori((render_size.x - 1) / 16 + 1)
	var y_groups: int = floori((render_size.y - 1) / 16 + 1)
	
	dispatch_stage(
		overlay_stage, 
		[
			get_image_uniform(past_color_image, 0),
			get_image_uniform(color_image, 1),
			get_sampler_uniform(color_image, 2)
		],
		byte_array,
		Vector3i(x_groups, y_groups, 1), 
		"Debug Overlay", 
		0
	)
	
	rd.draw_command_end_label()
