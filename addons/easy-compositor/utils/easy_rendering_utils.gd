class_name EasyRenderingUtils

const DEFAULT_TEXTURE_DATA_FORMAT: RenderingDevice.DataFormat = RenderingDevice.DataFormat.DATA_FORMAT_R32G32B32A32_SFLOAT

const DEFAULT_TEXTURE_USAGE_BITS: int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT

static var compute_lists_by_rd_instance: Dictionary[RenderingDeviceInstance, int]


static func get_image_uniform(image: RID, binding: int) -> RDUniform:
	var uniform := RDUniform.new()
	
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(image)
	
	return uniform


static func get_sampler_uniform(rd_instance: RenderingDeviceInstance, image: RID, binding: int, linear: bool = true) -> RDUniform:
	assert(rd_instance and rd_instance.is_valid(), "rd_instance must be valid")
	
	var uniform := RDUniform.new()
	
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = binding
	uniform.add_id(rd_instance.linear_sampler if linear else rd_instance.nearest_sampler)
	uniform.add_id(image)
	
	return uniform


static func get_buffer_uniform(buffer: RID, binding: int) -> RDUniform:
	var uniform := RDUniform.new()
	
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	
	return uniform


static func get_storage_buffer_uniform(buffer: RID, binding: int) -> RDUniform:
	var uniform := RDUniform.new()
	
	uniform.uniform_tyep = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	
	return uniform


