tool

# Converts a scene branch into C++ engine-side code that will build it.

# Format: { node: var_name }
var _var_names := {}
var _lines := PoolStringArray()


func convert_branch(root: Node) -> String:
	_var_names.clear()
	_lines.resize(0)
	_process_node(root, root)
	var code := _lines.join("\n")
	return code


func _process_node(node: Node, root: Node) -> void:
	var klass_name := node.get_class()

	var var_name := ""
	if node != root:
		var_name = _pascal_to_snake(node.name)

		# Ensure that each variable has a unique name.
		var duplicate_count := 0
		for other_var_name in _var_names.values():
			if other_var_name.begins_with(var_name):
				duplicate_count += 1
		if duplicate_count > 0:
			push_warning("Multiple Nodes are named \"%s\", give each node a unique name for the best results." % node.name)
			var_name += String(duplicate_count)

		_var_names[node] = var_name
		_lines.append(str(klass_name, " *", var_name, " = memnew(", klass_name, ");"))

	# Ignore properties which are sometimes overriden by other factors.
	var ignored_properties := []
	if node is Control:
		if (node.get_parent() is Container) or node == root:
			ignored_properties += [
				"margin_left",
				"margin_right",
				"margin_top",
				"margin_bottom",
				"anchor_left",
				"anchor_right",
				"anchor_top",
				"anchor_bottom"
			]
		if node.get_parent() is TabContainer:
			ignored_properties.append("visible")

	# used to check if a property is overriden
	var default_instance : Node = ClassDB.instance(klass_name)
	assert(default_instance is Node)

	# Set properties
	var props = ClassDB.class_get_property_list(node.get_class(), false)
	for prop in props:
		if (prop.usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		if prop.name in ignored_properties:
			continue
		var default_value = default_instance.get(prop.name)
		var current_value = node.get(prop.name)
		if current_value != default_value:
			#print(prop.name, " = ", current_value)
			var set_code := _get_property_set_code(node, prop.name, current_value)
			if node == root:
				_lines.append(str(set_code, ";"))
			else:
				_lines.append(str(var_name, "->", set_code, ";"))

	default_instance.free()

	# Process children
	if node.get_child_count() > 0:
		_lines.append("")

		for child in node.get_children():
			_process_node(child, root)
			if node == root:
				_lines.append(str("add_child(", _var_names[child], ");"))
			else:
				_lines.append(str(var_name, "->add_child(", _var_names[child], ");"))
			_lines.append("")


static func _get_property_set_code(obj: Object, property_name: String, value) -> String:
	var value_code := _value_to_code(value)

	# We first check very specific cases for best translation (but requires specific code)

	if obj is Control:
		match property_name:
			"margin_left":
				return str("set_margin(MARGIN_LEFT, ", value_code, " * EDSCALE)")
			"margin_right":
				return str("set_margin(MARGIN_RIGHT, ", value_code, " * EDSCALE)")
			"margin_top":
				return str("set_margin(MARGIN_TOP, ", value_code, " * EDSCALE)")
			"margin_bottom":
				return str("set_margin(MARGIN_BOTTOM, ", value_code, " * EDSCALE)")

			"anchor_left":
				return str("set_anchor(MARGIN_LEFT, ", value_code, ")")
			"anchor_right":
				return str("set_anchor(MARGIN_RIGHT, ", value_code, ")")
			"anchor_top":
				return str("set_anchor(MARGIN_TOP, ", value_code, ")")
			"anchor_bottom":
				return str("set_anchor(MARGIN_BOTTOM, ", value_code, ")")

			"size_flags_vertical":
				return str("set_v_size_flags(", _get_size_flags_code(value), ")")
			"size_flags_horizontal":
				return str("set_h_size_flags(", _get_size_flags_code(value), ")")

	if obj is TextureRect:
		match property_name:
			"stretch_mode":
				return str("set_stretch_mode(", _texture_rect_stretch_mode_codes[value], ")")

	if obj is BoxContainer:
		match property_name:
			"alignment":
				return str("set_alignment(", _box_container_alignment_codes[value], ")")

	if obj is Label:
		match property_name:
			"align":
				return str("set_align(", _label_align_codes[value], ")")
			"valign":
				return str("set_valign(", _label_valign_codes[value], ")")

	# Check if the setter is only aliased
	for klass in _aliased_setters:
		if obj is klass:
			var setters : Dictionary = _aliased_setters[klass]
			if property_name in setters:
				var setter_name : String = setters[property_name]
				return str(setter_name, "(", value_code, ")")

	# Assume regular setter
	return str("set_", property_name, "(", value_code, ")")

	# This should work but ideally we should avoid it because it's slow
	#return str("set(\"", property_name, "\", ", value_code, ")")


static func _value_to_code(v) -> String:
	match(typeof(v)):
		# var2str() will automatically pad decimals for floats
		# See https://github.com/godotengine/godot-proposals/issues/1693
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_REAL:
			return str(var2str(v), "f")
		TYPE_VECTOR2:
			return str("Vector2(", var2str(v.x), "f, ", var2str(v.y), "f)")
		TYPE_VECTOR3:
			return str("Vector3(", var2str(v.x), "f, ", var2str(v.y), "f, ", var2str(v.z), "f)")
		TYPE_COLOR:
			return str("Color(", var2str(v.r), "f, ", var2str(v.g), "f, ", var2str(v.b), "f, ", var2str(v.a), "f)")
		TYPE_STRING:
			return str("TTR(\"", v, "\")")
		TYPE_OBJECT:
				return "/* TODO: reference here */"
		_:
			return str(v)


static func _pascal_to_snake(src: String) -> String:
	var dst = ""
	for i in len(src):
		var c : String = src[i]
		dst += c.to_lower()
		if i + 1 == len(src):
			continue

		var next_c = src[i + 1]
		if next_c != next_c.to_lower():
			dst += "_"
	return dst


# Some setters have a different name in engine code
const _aliased_setters = {
	Control: {
		"rect_min_size": "set_custom_minimum_size"
	},
	WindowDialog: {
		"window_title": "set_title"
	}
}


static func _get_size_flags_code(sf: int) -> String:
	match sf:
		Control.SIZE_EXPAND:
			return "Control::SIZE_EXPAND"
		Control.SIZE_EXPAND_FILL:
			return "Control::SIZE_EXPAND_FILL"
		Control.SIZE_FILL:
			return "Control::SIZE_FILL"
		Control.SIZE_SHRINK_CENTER:
			return "Control::SIZE_SHRINK_CENTER"
		Control.SIZE_SHRINK_END:
			return "Control::SIZE_SHRINK_END"
		_:
			return str(sf)

# IF ONLY GODOT ALLOWED US TO GET ENUM NAMES AS STRINGS
# See https://github.com/godotengine/godot-proposals/issues/2854

const _label_align_codes = {
	Label.ALIGN_LEFT: "Label::ALIGN_LEFT",
	Label.ALIGN_CENTER: "Label::ALIGN_CENTER",
	Label.ALIGN_RIGHT: "Label::ALIGN_RIGHT",
	Label.ALIGN_FILL: "Label::ALIGN_FILL"
}

const _label_valign_codes = {
	Label.VALIGN_TOP: "Label::VALIGN_TOP",
	Label.VALIGN_CENTER: "Label::VALIGN_CENTER",
	Label.VALIGN_BOTTOM: "Label::VALIGN_BOTTOM",
	Label.VALIGN_FILL: "Label::VALIGN_FILL"
}

const _box_container_alignment_codes = {
	BoxContainer.ALIGN_BEGIN: "BoxContainer::ALIGN_END",
	BoxContainer.ALIGN_CENTER: "BoxContainer::ALIGN_CENTER",
	BoxContainer.ALIGN_END: "BoxContainer::ALIGN_END",
}

const _texture_rect_stretch_mode_codes = {
	TextureRect.STRETCH_SCALE_ON_EXPAND: "TextureRect::STRETCH_SCALE_ON_EXPAND",
	TextureRect.STRETCH_SCALE: "TextureRect::STRETCH_SCALE",
	TextureRect.STRETCH_TILE: "TextureRect::STRETCH_TILE",
	TextureRect.STRETCH_KEEP: "TextureRect::STRETCH_KEEP",
	TextureRect.STRETCH_KEEP_CENTERED: "TextureRect::STRETCH_KEEP_CENTERED",
	TextureRect.STRETCH_KEEP_ASPECT: "TextureRect::STRETCH_KEEP_ASPECT",
	TextureRect.STRETCH_KEEP_ASPECT_CENTERED: "TextureRect::STRETCH_KEEP_ASPECT_CENTERED",
	TextureRect.STRETCH_KEEP_ASPECT_COVERED: "TextureRect::STRETCH_KEEP_ASPECT_COVERED"
}
