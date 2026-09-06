@tool
class_name RenderingDeviceTexture

var rd: RenderingDevice

var texture: RID


func _init(rd_instance: RenderingDeviceInstance, p_texture: RID) -> void:
	assert(rd_instance and rd_instance.is_valid(), "rd_instance must be valid")
	
	rd = rd_instance.rd
	
	texture = p_texture


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if !rd:
			return
		
		if texture.is_valid():
			rd.free_rid(texture)
