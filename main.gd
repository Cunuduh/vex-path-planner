extends Control

var selected_point_index: int = -1
var multi_selection: Array[int] = []
var paths: Array = []
var screen_size = Vector2i(1152, 648)
var dragging: bool = false

const FIELD_SIZE_PIXELS = 482.0
const FIELD_SIZE_FEET := 12.0
const PIXELS_TO_FEET := FIELD_SIZE_FEET / FIELD_SIZE_PIXELS
const POINT_SELECTION_THRESHOLD = 15.0
const PATH_WIDTH = 2.0
enum PathType {LINEAR, BOOMERANG, SPLINE}
class PointData:
  var position: Vector2
  var heading: float = 0.0 # in degrees
  var heading_visibility: bool = true

  func _init(pos: Vector2, head: float = 0.0, show_heading: bool = false):
    position = pos
    heading = head
    heading_visibility = show_heading

class PathConnection:
  var start_index: int
  var end_index: int
  var path_type: PathType = PathType.LINEAR
  var waypoints: Array[int] = []

  func _init(start: int, end: int, type: PathType = PathType.LINEAR, points: Array[int] = []):
    start_index = start
    end_index = end
    path_type = type
    waypoints = points

var point_data: Array[PointData] = []

func _ready():
  var properties_panel = load("res://properties_panel.tscn").instantiate()
  add_child(properties_panel)
  properties_panel.hide()
  properties_panel.connect("heading_changed", _on_heading_changed)
  properties_panel.connect("position_changed", _on_position_changed)
  properties_panel.connect("heading_visibility_changed", _on_heading_visibility_changed)

func _gui_input(event: InputEvent) -> void:
  if event is InputEventMouseButton:
    var mouse_pos := get_global_mouse_position()
    if event.button_index == MOUSE_BUTTON_LEFT:
      var field_start_x = (screen_size.x - FIELD_SIZE_PIXELS) / 2.0
      var field_end_x = field_start_x + FIELD_SIZE_PIXELS
      var field_start_y = (screen_size.y - FIELD_SIZE_PIXELS) / 2.0
      var field_end_y = field_start_y + FIELD_SIZE_PIXELS
      
      if event.pressed:
        var ctrl_pressed = Input.is_key_pressed(KEY_CTRL)
        
        if mouse_pos.x >= field_start_x and mouse_pos.x <= field_end_x and \
           mouse_pos.y >= field_start_y and mouse_pos.y <= field_end_y:
          var shift_pressed = Input.is_key_pressed(KEY_SHIFT)
          var alt_pressed = Input.is_key_pressed(KEY_ALT)
          if ctrl_pressed:
            var clicked_point_index = find_closest_point(mouse_pos)
            print("Clicked on point index: ", clicked_point_index)

            if clicked_point_index != -1:
              if shift_pressed and multi_selection.size() > 0:
                if alt_pressed:
                  create_multi_point_path(PathType.BOOMERANG)
                else:
                  create_multi_point_path(PathType.LINEAR)
                multi_selection.clear()
                selected_point_index = -1
              else:
                if not clicked_point_index in multi_selection:
                  print("Adding point to multi-selection")
                  multi_selection.append(clicked_point_index)
                  selected_point_index = clicked_point_index
                  print("Multi-selection now: ", multi_selection)

              queue_redraw()
          else:
            var close_point_index = find_closest_point(mouse_pos)
            if close_point_index != -1:
              if shift_pressed and multi_selection.size() > 0:
                if not close_point_index in multi_selection:
                  multi_selection.append(close_point_index)
                selected_point_index = close_point_index
              else:
                select_point_by_index(close_point_index)
                multi_selection.clear()
                
              # Start dragging the point
              dragging = true
            else:
              add_point(mouse_pos)
              multi_selection.clear()
      else:
        # Mouse released, stop dragging
        dragging = false
        
    elif event.button_index == MOUSE_BUTTON_RIGHT:
      var point_index = find_closest_point(mouse_pos)
      if point_index != -1:
        remove_point(point_index)
        if point_index in multi_selection:
          multi_selection.erase(point_index)

    get_viewport().set_input_as_handled()
  
  elif event is InputEventMouseMotion and dragging and selected_point_index != -1:
    # Handle dragging movement
    drag_point(selected_point_index, get_global_mouse_position())

