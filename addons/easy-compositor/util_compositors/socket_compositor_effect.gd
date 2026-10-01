@tool
class_name SocketCompositorEffect
extends EnhancedCompositorEffect

signal render_callback(
	render_size: Vector2i,
	rd_instance: RenderingDeviceInstance,
	scene_buffers: RenderSceneBuffersRD,
	scene_data: RenderSceneDataRD
)


func _enhanced_render_callback(render_size: Vector2i) -> void:
	render_callback.emit(render_size, _current_rd_instance, _current_render_scene_buffers, _current_render_scene_data)
