@tool
class_name RenderingDeviceInstance
# NOTE @sphynx-owner: I created the rendering device instance system to
# avoid redundant creation of things like samplers, which do not need to be recreated
# more than once per rendering device.

static var _instances_by_rd: Dictionary[RenderingDevice, RenderingDeviceInstance]

var rd: RenderingDevice

var linear_sampler: RID

var nearest_sampler: RID


static func get_instance() -> RenderingDeviceInstance:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	
	if !rd:
		push_error("cannot find rendering device, returning null instance")
		return null
	
	if _instances_by_rd.has(rd):
		var instance: RenderingDeviceInstance = _instances_by_rd[rd]
		
		if !instance:
			push_error("cached rendering device instance is null, creating new one")
			return RenderingDeviceInstance.new(rd)
		
		return instance
	
	return RenderingDeviceInstance.new(rd)


static func _instance_created(rd: RenderingDevice, instance: RenderingDeviceInstance) -> void:
	_instances_by_rd[rd] = instance


static func _instance_predeleted(rd: RenderingDevice) -> void:
	_instances_by_rd.erase(rd)


func _init(p_rd: RenderingDevice):
	if _instances_by_rd.has(p_rd):
		push_error("cannot properly create RenderingDeviceInstance, rendering device already has an instance created for it")
		return
	
	rd = p_rd
	
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
