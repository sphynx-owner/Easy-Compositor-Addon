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

const DEFAULT_GROUP_SIZE: Vector3 = Vector3(16, 16, 1)

const DEFAULT_TEXTURE_UNIFORM_SET: int = 0

const DEBUG_CONTEXT: String = "Debug"

const DEBUG_SYMBOL: String = "// DEBUG_UNIFORMS"

const DEBUG_UNIFORM_SET: int = 1

const DEBUG_BINDING_START_OFFSET: int = 10

const DEBUG_TEXTURE_COUNT: int = 12

static var DEBUG_SNIPPET: String

static var DEBUG_TEXTURE_NAMES: Array[StringName]

## Enabling this would include the DEBUG pre-processor in 
## the compute shader before compiling and creating the pipeline,
## As well as adding debug image uniforms and binding them automatically.
@export var debug: bool = false:
	set(value):
		debug = value
		
		RenderingServer.call_on_render_thread(_update_debug_enabled)

# WARNING @sphynx-owner: the purpose of the rendering device instance system is to
# avoid creating redundant samplers for the same rendreing device. This system is
# has limitations, and would break if the same compositor effect is used across two
# scenes that use different rendering devices.
# NOTE @sphynx-owner: the reason I created the rendering device instance system is to
# avoid redundant creation of things like samplers, which do not need to be recreated
# more than once per rendering device. The real issue that drove this was that
# the editor holds on to resources even after they are dereferenced from code. 
# This caused samplers to clog the heap as they were created anew for every 
# compositor effect when doing stuff with them in the editor repeatedly.
var rd_instance: RenderingDeviceInstance = RenderingDeviceInstance.get_instance()

var context: StringName = DEFAULT_CONTEXT

var _all_shader_stages : Dictionary[RDShaderFile, CompiledShaderStage]

var _current_render_scene_buffers: RenderSceneBuffersRD

var _current_render_scene_data: RenderSceneDataRD

var all_debug_images: Array[RID]

#region Virtual Methods

static func _static_init() -> void:
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
	#RenderingServer.viewport_get_render_target(EditorInterface.get_editor_viewport_3d().get_viewport_rid())
	
	if !rd_instance.is_valid():
		return
	
	_current_render_scene_buffers = p_render_data.get_render_scene_buffers()
	_current_render_scene_data = p_render_data.get_render_scene_data()
	
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


func _enhanced_render_callback(render_size: Vector2i):
	pass

#endregion

#region Public Methods

