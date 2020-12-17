tool
extends WindowDialog

const Util = preload("./util.gd")

onready var _text_edit = $VBoxContainer/TextEdit


func _ready():
	if Util.is_in_edited_scene(self):
		return
	_text_edit.add_font_override("font", get_font("source", "EditorFonts"))


func set_code(code: String):
	_text_edit.text = code


func _on_CopyToClipboard_pressed():
	_text_edit.select_all()
	OS.clipboard = _text_edit.text


func _on_Ok_pressed():
	hide()
