@tool
extends EditorPlugin

const EasyCompositorExportPlugin = preload("res://addons/easy-compositor/easy_compositor_export_plugin.gd")


var export_plugin: EasyCompositorExportPlugin


func _enter_tree() -> void:
	export_plugin = EasyCompositorExportPlugin.new()
	
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	
	export_plugin = null
