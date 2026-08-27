class_name EasyCompositorUtils

const CAM_ENVIRONMENT_PROP: StringName = &"environment"
const ENV_ENVIRONMENT_PROP: StringName = &"environment"
const CAM_CAMERA_ATTRIBUTES_PROP: StringName = &"attributes"
const ENV_CAMERA_ATTRIBUTES_PROP: StringName = &"camera_attributes"
const CAM_COMPOSITOR_PROP: StringName = &"compositor"
const ENV_COMPOSITOR_PROP: StringName = &"compositor"

static func get_or_add_active_compositor_effect(node: Node, type: GDScript) -> CompositorEffect:
	var compositor: Compositor = get_active_compositor(node)
	
	if !compositor:
		compositor = Compositor.new()
		
		set_active_compositor(node, compositor)
	
	for compositor_effect in compositor.compositor_effects:
		if is_script_type(compositor_effect, type):
			return compositor_effect
	
	var new_effect: CompositorEffect = type.new()
	
	if !new_effect:
		push_error("could not create a new compositor effect")
		return null
	
	# NOTICE @sphynx-skillcap: deliberately setting the array again to trigger the setter's update.
	# Simply using append() would not update the compositor.
	compositor.compositor_effects = compositor.compositor_effects + [new_effect]
	
	return new_effect


static func set_active_environment(node: Node, environment: Environment) -> void:
	_set_active_post_process_config(node, CAM_ENVIRONMENT_PROP, ENV_ENVIRONMENT_PROP, environment)


static func get_active_environment(node: Node) -> Environment:
	return _get_active_post_process_config(node, CAM_ENVIRONMENT_PROP, ENV_ENVIRONMENT_PROP)


static func set_active_camera_attributes(node: Node, attributes: CameraAttributes) -> void:
	_set_active_post_process_config(node, CAM_CAMERA_ATTRIBUTES_PROP, ENV_CAMERA_ATTRIBUTES_PROP, attributes)


static func get_active_camera_attributes(node: Node) -> CameraAttributes:
	return _get_active_post_process_config(node, CAM_CAMERA_ATTRIBUTES_PROP, ENV_CAMERA_ATTRIBUTES_PROP)


static func set_active_compositor(node: Node, compositor: Compositor) -> void:
	_set_active_post_process_config(node, CAM_COMPOSITOR_PROP, ENV_COMPOSITOR_PROP, compositor)


static func get_active_compositor(node: Node) -> Compositor:
	return _get_active_post_process_config(node, CAM_COMPOSITOR_PROP, ENV_COMPOSITOR_PROP)


## Assumes there is an active camera that we can override post process attributes on.
# TODO @sphynx-owner: explore ensuring null values on the world3D camera attributes and environment properties.
static func _set_active_post_process_config(node: Node, cam_prop_name: StringName, env_prop_name: StringName, value: Object) -> void:
	var viewport: Viewport = safe_get_viewport(node)
	
	# If the value is null, we must ensure it's null along the fallback value on the environment
	# as well.
	if value == null:
		var environment: WorldEnvironment = find_environment_recursive(viewport)
		
		if environment:
			environment.set(env_prop_name, value)
	
	var camera: Camera3D = viewport.get_camera_3d()
	
	if !camera:
		push_error("no camera available to set active post process config")
		return
	
	camera.set(cam_prop_name, value)


## The post-proecssing of a scene is influenced by nodes present in it. The WorldEnvironment node
## and the active Camera3D/2D node both accept environment, camera attributes, and compositor overrides.
## The overrides set on the camera take precedence over the ones set by the environment.
# TODO @sphynx-owner: explore falling back to the world3D camera attributes and environment properties
# when the the envrionment is null or does not have an override itself.
static func _get_active_post_process_config(
	node: Node,
	cam_prop_name: StringName,
	env_prop_name: StringName
) -> Object:
	var viewport: Viewport = safe_get_viewport(node)
	
	if !viewport:
		push_error("node does not have a viewport")
		return null
	
	var camera: Camera3D = viewport.get_camera_3d()
	
	if camera and camera.get(cam_prop_name):
		return camera.get(cam_prop_name)
	
	var environment: WorldEnvironment = find_environment_recursive(viewport)
	
	if environment and environment.get(env_prop_name):
		return environment.get(env_prop_name)
	
	return null


static func is_script_type(object: Object, type: GDScript) -> bool:
	var base_script: GDScript = object.get_script()
	
	while base_script:
		if base_script == type:
			return true
		
		base_script = base_script.get_base_script()
	
	return false


## Return a more intuitive viewport.
static func safe_get_viewport(node: Node) -> Viewport:
	if node is Viewport:
		return node
	
	return node.get_viewport()


static func find_environment_recursive(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	
	for child in node.get_children():
		var found: Node = find_environment_recursive(child)
		
		if found:
			return found
	
	return null
