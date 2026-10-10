@tool
@abstract
class_name EnhancedCompositorEffect
extends CompositorEffect
## This script contains and handles a lot of the boilerplate required for setting up a functioning compositor effcet
## It also establishes a debugging pattern that compute shaders can hook onto with pre processors
## Using this while not the most efficient is great for setting quick effects to experiment with.

const DEFAULT_CONTEXT: String = "PostProcess"

# TODO @sphynx-owner: figure out if I should add support for multiple views. It's not as simple
# as calling multiple render callback virtuals for each view, since that could cause unnecessary
# duplicate logic per frame. There would need to be a better structure for the out-of-per-view
# dispatches, and then some way to dispatch for each view. Perhaps accumulate dispatches and then
# multiply them for each view... idk.
# ---------------------------------------
const PLACEHOLDER_VIEW_INDEX: int = 0

const PLACEHOLDER_VIEW_COUNT: int = 1
# ---------------------------------------

const VERSION_SYMBOL: String = "// ENGINE_VERSION"

const DEFAULT_GROUP_SIZE: Vector3 = Vector3(16, 16, 1)

const DEFAULT_TEXTURE_UNIFORM_SET: int = 0

const DEBUG_CONTEXT: String = "Debug"

const DEBUG_SYMBOL: String = "// DEBUG_UNIFORMS"

const DEBUG_UNIFORM_SET: int = 1

const DEBUG_BINDING_START_OFFSET: int = 10

const DEBUG_TEXTURE_COUNT: int = 12

static var VERSION_SNIPPET: String

static var DEBUG_SNIPPET: String

static var DEBUG_TEXTURE_NAMES: Array[StringName]

## Enabling this would include the DEBUG pre-processor in 
## the compute shader before compiling and creating the pipeline,
## As well as adding debug image uniforms and binding them automatically.
@export var debug: bool = false:
	set(value):
		debug = value
		
		RenderingServer.call_on_render_thread(_update_debug_enabled)

var context: StringName = DEFAULT_CONTEXT

var _all_shader_stages: Dictionary[RDShaderFile, CompiledShaderStage]

var _current_render_scene_buffers: RenderSceneBuffersRD

var _current_render_scene_data: RenderSceneDataRD

var _current_rd_instance: RenderingDeviceInstance

var all_debug_images: Array[RID]

#region Virtual Methods

static func _static_init() -> void:
	var version_info: Dictionary = Engine.get_version_info()
	
	VERSION_SNIPPET = "#define ENGINE_VERSION_%s_%s" % [version_info.major, version_info.minor]
	
	var new_debug_snippet: String = "#define DEBUG\n"
	
	var new_debug_texture_names: Array[StringName]
	
	for i in DEBUG_TEXTURE_COUNT:
		new_debug_snippet += "layout(rgba16f, set = %s, binding = %s) uniform image2D debug_%s_image;\n" % [
			DEBUG_UNIFORM_SET,
			DEBUG_BINDING_START_OFFSET + i,
			i + 1
		]
		
		new_debug_texture_names.push_back(StringName("debug_%s" % [i + 1]))
	
	DEBUG_SNIPPET = new_debug_snippet
	
	DEBUG_TEXTURE_NAMES = new_debug_texture_names


func _render_callback(p_effect_callback_type: int, p_render_data: RenderData):
	_current_render_scene_buffers = p_render_data.get_render_scene_buffers()
	_current_render_scene_data = p_render_data.get_render_scene_data()
	_current_rd_instance = RenderingDeviceInstance.get_instance()
	
	if !_current_rd_instance.is_valid():
		return
	
	if !_current_render_scene_buffers or !_current_render_scene_data:
		return
	
	var render_size: Vector2i = _current_render_scene_buffers.get_internal_size()
	
	if render_size.x == 0 or render_size.y == 0:
		return
	
	if debug:
		# HACK @sphynx-owner: overriding the context momentarily for the generation of all
		# debug textures. I don't know for certain if this is necessary but it feels right.
		var temp_context: String = context
		context = DEBUG_CONTEXT
		
		for debug_texture in DEBUG_TEXTURE_NAMES:
			ensure_texture(debug_texture)
			
			all_debug_images.append(get_texture(debug_texture))
		
		context = temp_context
	
	_enhanced_render_callback(render_size)
	
	all_debug_images.clear()
	
	# We set all these to null, especially the _current_rd_instance so that it would correctly get dereferenced and freed
	# if possible.
	_current_render_scene_buffers = null
	_current_render_scene_data = null
	_current_rd_instance = null


func _enhanced_render_callback(render_size: Vector2i) -> void:
	pass

#endregion

#region Public Methods

