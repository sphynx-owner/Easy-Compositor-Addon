@tool
class_name CompiledShaderStage
# TODO @sphynx-owner: Extend this to support compilation of all types of shaders, 
# not just RenderingDevice.SHADER_STAGE_COMPUTE. This would potentially mean allowing multiple shaders to live
# on the same shader file, and maybe integrating things like the RDShaderSource, which has multiple shader types.

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


func _init(rd_instance: RenderingDeviceInstance, p_shader_stage: RDShaderFile, p_debug: bool = false) -> void:
	assert(rd_instance and rd_instance.is_valid(), "rd_instance must be valid to create shader stage")
	
	_init_gate = true
	
	rd = rd_instance.rd
	
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
	
	if !shader_stage.resource_path:
		push_error("shader file does not have a resource path, cannot generate shader stage")
		return false
	
	var file_text: String = _get_shader_file_text(shader_stage)
	
	file_text = file_text.replace("#[compute]", "")
	
	var found_index: int = -1
	
	while true:
		found_index = file_text.find("#include", found_index + 1)
		
		if found_index == -1:
			break
		
		var open_quotes_index: int = file_text.find("\"", found_index)
		var close_quotes_index: int = file_text.find("\"", open_quotes_index + 1)
		
		var include_path: String = file_text.substr(open_quotes_index + 1, close_quotes_index - open_quotes_index - 1)
		
		var full_path: String = shader_stage.resource_path + "/../" + include_path
		
		var included_file: FileAccess = FileAccess.open(full_path, FileAccess.READ)
		
		file_text = file_text.substr(0, found_index) + included_file.get_as_text() + file_text.substr(close_quotes_index + 1, file_text.length() - close_quotes_index - 1)
	
	file_text = file_text.replace(EnhancedCompositorEffect.VERSION_SYMBOL, EnhancedCompositorEffect.VERSION_SNIPPET)
	
	if debug and file_text.contains(EnhancedCompositorEffect.DEBUG_SYMBOL):
		file_text = file_text.replace(EnhancedCompositorEffect.DEBUG_SYMBOL, EnhancedCompositorEffect.DEBUG_SNIPPET)
		
		_needs_debug = true
	
	var shader_source: RDShaderSource = RDShaderSource.new()
	
	shader_source.set_stage_source(RenderingDevice.SHADER_STAGE_COMPUTE, file_text)
	
	shader_spirv = rd.shader_compile_spirv_from_source(shader_source, false)
	
	var error: String = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	
	if error:
		push_error("shader compilation errors in %s: \n" % [shader_stage.resource_path.get_file()], error)
		return false
	
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)
	
	_is_compiled = true
	
	return true


func _get_shader_file_text(shader_file: RDShaderFile) -> String:
	var path: String = shader_stage.resource_path
	
	if !OS.has_feature("editor"):
		path = path.replace(".glsl", ".glsl.txt")
	
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	
	if !file:
		push_error("could not open file %s for shader stage generation" % [path])
		return ""
	
	return file.get_as_text()


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