func _input(event: InputEvent) -> void:
  if event is InputEventKey:
    if event.pressed:
      if event.keycode == KEY_DELETE and selected_point_index != -1:
        remove_point(selected_point_index)
        multi_selection.clear()
        selected_point_index = -1
        queue_redraw()
      elif event.keycode == KEY_ESCAPE:
        multi_selection.clear()
        selected_point_index = -1
        queue_redraw()
      elif event.keycode == KEY_ENTER and multi_selection.size() > 1:
        print("Creating multi-point path")
        var alt_pressed = Input.is_key_pressed(KEY_ALT)
        var ctrl_pressed = Input.is_key_pressed(KEY_CTRL)

        var path_type = PathType.LINEAR
        if alt_pressed:
          path_type = PathType.BOOMERANG
        elif ctrl_pressed:
          path_type = PathType.SPLINE

        create_multi_point_path(path_type)
        multi_selection.clear()
        selected_point_index = -1
        queue_redraw()

func create_multi_point_path(path_type: PathType = PathType.LINEAR) -> void:
  if multi_selection.size() < 2:
    return
  if path_type == PathType.LINEAR:
    update_headings(multi_selection)

  if path_type == PathType.SPLINE and multi_selection.size() > 2:
    var start_index = multi_selection[0]
    var end_index = multi_selection[multi_selection.size() - 1]
    var waypoints: Array[int] = []
    
    for i in range(1, multi_selection.size() - 1):
      waypoints.append(multi_selection[i])
    
    var new_path = PathConnection.new(start_index, end_index, path_type, waypoints)
    print("New spline path created with waypoints: ", waypoints)
    paths.append(new_path)
  else:
    for i in range(multi_selection.size() - 1):
      var start_index = multi_selection[i]
      var end_index = multi_selection[i + 1]

      var new_path = PathConnection.new(start_index, end_index, path_type)
      print("New path created: start=", start_index, ", end=", end_index, ", type=", new_path.path_type)
      paths.append(new_path)

  queue_redraw()

func update_headings(point_indices: Array[int]) -> void:
  if point_indices.size() < 2:
    return
    
  for i in range(point_indices.size()):
    var current_idx := point_indices[i]
    var current_pos := point_data[current_idx].position
    var heading := 0.0
    if i == 0:
      var next_idx := point_indices[i + 1]
      if next_idx >= 0 and next_idx < point_data.size():
        heading = -rad_to_deg(atan2(- (point_data[next_idx].position - current_pos).y, (point_data[next_idx].position - current_pos).x)) + 90
    elif i == point_indices.size() - 1:
      var prev_idx := point_indices[i - 1]
      if prev_idx >= 0 and prev_idx < point_data.size():
        heading = -rad_to_deg(atan2(- (current_pos - point_data[prev_idx].position).y, (current_pos - point_data[prev_idx].position).x)) + 90
    else:
      var prev_idx := point_indices[i - 1]
      var next_idx := point_indices[i + 1]
      if prev_idx >= 0 and prev_idx < point_data.size() and next_idx >= 0 and next_idx < point_data.size():
        heading = -rad_to_deg(atan2(- (point_data[next_idx].position - current_pos).y, (point_data[next_idx].position - current_pos).x)) + 90

    heading = fmod(heading, 360.0)
    if heading < 0:
      heading += 360.0

    point_data[current_idx].heading = heading
      
  if selected_point_index != -1 and selected_point_index < point_data.size():
    update_properties_panel()

func add_point(pos: Vector2) -> void:
  var shift_pressed = Input.is_key_pressed(KEY_SHIFT)
  var feet_pos := pixel_to_feet(pos)
  if shift_pressed:
    feet_pos = feet_pos.snapped(Vector2(0.25, 0.25))
    pos = feet_to_pixel(feet_pos)

  var new_point = PointData.new(pos, 0.0, false)
  point_data.append(new_point)

  selected_point_index = point_data.size() - 1

  print("Added point at pixel pos: ", pos, ", real-world feet: ", feet_pos)
  queue_redraw()
  update_properties_panel()

func remove_point(index: int) -> void:
  if index >= 0 and index < point_data.size():
    point_data.remove_at(index)

    var i := 0
    while i < paths.size():
      var path = paths[i]
      if path.start_index == index or path.end_index == index or index in path.waypoints:
        paths.remove_at(i)
      else:
        if path.start_index > index:
          path.start_index -= 1
        if path.end_index > index:
          path.end_index -= 1

        for j in range(path.waypoints.size()):
          if path.waypoints[j] > index:
            path.waypoints[j] -= 1

        i += 1

    for j in range(multi_selection.size() - 1, -1, -1):
      if multi_selection[j] == index:
        multi_selection.remove_at(j)
      elif multi_selection[j] > index:
        multi_selection[j] -= 1

    if selected_point_index == index:
      selected_point_index = -1
    elif selected_point_index > index:
      selected_point_index -= 1

    queue_redraw()
    update_properties_panel()