static func get_push_constants(
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


static func get_groups_count(render_size: Vector3i, group_size: Vector3i) -> Vector3i:
	return Vector3i(
		divide_by_tile_size(render_size.x, group_size.x),
		divide_by_tile_size(render_size.y, group_size.y),
		divide_by_tile_size(render_size.z, group_size.z)
	)


static func divide_vector2i_by_tile_size(size: Vector2i, tile_size: Vector2i) -> Vector2i:
	return Vector2i(
		divide_by_tile_size(size.x, tile_size.x),
		divide_by_tile_size(size.y, tile_size.y)
	)


static func divide_by_tile_size(size: int, tile_size: int) -> int:
	return (size - 1) / tile_size + 1


static func create_texture(
	rd_instance: RenderingDeviceInstance,
	size: Vector2i,
	data: Array[PackedByteArray] = [],
	texture_format: RenderingDevice.DataFormat = DEFAULT_TEXTURE_DATA_FORMAT,
	usage_bits: int = DEFAULT_TEXTURE_USAGE_BITS,
	discardable = false
) -> RenderingDeviceTexture:
	assert(rd_instance and rd_instance.is_valid(), "rd_instance must be valid")
	
	var format: RDTextureFormat = RDTextureFormat.new()
	
	format.format = texture_format
	format.width = size.x
	format.height = size.y
	format.usage_bits = usage_bits
	format.is_discardable = discardable
	
	var view: RDTextureView = RDTextureView.new()
	
	return RenderingDeviceTexture.new(
		rd_instance,
		rd_instance.rd.texture_create(
			format,
			view,
			data
		),
		format
	)


static func create_texture_3d(
	rd_instance: RenderingDeviceInstance,
	size: Vector3i,
	data: Array[PackedByteArray] = [],
	texture_format: RenderingDevice.DataFormat = DEFAULT_TEXTURE_DATA_FORMAT,
	usage_bits: int = DEFAULT_TEXTURE_USAGE_BITS,
	discardable = false
) -> RenderingDeviceTexture:
	assert(rd_instance and rd_instance.is_valid(), "rd_instance must be valid")
	
	var format: RDTextureFormat = RDTextureFormat.new()
	
	format.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	format.format = texture_format
	format.width = size.x
	format.height = size.y
	format.depth = size.z
	format.usage_bits = usage_bits
	format.is_discardable = discardable
	
	var view: RDTextureView = RDTextureView.new()
	
	return RenderingDeviceTexture.new(
		rd_instance,
		rd_instance.rd.texture_create(
			format,
			view,
			data
		),
		format
	)


static func create_texture_from_format(
	rd_instance: RenderingDeviceInstance,
	format: RDTextureFormat,
	data: Array[PackedByteArray] = [],
) -> RenderingDeviceTexture:
	assert(rd_instance and rd_instance.is_valid(), "rd_instance must be valid")
	
	var view: RDTextureView = RDTextureView.new()
	
	return RenderingDeviceTexture.new(
		rd_instance,
		rd_instance.rd.texture_create(
			format,
			view,
			data
		),
		format
	)


static func begin_compute(
	rd_instance: RenderingDeviceInstance,
	label: String = "DefaultLabel",
	color: Color = Color(1, 1, 1, 1)
) -> void:
	if compute_lists_by_rd_instance.has(rd_instance):
		push_error("there's already an ongoing compute list, end it first")
		return
	
	rd_instance.rd.draw_command_begin_label(label, color)
	
	compute_lists_by_rd_instance[rd_instance] = rd_instance.rd.compute_list_begin()


static func dispatch_stage(
	rd_instance: RenderingDeviceInstance,
	compiled_shader_stage: CompiledShaderStage,
	uniform_sets: Array,
	push_constants: PackedByteArray,
	dispatch_size: Vector3i,
	begin_and_end_manually: bool = false,
	label: String = "DefaultLabel",
	color: Color = Color(1, 1, 1, 1)
) -> bool:
	if !compiled_shader_stage.is_compiled():
		push_error("cannot dispatch invalid shader stage")
		return false
	
	if begin_and_end_manually and !compute_lists_by_rd_instance.has(rd_instance):
		push_error("you must start a compute list before dispatching anything")
		return false
	
	if !begin_and_end_manually:
		begin_compute(rd_instance, label, color)
	
	var compute_list: int = compute_lists_by_rd_instance[rd_instance]
	
	rd_instance.rd.compute_list_bind_compute_pipeline(compute_list, compiled_shader_stage.pipeline)
	
	for i in range(uniform_sets.size()):
		if uniform_sets[i] is Array and rd_instance.is_local:
			push_error("cannot create uniform set on dispatch for local rendering device, please pass in an array of uniform sets")
			return false
		
		var uniform_set: RID
		
		if rd_instance.is_local:
			# TODO @sphynx-owner: allow caching of uniform sets.
			uniform_set = uniform_sets[i]
			
		else:
			var uniforms: Array[RDUniform]
			
			uniforms.assign(uniform_sets[i])
			
			if uniforms.is_empty():
				continue
			
			uniform_set = UniformSetCacheRD.get_cache(compiled_shader_stage.shader, i, uniforms)
		
		rd_instance.rd.compute_list_bind_uniform_set(compute_list, uniform_set, i)
	
	rd_instance.rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	
	rd_instance.rd.compute_list_dispatch(compute_list, dispatch_size.x, dispatch_size.y, dispatch_size.z)
	
	if !begin_and_end_manually:
		end_compute(rd_instance)
	
	return true


static func add_barrier(rd_instance: RenderingDeviceInstance) -> void:
	if !compute_lists_by_rd_instance.has(rd_instance):
		push_error("there is no current compute list to add barrier to")
		return
	
	rd_instance.rd.compute_list_add_barrier(compute_lists_by_rd_instance[rd_instance])


static func end_compute(rd_instance: RenderingDeviceInstance) -> void:
	if !compute_lists_by_rd_instance.has(rd_instance):
		push_error("there is no current compute list to end")
		return
	
	rd_instance.rd.compute_list_end()
	
	rd_instance.rd.draw_command_end_label()
	
	compute_lists_by_rd_instance.erase(rd_instance)


static func get_viable_rectangle_dimensions(primitive_count: int, primitive_dimensions: Vector2i = Vector2i(1, 1)) -> Vector2i:
	var ratio: float = float(primitive_dimensions.x) / primitive_dimensions.y
	
	var flip: bool = false
	
	if ratio > 1.0:
		flip = true
		ratio = 1.0 / ratio
	
	var base_root: int = ceil(sqrt(primitive_count * ratio))
	
	var lenience: int = 0
	
	var iteration_count: int = 0
	
	var root_distance: int = 0
	
	# HACK @sphynx-owner: some magic cap, with primitive count of 10000 and default primitive size does not surpass 20 iterations
	while iteration_count < 100:
		iteration_count += 1
		
		root_distance += 1
		
		@warning_ignore("integer_division")
		var root: int = base_root + (root_distance / 2) * (1 if iteration_count % 2 else -1)
		
		@warning_ignore("integer_division")
		var root_2: int = (primitive_count - 1) / root + 1
		
		var result: int = root * root_2 - primitive_count
		
		if result >= 0 and result <= lenience:
			return Vector2(root if flip else root_2, root_2 if flip else root)
		
		lenience += 2
	
	return Vector2(-1, -1)
