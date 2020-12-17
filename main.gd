extends Node

const Converter = preload("res://addons/zylann.scene_code_converter/converter.gd")

onready var _text_edit = $TextEdit

func _ready():
	var converter = Converter.new()
	#_text_edit.add_font_override("font", _text_edit.get_font("source", "EditorFonts"))
	_text_edit.text = converter.convert_branch($WindowDialog)