func ensure_texture(
	texture_name: StringName,
	texture_format: RenderingDevice.DataFormat = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
	render_size: Vector2i = _current_render_scene_buffers.get_internal_size(),
	usage_bits: int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT,
	unique = false,
	discardable = true
) -> bool:
	assert(_current_render_scene_buffers, "current render scene buffers must be set")
	
	if _current_render_scene_buffers.has_texture(context, texture_name):
		var tf: RDTextureFormat = _current_render_scene_buffers.get_texture_format(context, texture_name)
		
		if tf.width != render_size.x or tf.height != render_size.y:
			_current_render_scene_buffers.clear_context(context)
	
	if !_current_render_scene_buffers.has_texture(context, texture_name):
		_current_render_scene_buffers.create_texture(
			context,
			texture_name,
			texture_format,
			usage_bits,
			RenderingDevice.TEXTURE_SAMPLES_1,
			render_size,
			PLACEHOLDER_VIEW_COUNT,
			1,
			unique,
			discardable
		)
		
		return true
	
	return false


func get_texture(texture_name: StringName) -> RID:
	assert(_current_render_scene_buffers, "current render scene buffers must be set")
	
	return _current_render_scene_buffers.get_texture_slice(context, texture_name, PLACEHOLDER_VIEW_INDEX, 0, 1, 1)


func get_depth_texture() -> RID:
	assert(_current_render_scene_buffers, "current render scene buffers must be set")
	
	return _current_render_scene_buffers.get_depth_layer(PLACEHOLDER_VIEW_INDEX)


func get_color_texture() -> RID:
	assert(_current_render_scene_buffers, "current render scene buffers must be set")
	
	return _current_render_scene_buffers.get_color_layer(PLACEHOLDER_VIEW_INDEX)


func get_velocity_texture() -> RID:
	assert(_current_render_scene_buffers, "current render scene buffers must be set")
	
	return _current_render_scene_buffers.get_velocity_layer(PLACEHOLDER_VIEW_INDEX)


func get_scene_uniform_data_buffer() -> RID:
	assert(_current_render_scene_data, "current render scene buffers must be set")
	
	return _current_render_scene_data.get_uniform_buffer()


func get_image_uniform(image: RID, binding: int) -> RDUniform:
	return EasyRenderingUtils.get_image_uniform(image, binding)


func get_sampler_uniform(image: RID, binding: int, linear: bool = true) -> RDUniform:
	return EasyRenderingUtils.get_sampler_uniform(_current_rd_instance, image, binding, linear)


func get_buffer_uniform(buffer: RID, binding: int) -> RDUniform:
	return EasyRenderingUtils.get_buffer_uniform(buffer, binding)


func begin_compute(
	label: String = "DefaultLabel",
	color: Color = Color(1, 1, 1, 1)
) -> void:
	assert(_current_rd_instance, "No current rendering device instance available, did you call this outside the render callback?")
	
	EasyRenderingUtils.begin_compute(_current_rd_instance, label, color)


func dispatch_stage(
	stage: RDShaderFile,
	uniforms: Array[RDUniform],
	push_constants: PackedByteArray,
	dispatch_size: Vector3i
) -> bool:
	if !_all_shader_stages.has(stage):
		_all_shader_stages[stage] = CompiledShaderStage.new(_current_rd_instance, stage, debug)
	
	var compiled_shader_stage: CompiledShaderStage = _all_shader_stages[stage]
	
	if !compiled_shader_stage.is_compiled():
		push_error("cannot dispatch invalid shader stage")
		return false
	
	assert(_current_rd_instance, "No current rendering device instance available, did you call this outside the render callback?")
	
	var uniform_sets: Array[Array] = [uniforms]
	
	if compiled_shader_stage.needs_debug():
		var debug_uniforms: Array[RDUniform]
		
		for i in DEBUG_TEXTURE_COUNT:
			debug_uniforms.append(get_image_uniform(all_debug_images[i], DEBUG_BINDING_START_OFFSET + i))
		
		uniform_sets.append(debug_uniforms)
	
	return EasyRenderingUtils.dispatch_stage(
		_current_rd_instance,
		compiled_shader_stage,
		uniform_sets,
		push_constants,
		dispatch_size,
		true
	)


func add_barrier() -> void:
	assert(_current_rd_instance, "No current rendering device instance available, did you call this outside the render callback?")
	
	EasyRenderingUtils.add_barrier(_current_rd_instance)


func end_compute() -> void:
	assert(_current_rd_instance, "No current rendering device instance available, did you call this outside the render callback?")
	
	EasyRenderingUtils.end_compute(_current_rd_instance)

#endregion

#region Private Methods

func _update_debug_enabled() -> void:
	for compiled_shader_stage: CompiledShaderStage in _all_shader_stages.values():
		compiled_shader_stage.debug = debug


func _recompile_all_shaders() -> void:
	for compiled_shader_stage: CompiledShaderStage in _all_shader_stages.values():
		compiled_shader_stage.try_compile()

#endregion
