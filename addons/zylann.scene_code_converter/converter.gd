tool

# Converts a scene branch into C++ engine-side code that will build it.

var _vars = []
var _lines = []


func convert_branch(root: Node) -> String:
	_vars.clear()
	_lines.clear()
	_process_node(root, root)
	var code := PoolStringArray(_lines).join("\n")
	return code


func _process_node(node: Node, root: Node) -> Dictionary:
	var klass_name := node.get_class()
	
	var var_name = ""
	if node != root:
		var_name = _pascal_to_snake(klass_name)
		if var_name in _vars:
			var incremented_name = var_name
			var i = 1
			while incremented_name in _vars:
				i += 1
				incremented_name = str(var_name, i)
			var_name = incremented_name
		_vars.append(var_name)
	
	# Create the node in a variable if necessary
	if var_name != "":
		if not _has_default_node_name(node):
			_lines.append(str("// ", node.name))
		_lines.append(str(klass_name, " *", var_name, " = memnew(", klass_name, ");"))
	
	# Ignore properties which are sometimes overriden by other factors
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
			if var_name == "":
				_lines.append(str(set_code, ";"))
			else:
				_lines.append(str(var_name, "->", set_code, ";"))

	default_instance.free()

	# Process children
	if node.get_child_count() > 0:
		_lines.append("")
		
		for i in node.get_child_count():
			var child = node.get_child(i)
			if child.owner == null:
				continue
			var child_info = _process_node(child, root)
			if var_name == "":
				_lines.append(str("add_child(", child_info.var_name, ");"))
			else:
				_lines.append(str(var_name, "->add_child(", child_info.var_name, ");"))
			_lines.append("")
	
	return {
		"var_name": var_name
	}


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
		TYPE_BOOL:
			if v:
				return "true"
			else:
				return "false"
		TYPE_VECTOR2:
			return str("Vector2(", v.x, ", ", v.y, ")")
		TYPE_VECTOR3:
			return str("Vector3(", v.x, ", ", v.y, ", ", v.z, ")")
		TYPE_COLOR:
			return str("Color(", v.r, ", ", v.g, ", ", v.b, ", ", v.a, ")")
		TYPE_STRING:
			return str("TTR(\"", v, "\")")
		TYPE_OBJECT:
			if v is Resource:
				return "nullptr /* TODO resource here */"
			else:
				return "nullptr /* TODO reference here */"
		_:
			return str(v)


static func _pascal_to_snake(src: String) -> String:
	var dst = ""
	for i in len(src):
		var c : String = src[i]
		dst += c.to_lower()
		if i + 1 < len(src):
			var next_c = src[i + 1]
			if next_c != next_c.to_lower():
				dst += "_"
	return dst


static func _has_default_node_name(node: Node) -> bool:
	var cname = node.get_class()
	if node.name == cname:
		return true
	# Let's go the dumb way
	for i in range(2, 10):
		if node.name == str(cname, i):
			return true
	return false


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
