@tool
class_name RenderingDeviceTexture

var rd: RenderingDevice

var texture: RID

var format_cache: RDTextureFormat


func _init(rd_instance: RenderingDeviceInstance, p_texture: RID, p_format_cache: RDTextureFormat = null) -> void:
	assert(rd_instance and rd_instance.is_valid(), "rd_instance must be valid")
	
	rd = rd_instance.rd
	
	texture = p_texture
	
	format_cache = p_format_cache


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if !rd:
			return
		
		if texture.is_valid():
			rd.free_rid(texture)


func get_size() -> Vector2i:
	if !format_cache:
		return Vector2i(-1, -1)
	
	return Vector2i(format_cache.width, format_cache.height)


func get_size_3d() -> Vector3i:
	if !format_cache:
		return Vector3i(-1, -1, -1)
	
	return Vector3i(format_cache.width, format_cache.height, format_cache.depth)
