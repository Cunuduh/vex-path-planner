extends PanelContainer

signal heading_changed(index, new_heading)
signal position_changed(index, new_position)
signal heading_visibility_changed(index, is_visible)

var current_index: int = -1

@onready var index_label = $VBoxContainer/IndexLabel
@onready var x_spinbox = $VBoxContainer/PositionContainer/XContainer/SpinBox
@onready var y_spinbox = $VBoxContainer/PositionContainer/YContainer/SpinBox
@onready var heading_spinbox = $VBoxContainer/HeadingContainer/SpinBox
@onready var heading_visibility_checkbox = $VBoxContainer/HeadingVisibilityContainer/CheckBox
@onready var reverse_button = $VBoxContainer/ReversedContainer/Button
func _ready() -> void:
  x_spinbox.connect("value_changed", _on_x_changed)
  y_spinbox.connect("value_changed", _on_y_changed)
  heading_spinbox.connect("value_changed", _on_heading_value_changed)
  heading_visibility_checkbox.connect("toggled", _on_heading_visibility_toggled)
  reverse_button.connect("pressed", _on_reverse_pressed)

func update_values(index: int, pos: Vector2, heading: float, is_heading_visible: bool) -> void:
  current_index = index
  index_label.text = "Point: " + str(index)
  
  x_spinbox.set_block_signals(true)
  y_spinbox.set_block_signals(true)
  heading_spinbox.set_block_signals(true)
  heading_visibility_checkbox.set_block_signals(true)

  x_spinbox.value = pos.x
  y_spinbox.value = pos.y
  heading_spinbox.value = normalize_heading(heading)
  heading_visibility_checkbox.button_pressed = is_heading_visible

  x_spinbox.set_block_signals(false)
  y_spinbox.set_block_signals(false)
  heading_spinbox.set_block_signals(false)
  heading_visibility_checkbox.set_block_signals(false)

func _on_x_changed(new_value: float) -> void:
  if current_index >= 0:
    var current_pos = Vector2(new_value, y_spinbox.value)
    emit_signal("position_changed", current_index, current_pos)

func _on_y_changed(new_value: float) -> void:
  if current_index >= 0:
    var current_pos = Vector2(x_spinbox.value, new_value)
    emit_signal("position_changed", current_index, current_pos)

func _on_heading_value_changed(new_value: float) -> void:
  if current_index >= 0:
    var normalized_heading = normalize_heading(new_value)
    if normalized_heading != new_value:
      heading_spinbox.set_block_signals(true)
      heading_spinbox.value = normalized_heading
      heading_spinbox.set_block_signals(false)
    emit_signal("heading_changed", current_index, normalized_heading)

func _on_heading_visibility_toggled(button_pressed: bool) -> void:
  if current_index >= 0:
    emit_signal("heading_visibility_changed", current_index, button_pressed)

func _on_reverse_pressed() -> void:
  if current_index >= 0:
    var new_heading = normalize_heading(heading_spinbox.value + 180.0)
    heading_spinbox.set_block_signals(true)
    heading_spinbox.value = new_heading
    heading_spinbox.set_block_signals(false)
    emit_signal("heading_changed", current_index, new_heading)

func normalize_heading(heading: float) -> float:
  var normalized = fmod(heading, 360.0)
  if normalized < 0:
    normalized += 360.0
  return normalized
