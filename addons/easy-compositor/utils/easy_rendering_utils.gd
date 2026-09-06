class_name EasyRenderingUtils



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