func select_point(pos: Vector2) -> void:
  var closest_index := find_closest_point(pos)
  if closest_index != -1:
    selected_point_index = closest_index
  else:
    selected_point_index = -1

  queue_redraw()
  update_properties_panel()

func select_point_by_index(index: int) -> void:
  if index >= 0 and index < point_data.size():
    selected_point_index = index
    queue_redraw()
    update_properties_panel()

func find_closest_point(pos: Vector2) -> int:
  var closest_index := -1
  var closest_distance := POINT_SELECTION_THRESHOLD

  for i in range(point_data.size()):
    var distance := pos.distance_to(point_data[i].position)
    if distance < closest_distance:
      closest_distance = distance
      closest_index = i

  return closest_index

func add_path(start_index: int, end_index: int, path_type: PathType) -> void:
  var new_path := PathConnection.new(start_index, end_index, path_type)
  paths.append(new_path)
  queue_redraw()

func _draw():
  for path in paths:
    if path.start_index >= 0 and path.start_index < point_data.size() and \
       path.end_index >= 0 and path.end_index < point_data.size():
      var start_pos := point_data[path.start_index].position
      var end_pos := point_data[path.end_index].position

      var color := Color.GREEN
      if path.path_type == PathType.BOOMERANG:
        color = Color.ORANGE
      elif path.path_type == PathType.SPLINE:
        color = Color.CORNFLOWER_BLUE

      if path.path_type == PathType.SPLINE and path.waypoints.size() > 0:
        draw_multi_point_spline(path, color)
      else:
        if path.path_type == PathType.LINEAR:
          draw_line(start_pos, end_pos, color, PATH_WIDTH)
        else:
          draw_path(start_pos, end_pos, point_data[path.start_index].heading,
                  point_data[path.end_index].heading,
                  path.path_type, color)
  for i in range(point_data.size()):
    var point := point_data[i].position
    var heading_rad := deg_to_rad(- point_data[i].heading + 90)
    var heading_line_length := 20.0

    var point_color := Color.WHITE
    var point_size := 5.0

    if i == selected_point_index:
      point_color = Color.YELLOW
      point_size = 7.0
    elif i in multi_selection:
      point_color = Color(0.5, 0.75, 1.0)
      point_size = 7.0

    draw_circle(point, point_size, point_color)

    if point_data[i].heading_visibility:
      var heading_end := point + Vector2(cos(heading_rad), - sin(heading_rad)) * heading_line_length
      draw_line(point, heading_end, point_color, 2.0)

    draw_string(get_theme_default_font(), point + Vector2(10, -10), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

    if i in multi_selection:
      var selection_idx := multi_selection.find(i)
      draw_string(get_theme_default_font(), point + Vector2(10, 10),
                 "(" + str(selection_idx + 1) + ")", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.LIGHT_BLUE)


func draw_path(start_pos: Vector2, end_pos: Vector2, start_heading: float, end_heading: float, path_type: PathType, color: Color) -> void:
  if path_type == PathType.LINEAR:
    draw_line(start_pos, end_pos, color, PATH_WIDTH)
  elif path_type == PathType.BOOMERANG:
    draw_boomerang_path(start_pos, end_pos, end_heading, color)

func draw_boomerang_path(start: Vector2, end: Vector2, end_heading: float, color: Color) -> void:
  # https://www.desmos.com/calculator/sptjw5szex from EZ-Template docs page
  var theta_end := deg_to_rad(end_heading - 90)

  var h := start.distance_to(end)
  var d_lead := 0.625

  var x_1 := end.x - (h * cos(theta_end) * d_lead)
  var y_1 := end.y - (h * sin(theta_end) * d_lead)
  var points := []
  var steps := 20

  for i in range(steps + 1):
    var t := float(i) / steps
    var p := Vector2(
      (1 - t) * (1 - t) * start.x + 2 * (1 - t) * t * x_1 + t * t * end.x,
      (1 - t) * (1 - t) * start.y + 2 * (1 - t) * t * y_1 + t * t * end.y
    )
    points.append(p)

  for i in range(points.size() - 1):
    draw_line(points[i], points[i + 1], color, PATH_WIDTH)

func catmull_rom_interpolate(
  p0: Vector2,
  p1: Vector2,
  p2: Vector2,
  p3: Vector2,
  t: float,
  alpha: float = 1.0
) -> Vector2:
  # https://en.wikipedia.org/wiki/Centripetal_Catmull–Rom_spline
  var d01 := pow((p1 - p0).length(), alpha)
  var d12 := pow((p2 - p1).length(), alpha)
  var d23 := pow((p3 - p2).length(), alpha)

  var t0 := 0.0
  var t1 := t0 + d01
  var t2 := t1 + d12
  var t3 := t2 + d23

  var t_: float = lerp(t1, t2, t)
  
  var A1 := p0.lerp(p1, (t_ - t0) / (t1 - t0))
  var A2 := p1.lerp(p2, (t_ - t1) / (t2 - t1))
  var A3 := p2.lerp(p3, (t_ - t2) / (t3 - t2))

  var B1 := A1.lerp(A2, (t_ - t0) / (t2 - t0))
  var B2 := A2.lerp(A3, (t_ - t1) / (t3 - t1))

  return B1.lerp(B2, (t_ - t1) / (t2 - t1))

func draw_multi_point_spline(path: PathConnection, color: Color) -> void:
  var points: Array[Vector2] = []
  var all_indices: Array[int] = [path.start_index]
  all_indices.append_array(path.waypoints)
  all_indices.append(path.end_index)
  
  for idx in all_indices:
    if idx >= 0 and idx < point_data.size():
      points.append(point_data[idx].position)
  
  var spline_points: Array[Vector2] = []
  var num_points = points.size()
  var points_per_segment = 20
  
  for i in range(num_points - 1):
    var p0 = points[i-1] if i > 0 else points[0] - (points[1] - points[0])
    var p1 = points[i]
    var p2 = points[i+1]
    var p3 = points[i+2] if i < num_points - 2 else points[num_points-1] + (points[num_points-1] - points[num_points-2])
    
    for t_step in range(points_per_segment):
      var t = float(t_step) / points_per_segment
      var point = catmull_rom_interpolate(p0, p1, p2, p3, t)
      spline_points.append(point)
  
  spline_points.append(points[num_points-1])
  
  for i in range(spline_points.size() - 1):
    draw_line(spline_points[i], spline_points[i + 1], color, PATH_WIDTH)

func pixel_to_feet(pixel_pos: Vector2) -> Vector2:
  var centred_x: float = pixel_pos.x - (screen_size.x / 2.0)
  var centred_y: float = (screen_size.y / 2.0) - pixel_pos.y

  var feet_x := centred_x * PIXELS_TO_FEET
  var feet_y := centred_y * PIXELS_TO_FEET

  return Vector2(feet_x, feet_y)

func feet_to_pixel(feet_pos: Vector2) -> Vector2:
  var pixel_x: float = (feet_pos.x / PIXELS_TO_FEET) + (screen_size.x / 2.0)
  var pixel_y: float = (screen_size.y / 2.0) - (feet_pos.y / PIXELS_TO_FEET)

  return Vector2(pixel_x, pixel_y)

func update_properties_panel() -> void:
  var panel = get_node_or_null("PropertiesPanel")
  if panel:
    if selected_point_index != -1 and selected_point_index < point_data.size():
      var point = point_data[selected_point_index]
      var feet_pos = pixel_to_feet(point.position)
      panel.update_values(selected_point_index, feet_pos, point.heading, point.heading_visibility)
      panel.show()
    else:
      panel.hide()

func _on_position_changed(index: int, new_pos: Vector2) -> void:
  if index >= 0 and index < point_data.size():
    point_data[index].position = feet_to_pixel(new_pos)
    queue_redraw()

func _on_heading_changed(index: int, new_heading: float) -> void:
  if index >= 0 and index < point_data.size():
    point_data[index].heading = new_heading
    queue_redraw()

func _on_heading_visibility_changed(index: int, new_value: bool) -> void:
  if index >= 0 and index < point_data.size():
    point_data[index].heading_visibility = new_value
    queue_redraw()

func drag_point(index: int, mouse_pos: Vector2) -> void:
  if index < 0 or index >= point_data.size():
    return
    
  var field_start_x = (screen_size.x - FIELD_SIZE_PIXELS) / 2.0
  var field_end_x = field_start_x + FIELD_SIZE_PIXELS
  var field_start_y = (screen_size.y - FIELD_SIZE_PIXELS) / 2.0
  var field_end_y = field_start_y + FIELD_SIZE_PIXELS
  
  # Constrain to field boundaries
  mouse_pos.x = clamp(mouse_pos.x, field_start_x, field_end_x)
  mouse_pos.y = clamp(mouse_pos.y, field_start_y, field_end_y)
  
  var feet_pos := pixel_to_feet(mouse_pos)
  
  # Snap to grid if shift is pressed
  if Input.is_key_pressed(KEY_SHIFT):
    feet_pos = feet_pos.snapped(Vector2(0.25, 0.25))
    mouse_pos = feet_to_pixel(feet_pos)
  
  point_data[index].position = mouse_pos
  
  # Update properties panel with new position
  update_properties_panel()
  queue_redraw()