func ensure_texture(
	texture_name: StringName,
	texture_format: RenderingDevice.DataFormat = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
	render_size: Vector2i = _current_render_scene_buffers.get_internal_size(),
	usage_bits: int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
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
			true,
			# HACK @sphynx-owner: having it at false without knowing what this means.
			# My worry is that this means textures are discarded as soon as possible, or
			# maybe discardable manually, or something. I don't know yet.
			# TODO @sphynx-owner: learn.
			false
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
	var uniform := RDUniform.new()
	
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(image)
	
	return uniform


func get_sampler_uniform(image: RID, binding: int, linear: bool = true) -> RDUniform:
	var uniform := RDUniform.new()
	
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = binding
	uniform.add_id(rd_instance.linear_sampler if linear else rd_instance.nearest_sampler)
	uniform.add_id(image)
	
	return uniform


func get_buffer_uniform(buffer: RID, binding: int) -> RDUniform:
	var uniform := RDUniform.new()
	
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	
	return uniform


func get_push_constants(
	floats: PackedFloat32Array = [], 
	ints: PackedInt32Array = [], 
	force_four_minimum_entries := false
) -> PackedByteArray:
	var ret: PackedByteArray
	
	if floats.size() > 0 or force_four_minimum_entries:
		@warning_ignore("integer_division")
		floats.resize((((floats.size() - 1) / 4 + 1) * 4))
	
	ret.append_array(floats.to_byte_array())
	
	if ints.size() > 0 or force_four_minimum_entries:
		@warning_ignore("integer_division")
		ints.resize((((ints.size() - 1) / 4 + 1) * 4))
	
	ret.append_array(ints.to_byte_array())
	
	return ret


func get_groups_count(render_size: Vector3i, group_size: Vector3i) -> Vector3i:
	return Vector3i(
		divide_by_tile_size(render_size.x, group_size.x),
		divide_by_tile_size(render_size.y, group_size.y),
		divide_by_tile_size(render_size.z, group_size.z)
	)


func divide_vector2i_by_tile_size(size: Vector2i, tile_size: Vector2i) -> Vector2i:
	return Vector2i(
		divide_by_tile_size(size.x, tile_size.x),
		divide_by_tile_size(size.y, tile_size.y)
	)


func divide_by_tile_size(size: int, tile_size: int) -> int:
	return (size - 1) / tile_size + 1


func dispatch_stage(
	stage: RDShaderFile,
	uniforms: Array[RDUniform],
	push_constants: PackedByteArray,
	dispatch_size: Vector3i,
	label: String = "DefaultLabel",
	color: Color = Color(1, 1, 1, 1)
) -> bool:
	if !_all_shader_stages.has(stage):
		_all_shader_stages[stage] = CompiledShaderStage.new(rd_instance.rd, stage, debug)
	
	var compiled_shader_stage: CompiledShaderStage = _all_shader_stages[stage]
	
	if !compiled_shader_stage.is_compiled():
		push_error("cannot dispatch invalid shader stage")
		return false
	
	rd_instance.rd.draw_command_begin_label(label + " " + str(PLACEHOLDER_VIEW_INDEX), color)
	
	var tex_uniform_set: RID = UniformSetCacheRD.get_cache(compiled_shader_stage.shader, DEFAULT_TEXTURE_UNIFORM_SET, uniforms)
	
	var compute_list = rd_instance.rd.compute_list_begin()
	
	rd_instance.rd.compute_list_bind_compute_pipeline(compute_list, compiled_shader_stage.pipeline)
	
	rd_instance.rd.compute_list_bind_uniform_set(compute_list, tex_uniform_set, DEFAULT_TEXTURE_UNIFORM_SET)
	
	if compiled_shader_stage.needs_debug():
		var debug_uniforms: Array[RDUniform]
		
		for i in DEBUG_TEXTURE_COUNT:
			debug_uniforms.append(get_image_uniform(all_debug_images[i], DEBUG_BINDING_START_OFFSET + i))
		
		var debug_uniform_set: RID = UniformSetCacheRD.get_cache(compiled_shader_stage.shader, DEBUG_UNIFORM_SET, debug_uniforms)
		
		rd_instance.rd.compute_list_bind_uniform_set(compute_list, debug_uniform_set, DEBUG_UNIFORM_SET)
	
	if !push_constants.is_empty():
		rd_instance.rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	
	rd_instance.rd.compute_list_dispatch(compute_list, dispatch_size.x, dispatch_size.y, dispatch_size.z)
	
	rd_instance.rd.compute_list_end()
	
	rd_instance.rd.draw_command_end_label()
	
	return true

#endregion

#region Private Methods

func _update_debug_enabled() -> void:
	for compiled_shader_stage: CompiledShaderStage in _all_shader_stages.values():
		compiled_shader_stage.debug = debug


func _recompile_all_shaders() -> void:
	for compiled_shader_stage: CompiledShaderStage in _all_shader_stages.values():
		compiled_shader_stage.try_compile()

#endregion

class RenderingDeviceInstance:
	static var _instances_by_rd: Dictionary[RenderingDevice, WeakRef]
	
	var rd: RenderingDevice
	
	var linear_sampler: RID
	
	var nearest_sampler: RID
	
	
	static func get_instance() -> RenderingDeviceInstance:
		var rd: RenderingDevice = RenderingServer.get_rendering_device()
		
		if !rd:
			push_error("cannot find rendering device, returning null instance")
			return null
		
		if _instances_by_rd.has(rd):
			var instance: RenderingDeviceInstance = _instances_by_rd[rd].get_ref()
			
			if !instance:
				push_error("cached rendering device instance is null, creating new one")
				return RenderingDeviceInstance.new()
			
			return instance
		
		return RenderingDeviceInstance.new()
	
	
	static func _instance_created(rd: RenderingDevice, instance: RenderingDeviceInstance) -> void:
		_instances_by_rd[rd] = weakref(instance)
	
	
	static func _instance_predeleted(rd: RenderingDevice) -> void:
		_instances_by_rd.erase(rd)
	
	
	func _init():
		rd = RenderingServer.get_rendering_device()
		
		if !rd:
			push_error("could not find rendering device, instance is invalid")
			return
		
		var sampler_state := RDSamplerState.new()
		
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		
		linear_sampler = rd.sampler_create(sampler_state)
		
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		
		nearest_sampler = rd.sampler_create(sampler_state)
		
		_instance_created(rd, self)
	
	
	func _notification(what: int):
		if what == NOTIFICATION_PREDELETE:
			if !rd:
				push_error("rendering device not available for instance predelete")
				return
			
			_instance_predeleted(rd)
			
			if linear_sampler.is_valid():
				rd.free_rid(linear_sampler)
			
			if nearest_sampler.is_valid():
				rd.free_rid(nearest_sampler)
	
	
	func is_valid() -> bool:
		return !!rd


class CompiledShaderStage:
	var rd: RenderingDevice
	
	var shader_stage: RDShaderFile:
		set(value):
			if shader_stage == value:
				return
			
			if shader_stage and shader_stage.changed.is_connected(try_compile):
				shader_stage.changed.disconnect(try_compile)
			
			shader_stage = value
			
			if shader_stage and !shader_stage.changed.is_connected(try_compile):
				shader_stage.changed.connect(try_compile)
			
			if !_init_gate:
				try_compile()
	
	var debug: bool = false:
		set(value):
			if debug == value:
				return
			
			debug = value
			
			if !_init_gate:
				try_compile()
	
	var _init_gate: bool = false
	
	var _needs_debug: bool = false
	var _is_compiled: bool = false
	
	var shader: RID
	var pipeline: RID
	
	
	func _init(p_rd: RenderingDevice, p_shader_stage: RDShaderFile, p_debug: bool = false) -> void:
		_init_gate = true
		
		rd = p_rd
		
		shader_stage = p_shader_stage
		
		debug = p_debug
		
		_init_gate = false
		
		try_compile()
	
	
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			if !rd:
				return
			
			# NOTE @sphynx-owner: the pipeline would automatically be freed.
			# trying to free it, even with an is_valid check after this, would
			# result in an error: https://github.com/godotengine/godot/issues/103073
			if shader.is_valid():
				rd.free_rid(shader)
			
			_is_compiled = false
			shader = RID()
			pipeline = RID()
	
	
	func is_compiled() -> bool:
		return _is_compiled
	
	
	func needs_debug() -> bool:
		return _needs_debug
	
	
	func try_compile() -> bool:
		_free_rids()
		
		var shader_spirv: RDShaderSPIRV
		
		_needs_debug = false
		
		if debug:
			if !shader_stage.resource_path:
				push_error("shader file does not have a resource path, cannot generate debug version")
				return false
			
			var file: FileAccess = FileAccess.open(shader_stage.resource_path, FileAccess.READ)
			
			var file_text: String = file.get_as_text()
			
			file_text = file_text.replace("#[compute]", "")
			
			if file_text.contains(EnhancedCompositorEffect.DEBUG_SYMBOL):
				file_text = file_text.replace(EnhancedCompositorEffect.DEBUG_SYMBOL, EnhancedCompositorEffect.DEBUG_SNIPPET)
				
				_needs_debug = true
			
			var shader_source: RDShaderSource = RDShaderSource.new()
			
			shader_source.set_stage_source(RenderingDevice.SHADER_STAGE_COMPUTE, file_text)
			
			shader_spirv = rd.shader_compile_spirv_from_source(shader_source, false)
			
		else:
			shader_spirv = shader_stage.get_spirv()
		
		var error: String = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		
		if error:
			push_error("shader compilation errors in %s: \n" % [shader_stage.resource_path.get_file()], error)
			return false
		
		shader = rd.shader_create_from_spirv(shader_spirv)
		pipeline = rd.compute_pipeline_create(shader)
		
		_is_compiled = true
		
		return true
	
	
	func _free_rids() -> void:
		if !rd:
			return
		
		# NOTE @sphynx-owner: the pipeline would automatically be freed.
		# trying to free it, even with an is_valid check after this, would
		# result in an error: https://github.com/godotengine/godot/issues/103073
		if shader.is_valid():
			rd.free_rid(shader)
		
		_is_compiled = false
		shader = RID()
		pipeline = RID()
