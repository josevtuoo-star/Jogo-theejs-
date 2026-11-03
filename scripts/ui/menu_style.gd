class_name MenuStyle
extends RefCounted
## Aparência comum dos menus (inicial e de pausa): botões largos para o dedo,
## cinza-escuro com borda âmbar no toque, títulos com contorno.

const ACCENT := Color(0.95, 0.74, 0.32)


static func button(text: String, action: Callable, width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 58.0)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(0.92, 0.92, 0.88))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.7))
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))
	b.add_theme_stylebox_override("normal", _box(Color(0.1, 0.11, 0.1, 0.85), Color(1, 1, 1, 0.12)))
	b.add_theme_stylebox_override("hover", _box(Color(0.16, 0.16, 0.14, 0.92), ACCENT * Color(1, 1, 1, 0.7)))
	b.add_theme_stylebox_override("pressed", _box(Color(0.22, 0.19, 0.12, 0.95), ACCENT))
	b.add_theme_stylebox_override("disabled", _box(Color(0.08, 0.08, 0.08, 0.6), Color(1, 1, 1, 0.05)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if action.is_valid():
		b.pressed.connect(action)
	return b


static func _box(color: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	box.set_content_margin_all(10)
	return box


static func panel(color: Color = Color(0.08, 0.085, 0.08, 0.92)) -> StyleBoxFlat:
	var box := _box(color, Color(1, 1, 1, 0.1))
	box.set_content_margin_all(22)
	return box


static func label(text: String, font_size: int = 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.88, 0.88, 0.84))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(text: String, font_size: int = 56) -> Label:
	var l := label(text, font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_color_override("font_color", Color(0.93, 0.9, 0.82))
	l.add_theme_constant_override("outline_size", 10)
	return l


static func field(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0.0, 52.0)
	e.add_theme_font_size_override("font_size", 20)
	e.add_theme_stylebox_override("normal", _box(Color(0.04, 0.045, 0.04, 0.9), Color(1, 1, 1, 0.18)))
	e.add_theme_stylebox_override("focus", _box(Color(0.05, 0.05, 0.04, 0.95), ACCENT))
	return e
