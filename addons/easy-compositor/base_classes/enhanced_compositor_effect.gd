@tool
@abstract
class_name EnhancedCompositorEffect
extends CompositorEffect
## This script contains and handles a lot of the boilerplate required for setting up a functioning compositor effcet
## It also establishes a debugging pattern that compute shaders can hook onto with pre processors
## Using this while not the most efficient is great for setting quick effects to experiment with.

const DEFAULT_TEXTURE_UNIFORM_SET: int = 0

const DEBUG_SYMBOL: String = "// DEBUG_UNIFORMS"

const DEBUG_UNIFORM_SET: int = 1

const DEBUG_BINDING_START_OFFSET: int = 10

const DEBUG_TEXTURE_COUNT: int = 8

static var DEBUG_SNIPPET: String

static var DEBUG_TEXTURE_NAMES: Array[StringName]

## Enabling this would include the DEBUG pre-processor in 
## the compute shader before compiling and creating the pipeline,
## As well as adding debug image uniforms and binding them automatically.
@export var debug: bool = false:
	set(value):
		debug = value
		
		RenderingServer.call_on_render_thread(_update_debug_enabled)

var rd: RenderingDevice

var linear_sampler: RID

var nearest_sampler: RID

var context: StringName = "PostProcess"

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


func _init():
	RenderingServer.call_on_render_thread(_initialize_compute)


func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		if !rd:
			return
		
		if linear_sampler.is_valid():
			rd.free_rid(linear_sampler)
		
		if nearest_sampler.is_valid():
			rd.free_rid(nearest_sampler)


func _render_callback(p_effect_callback_type: int, p_render_data: RenderData):
	if !rd:
		return
	
	_current_render_scene_buffers = p_render_data.get_render_scene_buffers()
	_current_render_scene_data = p_render_data.get_render_scene_data()
	
	if !_current_render_scene_buffers or !_current_render_scene_data:
		return
	
	var render_size: Vector2i = _current_render_scene_data.get_internal_size()
	
	if render_size.x == 0 or render_size.y == 0:
		return
	
	if debug:
		for debug_texture in DEBUG_TEXTURE_NAMES:
			ensure_texture(debug_texture, _current_render_scene_buffers)
		
		for debug_texture in DEBUG_TEXTURE_NAMES:
			all_debug_images.append(get_texture(debug_texture, _current_render_scene_buffers))
	
	_enhanced_render_callback(render_size, _current_render_scene_buffers, _current_render_scene_data)
	
	all_debug_images.clear()


func _enhanced_render_callback(
	render_size: Vector2i,
	render_scene_buffers: RenderSceneBuffersRD,
	render_scene_data: RenderSceneDataRD
):
	pass

#endregion

#region Public Methods

func ensure_texture(
	texture_name: StringName,
	render_scene_buffers: RenderSceneBuffersRD,
	texture_format: RenderingDevice.DataFormat = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
	render_size_multiplier: Vector2 = Vector2(1, 1)
) -> bool:
	var render_size: Vector2i = Vector2(render_scene_buffers.get_internal_size()) * render_size_multiplier
	
	if render_scene_buffers.has_texture(context, texture_name):
		var tf: RDTextureFormat = render_scene_buffers.get_texture_format(context, texture_name)
		
		if tf.width != render_size.x or tf.height != render_size.y:
			render_scene_buffers.clear_context(context)
	
	if !render_scene_buffers.has_texture(context, texture_name):
		var usage_bits: int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		
		render_scene_buffers.create_texture(
			context,
			texture_name,
			texture_format,
			usage_bits,
			RenderingDevice.TEXTURE_SAMPLES_1,
			render_size,
			1,
			1,
			true,
			false
		)
		
		return true
	
	return false


func get_texture(texture_name: StringName, render_scene_buffers: RenderSceneBuffersRD) -> RID:
	return render_scene_buffers.get_texture_slice(context, texture_name, 0, 0, 1, 1)


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
	uniform.add_id(linear_sampler if linear else nearest_sampler)
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
		floori((render_size.x - 1) / group_size.x + 1),
		floori((render_size.y - 1) / group_size.y + 1),
		floori((render_size.z - 1) / group_size.z + 1)
	)


func dispatch_stage(
	stage: RDShaderFile,
	uniforms: Array[RDUniform],
	push_constants: PackedByteArray,
	dispatch_size: Vector3i,
	label: String = "DefaultLabel",
	view: int = 0,
	color: Color = Color(1, 1, 1, 1)
) -> bool:
	if !_all_shader_stages.has(stage):
		_all_shader_stages[stage] = CompiledShaderStage.new(rd, stage, debug)
	
	var compiled_shader_stage: CompiledShaderStage = _all_shader_stages[stage]
	
	if !compiled_shader_stage.is_compiled():
		push_error("cannot dispatch invalid shader stage")
		return false
	
	rd.draw_command_begin_label(label + " " + str(view), color)
	
	var tex_uniform_set: RID = UniformSetCacheRD.get_cache(compiled_shader_stage.shader, DEFAULT_TEXTURE_UNIFORM_SET, uniforms)
	
	var compute_list = rd.compute_list_begin()
	
	rd.compute_list_bind_compute_pipeline(compute_list, compiled_shader_stage.pipeline)
	
	rd.compute_list_bind_uniform_set(compute_list, tex_uniform_set, DEFAULT_TEXTURE_UNIFORM_SET)
	
	if compiled_shader_stage.needs_debug():
		var debug_uniforms: Array[RDUniform]
		
		for i in DEBUG_TEXTURE_COUNT:
			debug_uniforms.append(get_image_uniform(all_debug_images[i], DEBUG_BINDING_START_OFFSET + i))
		
		var debug_uniform_set: RID = UniformSetCacheRD.get_cache(compiled_shader_stage.shader, DEBUG_UNIFORM_SET, debug_uniforms)
		
		rd.compute_list_bind_uniform_set(compute_list, debug_uniform_set, DEBUG_UNIFORM_SET)
	
	if !push_constants.is_empty():
		rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	
	rd.compute_list_dispatch(compute_list, dispatch_size.x, dispatch_size.y, dispatch_size.z)
	
	rd.compute_list_end()
	
	rd.draw_command_end_label()
	
	return true

#endregion

#region Private Methods

func _initialize_compute():
	rd = RenderingServer.get_rendering_device()
	
	if !rd:
		push_error("could not find rendering device, halting compute initialization")
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


func _update_debug_enabled() -> void:
	for compiled_shader_stage: CompiledShaderStage in _all_shader_stages.values():
		compiled_shader_stage.debug = debug


func _recompile_all_shaders() -> void:
	for compiled_shader_stage: CompiledShaderStage in _all_shader_stages.values():
		compiled_shader_stage.try_compile()

#endregion


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
			
			var file = FileAccess.open(shader_stage.resource_path, FileAccess.READ)
			
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
			push_error("shader compilation errors: \n", error)
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
