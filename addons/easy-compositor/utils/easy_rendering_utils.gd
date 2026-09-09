class_name EasyRenderingUtils

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
	texture_format: RenderingDevice.DataFormat = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
	usage_bits: int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT,
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
	
	return RenderingDeviceTexture.new(rd_instance, rd_instance.rd.texture_create(
		format,
		view,
		data
	))


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
	uniform_sets: Array[Array],
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
		var uniforms: Array[RDUniform]
		
		uniforms.assign(uniform_sets[i])
		
		if uniforms.is_empty():
			continue
		
		var uniform_set: RID = UniformSetCacheRD.get_cache(compiled_shader_stage.shader, i, uniforms)
		
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
