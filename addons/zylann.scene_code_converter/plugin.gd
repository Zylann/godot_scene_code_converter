tool
extends EditorPlugin

const Converter = preload("./converter.gd")
const ConversionDialogScene = preload("./conversion_dialog.tscn")

var _convert_button : Button
var _conversion_dialog = null


func _enter_tree():
	_convert_button = Button.new()
	_convert_button.text = "Convert to engine code"
	_convert_button.connect("pressed", self, "_on_ConvertToEngineCode_pressed")
	add_control_to_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, _convert_button)

	var base_control = get_editor_interface().get_base_control()

	_conversion_dialog = ConversionDialogScene.instance()
	base_control.add_child(_conversion_dialog)


func _exit_tree():
	_convert_button.queue_free()
	_convert_button = null
	
	_conversion_dialog.queue_free()
	_conversion_dialog = null


func _on_ConvertToEngineCode_pressed():
	var selected_nodes = get_editor_interface().get_selection().get_selected_nodes()
	if len(selected_nodes) == 0:
		push_warning("No nodes selected for conversion")
		return
	
	var node = selected_nodes[0]
	assert(node is Node)
	
	var converter := Converter.new()
	var code := converter.convert_branch(node)
	_conversion_dialog.set_code(code)
	_conversion_dialog.popup_centered_ratio()

