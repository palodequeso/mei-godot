extends Node3D

# Scene templates
var SelectionMarkerScene = preload("res://scenes/objects/selection_marker.tscn")
var CrosshairScene = preload("res://scenes/objects/crosshair.tscn")

# Sub-scene references
@export var galaxy_scene: Node3D
@export var system_scene: Node3D
@export var camera: Camera3D

@export var galaxy_seed: int = 0

@export_group("HUD")
@export var x_position: Label
@export var y_position: Label
@export var z_position: Label
@export var fps_label: Label
@export var star_info_label: RichTextLabel
@export var flight_mode_button: CheckButton
@export var view_mode_label: Label
@export var fly_button: Button  # Toggles between "Fly to System" and "Back to Galaxy"
@export var seed_input: LineEdit
@export var velocity_slider: HSlider
@export var velocity_label: Label

@export_group("Goto Position")
@export var goto_button: Button
@export var x_input: LineEdit
@export var y_input: LineEdit
@export var z_input: LineEdit

@export_group("Nearest Stars")
@export var nearest_stars_panel: Panel
@export var nearest_star_list: VBoxContainer

@export_group("System View")
@export var system_objects_panel: Panel
@export var object_list: Tree
@export var selected_object_panel: Panel
@export var selected_object_info: Label
@export var fly_to_object_button: Button
@export var tooltip_label: Label

@export_group("Virtual Joysticks")
@export var move_panel: Panel
@export var rotate_panel: Panel

# Note: Star picking now uses fixed 50px threshold (matches mei-viewer)
@export var click_threshold: float = 0.5  # Deprecated - kept for VR ray picking only

# View state
var in_system_view: bool = false
var is_flying_to_star: bool = false  # True during fly-to animation
var is_flying_to_position: bool = false  # True during fly-to-position animation
var fly_to_tween: Tween = null
var selected_star: Dictionary = {}
var selected_system: Dictionary = {}
var selected_system_object: Dictionary = {}  # Currently selected object in system view
var system_objects: Array = []  # All selectable objects in system view

# Goto position state
var goto_edit_mode: bool = false

# Nearby stars state
var nearby_stars_data: Array = []  # Cached list of nearby stars with distances
var selected_nearby_star: Dictionary = {}  # Currently selected nearby star

# Flight controls
var mouse_motion: Vector2 = Vector2.ZERO
var is_mouse_looking: bool = false
const MOUSE_SENSITIVITY: float = 0.003
const VELOCITY_DAMPING: float = 0.9
const SHIFT_MULTIPLIER: float = 3.0

# Gamepad crosshair
var using_gamepad: bool = false
var crosshair: Control

# VR Mode
var vr_enabled: bool = false
var xr_interface: XRInterface
@export var xr_origin: XROrigin3D
@export var xr_camera: XRCamera3D
@export var left_controller: XRController3D
@export var right_controller: XRController3D
var vr_laser_dot: MeshInstance3D
var vr_hovered_star: Dictionary = {}
var vr_left_label: Label3D
var vr_right_label: Label3D

# VR 3D UI elements
var vr_menu: Node3D
var vr_buttons: Array = []

# Virtual joystick state (for Android touch)
var move_touch_index: int = -1
var rotate_touch_index: int = -1
var move_joystick_value: Vector2 = Vector2.ZERO
var rotate_joystick_value: Vector2 = Vector2.ZERO
var move_touch_start: Vector2 = Vector2.ZERO
var rotate_touch_start: Vector2 = Vector2.ZERO
const JOYSTICK_DEADZONE: float = 0.15
const JOYSTICK_MAX_DISTANCE: float = 40.0

# Camera state
var camera_velocity: Vector3 = Vector3.ZERO
var camera_speed: float = 1.0
var saved_galaxy_position: Vector3 = Vector3.ZERO  # Saved position when entering system view
var saved_galaxy_rotation: Basis = Basis.IDENTITY  # Saved rotation when entering system view

# Velocity scales
const GALACTIC_VELOCITY_MAX: float = 1000.0  # ly/s
const SYSTEM_VELOCITY_MAX: float = 10.0  # AU/s

# Debounce for nearby queries
var last_move_time: float = 0.0
const DEBOUNCE_DELAY: float = 0.3
var _nearby_stars_dirty: bool = true  # Flag to update list only once after stopping
var _last_camera_rotation: Quaternion = Quaternion.IDENTITY  # Track rotation for pick grid

# Debug visualization
var selection_marker: Node3D

func _ready():
    # Initialize galaxy seed
    galaxy_seed = 0
    
    # Connect UI signals (others are already connected in main.tscn)
    if seed_input:
        seed_input.text_submitted.connect(_on_seed_input_text_submitted)
    if fly_to_object_button:
        fly_to_object_button.pressed.connect(_on_fly_to_object_pressed)
        fly_to_object_button.disabled = true
    
    # Setup VR 3D menu
    _setup_vr_menu()
    
    _setup_vr()
    _setup_selection_marker()
    _setup_crosshair()
    _setup_velocity_controls()
    _setup_virtual_joysticks()
    if seed_input:
        seed_input.text = str(galaxy_seed)
    _start_galaxy_view()

func _setup_velocity_controls():
    if velocity_slider:
        # Use logarithmic scale: slider 0-100 maps to speed 0.001-100
        velocity_slider.min_value = 0
        velocity_slider.max_value = 100
        velocity_slider.step = 1
        velocity_slider.value = _speed_to_slider(camera_speed)
        # Note: value_changed already connected in main.tscn
    _update_velocity_label()

func _speed_to_slider(speed: float) -> float:
    # Convert speed (0.001 to 100) to slider value (0 to 100) using log scale
    var log_min = log(0.001)
    var log_max = log(100.0)
    var log_speed = log(clamp(speed, 0.001, 100.0))
    return ((log_speed - log_min) / (log_max - log_min)) * 100.0

func _slider_to_speed(slider_val: float) -> float:
    # Convert slider value (0 to 100) to speed (0.001 to 100) using log scale
    var log_min = log(0.001)
    var log_max = log(100.0)
    var t = slider_val / 100.0
    return exp(log_min + t * (log_max - log_min))

func _on_velocity_slider_changed(value: float):
    camera_speed = _slider_to_speed(value)
    _update_velocity_label()

func _update_velocity_label():
    if velocity_label:
        var display_speed: float
        var unit: String
        if in_system_view:
            # Convert visual units/s to AU/s
            const SYSTEM_SCALE = 1000.0  # Must match system.gd
            display_speed = camera_speed / SYSTEM_SCALE
            unit = "AU/s"
        else:
            display_speed = camera_speed
            unit = "ly/s"
        
        velocity_label.text = "Velocity: %.4f %s" % [display_speed, unit]
    if velocity_slider:
        velocity_slider.set_value_no_signal(_speed_to_slider(camera_speed))

func _setup_selection_marker():
    selection_marker = SelectionMarkerScene.instantiate()
    # The wireframe box is created by the selection_marker script
    add_child(selection_marker)

func _update_selection_marker_scale():
    # Scale marker to appear consistent size on screen regardless of distance
    if selection_marker == null or camera == null or not selection_marker.visible:
        return
    var dist = camera.global_position.distance_to(selection_marker.global_position)
    # Target ~20 pixels on screen - scale linearly with distance
    var scale_factor = dist * 0.02  # Adjust multiplier to taste
    scale_factor = clamp(scale_factor, 0.001, 1.0)  # Prevent too small or too large
    selection_marker.scale = Vector3.ONE * scale_factor

func _setup_vr():
    xr_interface = XRServer.find_interface("OpenXR")
    if xr_interface:
        print("OpenXR interface found")
    else:
        print("OpenXR interface not available - VR mode disabled")
    
    # Get laser dot and label references from controllers
    if right_controller:
        vr_laser_dot = right_controller.get_node_or_null("LaserDot")
        vr_right_label = right_controller.get_node_or_null("HelpLabel")
    if left_controller:
        vr_left_label = left_controller.get_node_or_null("HelpLabel")

func _update_vr_labels():
    if vr_left_label:
        if in_system_view:
            vr_left_label.text = "Movement:\n  Stick = Move\n  Grip = Speed Boost\n  Y = Back to Galaxy"
        else:
            vr_left_label.text = "Movement:\n  Stick = Move\n  Grip = Speed Boost\n  Y = Quit"
    
    if vr_right_label:
        if in_system_view:
            vr_right_label.text = "Selection:\n  Trigger = Select Object\n  A = Back to Galaxy\n  Stick = Turn"
        else:
            vr_right_label.text = "Selection:\n  Trigger = Select Star\n  A = Fly to System\n  Stick = Turn"

func _toggle_vr_mode():
    if xr_interface == null:
        print("Cannot toggle VR: OpenXR not available")
        return
    
    if xr_origin == null or xr_camera == null:
        print("Cannot toggle VR: XROrigin3D or XRCamera3D not configured in scene")
        return
    
    vr_enabled = not vr_enabled
    
    if vr_enabled:
        # Initialize XR
        if not xr_interface.is_initialized():
            if not xr_interface.initialize():
                print("Failed to initialize OpenXR")
                vr_enabled = false
                return
        
        # Position XR origin at current camera position
        xr_origin.global_position = camera.global_position
        xr_origin.global_rotation = camera.global_rotation
        
        # Enable XR on viewport and switch cameras
        get_viewport().use_xr = true
        xr_origin.visible = true
        xr_camera.current = true
        camera.current = false
        
        # Show VR 3D menu
        if vr_menu:
            vr_menu.visible = true
        # Hide flatscreen HUD in VR
        if camera and camera.has_node("HUD"):
            camera.get_node("HUD").visible = false
        print("VR mode enabled")
    else:
        # Hide VR menu
        if vr_menu:
            vr_menu.visible = false
        # Show flatscreen HUD
        if camera and camera.has_node("HUD"):
            camera.get_node("HUD").visible = true
        print("VR mode disabled")
        # Disable XR on viewport
        get_viewport().use_xr = false
        
        # Position regular camera at XR origin position
        camera.global_position = xr_origin.global_position
        camera.global_rotation = xr_origin.global_rotation
        
        # Switch back to regular camera
        camera.current = true
        xr_camera.current = false
        xr_origin.visible = false
        
        print("VR mode disabled")
    
    _update_view_mode_label()

func _handle_vr_input():
    if not vr_enabled or left_controller == null or right_controller == null:
        return
    
    # Check for trigger presses on either controller
    if left_controller.is_button_pressed("trigger_click") or right_controller.is_button_pressed("trigger_click"):
        # Use right controller position for selection in VR
        var controller = right_controller if right_controller.is_button_pressed("trigger_click") else left_controller
        
        # Check VR button interaction first
        if _handle_vr_button_interaction(controller):
            return  # Button was pressed, don't do star selection
        
        _handle_vr_selection(controller)
    
    # Handle thumbstick movement for navigation
    var left_stick = Vector2.ZERO
    var right_stick = Vector2.ZERO
    
    if left_controller.get_vector2("primary") != Vector2.ZERO:
        left_stick = left_controller.get_vector2("primary")
    
    if right_controller.get_vector2("primary") != Vector2.ZERO:
        right_stick = right_controller.get_vector2("primary")
    
    # Use left stick for movement, right stick for rotation
    _handle_vr_movement(left_stick, right_stick)
    
    # Handle other VR buttons
    if left_controller.is_button_pressed("grip_click") or right_controller.is_button_pressed("grip_click"):
        camera_speed = clamp(camera_speed * 1.3, 0.001, 100.0)
        _update_velocity_label()
    
    # Handle system navigation with A/X button
    if left_controller.is_button_pressed("primary_click") or right_controller.is_button_pressed("primary_click"):
        if not in_system_view:
            _fly_to_system()
        else:
            _exit_system_view()

func _handle_vr_selection(controller: XRController3D):
    if controller == null or galaxy_scene == null:
        return
    
    if in_system_view:
        # Handle system object selection - use ray from controller
        var ray_origin = controller.global_position
        var ray_dir = -controller.global_transform.basis.z
        var picked = system_scene.pick_object_at_ray(ray_origin, ray_dir) if system_scene else {}
        if not picked.is_empty():
            selected_system_object = picked
            system_scene.select_object(picked)
            _update_selected_object_info()
        return
    
    # Galaxy view - find star along controller ray
    var ray_origin = controller.global_position
    var ray_dir = -controller.global_transform.basis.z
    var star = galaxy_scene.find_star_along_ray(ray_origin, ray_dir, click_threshold)
    
    if star.is_empty():
        print("No star found along ray")
        return
    
    selected_star = star
    
    # Update selection marker
    var pos = selected_star.get("position", {})
    var galaxy_scale = galaxy_scene.galaxy_scale
    var star_world_pos = Vector3(
        pos.get("x", 0.0) * galaxy_scale,
        pos.get("y", 0.0) * galaxy_scale,
        pos.get("z", 0.0) * galaxy_scale
    )
    selection_marker.global_position = star_world_pos
    selection_marker.visible = true
    _update_selection_marker_scale()
    
    # Position laser dot at star
    if vr_laser_dot:
        vr_laser_dot.global_position = star_world_pos
    
    # Query system data
    var star_id = str(selected_star.get("id", "0"))
    selected_system = galaxy_scene.get_star_system(star_id)
    
    _update_view_mode_label()
    print("VR selected star: ", star_id)

func _handle_vr_movement(left_stick: Vector2, right_stick: Vector2):
    if not vr_enabled or xr_camera == null:
        return
    
    var delta = get_process_delta_time()
    
    # Movement using left stick
    var move_input = Vector3(left_stick.x, 0, -left_stick.y)
    if move_input.length() > 0.1:  # Deadzone
        var camera_basis = xr_camera.global_transform.basis
        var movement = camera_basis * move_input * camera_speed * delta * 10.0
        xr_origin.global_position += movement
    
    # Rotation using right stick (snap turning to avoid motion sickness)
    if right_stick.length() > 0.1:  # Deadzone
        var rotation_speed = 2.0
        var yaw = -right_stick.x * rotation_speed * delta
        # Apply rotation to XR origin
        xr_origin.rotate_y(yaw)

func _get_active_camera() -> Camera3D:
    if vr_enabled and xr_camera:
        return xr_camera
    return camera

func _setup_crosshair():
    crosshair = CrosshairScene.instantiate()
    # Add to HUD if camera exists, otherwise to self
    if camera and camera.has_node("HUD"):
        camera.get_node("HUD").add_child(crosshair)
    else:
        add_child(crosshair)

func _setup_virtual_joysticks():
    # Show virtual joystick panels on mobile devices (Android/iOS)
    var is_mobile = OS.get_name() in ["Android", "iOS"]
    
    if is_mobile and not vr_enabled:
        if move_panel:
            move_panel.visible = true
        if rotate_panel:
            rotate_panel.visible = true
        print("Virtual joysticks enabled for mobile")
    else:
        if move_panel:
            move_panel.visible = false
        if rotate_panel:
            rotate_panel.visible = false

func _setup_vr_menu():
    """Create 3D VR menu with simple 3D buttons"""
    if not left_controller:
        return
    
    # Create menu container
    vr_menu = Node3D.new()
    vr_menu.name = "VRMenu"
    left_controller.add_child(vr_menu)
    
    # Position menu in front of left hand (like a wrist menu)
    vr_menu.position = Vector3(0, 0.05, -0.15)
    vr_menu.rotation_degrees = Vector3(-30, 0, 0)
    
    # Create simple 3D buttons
    _create_vr_button(vr_menu, "System", Vector3(0, 0, 0), Color.CYAN)
    _create_vr_button(vr_menu, "Galaxy", Vector3(0, -0.06, 0), Color.ORANGE)
    
    vr_menu.visible = false
    print("VR 3D menu setup complete")

func _create_vr_button(parent: Node3D, label_text: String, pos: Vector3, color: Color):
    """Create a simple 3D button with mesh and label"""
    var button_node = Node3D.new()
    button_node.name = label_text + "Button"
    button_node.position = pos
    parent.add_child(button_node)
    
    # Create button mesh (small box)
    var mesh_instance = MeshInstance3D.new()
    var box_mesh = BoxMesh.new()
    box_mesh.size = Vector3(0.08, 0.04, 0.01)
    mesh_instance.mesh = box_mesh
    
    var mat = StandardMaterial3D.new()
    mat.albedo_color = color
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mesh_instance.material_override = mat
    button_node.add_child(mesh_instance)
    
    # Create label
    var label = Label3D.new()
    label.text = label_text
    label.pixel_size = 0.001
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.position = Vector3(0, 0, 0.01)
    label.modulate = Color.WHITE
    button_node.add_child(label)
    
    # Store button reference
    vr_buttons.append({"node": button_node, "action": label_text, "mesh": mesh_instance})
    
    print("Created VR button: ", label_text)

func _handle_vr_button_interaction(controller: XRController3D) -> bool:
    """Check if controller laser is pointing at a VR button"""
    if not vr_menu or not vr_menu.visible:
        return false
    
    var controller_pos = controller.global_position
    var controller_forward = -controller.global_transform.basis.z
    
    # Check each button
    for button_data in vr_buttons:
        var button_node = button_data["node"]
        var button_pos = button_node.global_position
        
        # Calculate distance and direction to button
        var to_button = button_pos - controller_pos
        var distance = to_button.length()
        var direction = to_button.normalized()
        
        # Check if pointing at button (dot product for angle check)
        var dot = controller_forward.dot(direction)
        
        # If within range and pointing at it
        if distance < 0.5 and dot > 0.9:  # Within 50cm and pointing directly
            # Execute button action
            _execute_vr_button_action(button_data["action"])
            print("VR button pressed: ", button_data["action"])
            return true
    
    return false

func _execute_vr_button_action(action: String):
    """Execute the action for a VR button"""
    match action:
        "System":
            if not in_system_view and selected_star.size() > 0:
                _fly_to_system()
        "Galaxy":
            if in_system_view:
                _exit_system_view()

func _start_galaxy_view():
    in_system_view = false
    
    # Show galaxy, hide system
    if galaxy_scene:
        galaxy_scene.visible = true
        await galaxy_scene.initialize(galaxy_seed)
    if system_scene:
        system_scene.visible = false
    
    # Update UI
    _update_view_mode_label()
    
    # Reset camera to view galaxy
    if camera:
        camera.global_position = Vector3(0, 0, 25)
        camera.look_at(Vector3.ZERO, Vector3.UP)
    
    # Query nearby stars at camera position after a short delay
    await get_tree().process_frame
    if galaxy_scene:
        galaxy_scene.update_nearby_stars(camera.global_position, true)
        galaxy_scene.rebuild_pick_grid(camera)
        await get_tree().create_timer(0.1).timeout
        _update_nearest_stars_list()
    
    camera_speed = 1.0  # Default galaxy speed

func _regenerate_galaxy():
    # Clear selection state
    selected_star = {}
    selected_system = {}
    
    # Reinitialize with new seed
    if galaxy_scene:
        galaxy_scene.reinitialize(galaxy_seed)
    
    # Reset camera
    if camera:
        camera.global_position = Vector3(0, 0, 25)
        camera.look_at(Vector3.ZERO, Vector3.UP)
    
    # Update nearby stars
    await get_tree().process_frame
    if galaxy_scene:
        galaxy_scene.update_nearby_stars(camera.global_position, true)
        galaxy_scene.rebuild_pick_grid(camera)
        await get_tree().create_timer(0.1).timeout
        _update_nearest_stars_list()
    
    _update_view_mode_label()
    if star_info_label:
        star_info_label.text = "[center][color=#888888]No star selected[/color][/center]"

func _fly_to_system():
    if selected_star.is_empty() or selected_system.is_empty():
        print("No star selected")
        return
    
    if is_flying_to_star:
        return  # Already flying
    
    # Save current galaxy position before flying
    if camera:
        saved_galaxy_position = camera.global_position
        saved_galaxy_rotation = camera.global_transform.basis
        print("Saved galaxy position before flying: ", saved_galaxy_position)
        print("Saved galaxy rotation: ", saved_galaxy_rotation.get_euler())
    
    # Calculate target position (the selected star in visual coordinates)
    var star_pos = selected_star.get("position", {})
    var galaxy_scale = galaxy_scene.galaxy_scale if galaxy_scene else 0.001
    var target_pos = Vector3(
        star_pos.get("x", 0.0) * galaxy_scale,
        star_pos.get("y", 0.0) * galaxy_scale,
        star_pos.get("z", 0.0) * galaxy_scale
    )
    
    # Start fly-to animation
    is_flying_to_star = true
    _update_view_mode_label()
    
    # Cancel any existing tween
    if fly_to_tween and fly_to_tween.is_valid():
        fly_to_tween.kill()
    
    # Calculate flight duration based on distance (faster for longer distances)
    var distance = camera.global_position.distance_to(target_pos)
    var flight_duration = clamp(distance * 0.5, 0.5, 3.0)  # 0.5-3 seconds
    
    # Create tween for smooth flight
    fly_to_tween = create_tween()
    fly_to_tween.set_trans(Tween.TRANS_QUAD)
    fly_to_tween.set_ease(Tween.EASE_IN_OUT)
    
    # Animate camera position towards star
    fly_to_tween.tween_property(camera, "global_position", target_pos, flight_duration)
    
    # Make camera look at target during flight
    fly_to_tween.parallel().tween_method(_look_at_target.bind(target_pos), 0.0, 1.0, flight_duration)
    
    # When animation completes, switch to system view
    fly_to_tween.tween_callback(_complete_fly_to_system)
    
    print("Flying to star system... (", flight_duration, "s)")

func _look_at_target(_progress: float, target: Vector3):
    if camera:
        var direction = (target - camera.global_position).normalized()
        if direction.length() > 0.001:
            camera.look_at(target, Vector3.UP)

func _complete_fly_to_system():
    is_flying_to_star = false
    
    # Force update nearby stars at selected star's position before transitioning
    if galaxy_scene and camera:
        var star_pos = selected_star.get("position", {})
        var star_visual_pos = Vector3(
            star_pos.get("x", 0.0) * galaxy_scene.galaxy_scale,
            star_pos.get("y", 0.0) * galaxy_scene.galaxy_scale,
            star_pos.get("z", 0.0) * galaxy_scene.galaxy_scale
        )
        galaxy_scene.update_nearby_stars(star_visual_pos, true)
    
    in_system_view = true
    
    # Hide galaxy, show system
    if galaxy_scene:
        galaxy_scene.visible = false
    if system_scene:
        system_scene.visible = true
        # Set camera reference so distant stars can follow it
        system_scene.set_camera(camera)
        # Pass nearby stars from galaxy for distant star rendering
        var nearby = galaxy_scene.current_nearby_stars if galaxy_scene else {}
        var nearby_count = nearby.get("count", 0) if nearby else 0
        print("Passing ", nearby_count, " nearby stars to system scene")
        system_scene.load_system(selected_system, selected_star, nearby)
    
    # Position camera in system view
    if camera and system_scene:
        var cam_pos = system_scene.get_recommended_camera_position()
        camera.global_position = cam_pos
        camera.look_at(Vector3.ZERO, Vector3.UP)
    
    # Speed for system exploration at 1000x visual scale
    # Objects are now 1-10 visual units, orbits are 500-5000 units
    camera_speed = 50.0  # visual units/s - good for exploring system
    
    # Populate the system objects list
    _populate_system_objects_list()
    
    _update_view_mode_label()
    _update_velocity_label()
    _update_vr_labels()
    _update_nearby_panels_visibility()  # Hide nearest stars panel in system view
    print("Entered system view")

func _exit_system_view():
    if not in_system_view:
        return
    
    in_system_view = false
    
    # Show galaxy at the star's position
    if galaxy_scene:
        galaxy_scene.visible = true
    if system_scene:
        system_scene.visible = false
    
    camera_speed = 1.0
    _nearby_stars_dirty = true  # Trigger update of nearby stars
    _update_view_mode_label()
    _update_velocity_label()
    _update_vr_labels()
    _update_nearby_panels_visibility()  # Show nearest stars panel in galaxy view
    
    # Restore camera to saved galaxy position (after other updates)
    if camera:
        print("Restoring galaxy position: ", saved_galaxy_position)
        print("Restoring galaxy rotation: ", saved_galaxy_rotation.get_euler())
        camera.global_position = saved_galaxy_position
        camera.global_transform.basis = saved_galaxy_rotation
        
        # Reset saved position so it can be saved again for next star selection
        saved_galaxy_position = Vector3.ZERO
        saved_galaxy_rotation = Basis.IDENTITY
    
    print("Exited to galaxy view")

func _update_view_mode_label():
    if view_mode_label:
        var vr_suffix = " [VR]" if vr_enabled else ""
        if is_flying_to_star:
            view_mode_label.text = "Flying to Star..." + vr_suffix
        elif is_flying_to_position:
            view_mode_label.text = "Flying to Position..." + vr_suffix
        elif in_system_view:
            view_mode_label.text = "System View" + vr_suffix
        else:
            view_mode_label.text = "Galaxy View" + vr_suffix
    if fly_button:
        if is_flying_to_star:
            fly_button.text = "Flying..."
            fly_button.disabled = true
        elif in_system_view:
            fly_button.text = "Back to Galaxy"
            fly_button.disabled = false
        else:
            fly_button.text = "Fly to System" if not selected_star.is_empty() else "Select a Star"
            fly_button.disabled = selected_star.is_empty()
    if system_objects_panel:
        system_objects_panel.visible = in_system_view
    if selected_object_panel:
        selected_object_panel.visible = in_system_view

func _populate_system_objects_list():
    if object_list == null:
        return
    
    # Clear existing items and create root
    object_list.clear()
    var root = object_list.create_item()
    
    # Connect item selection signal if not already connected
    if not object_list.item_selected.is_connected(_on_tree_item_selected):
        object_list.item_selected.connect(_on_tree_item_selected)
    
    system_objects.clear()
    
    var stars = selected_system.get("stars", [])
    var components = selected_system.get("stellar_components", [])
    
    # Track global planet index for navigation
    var global_planet_idx = 0
    
    # If we have stellar components, use hierarchical view
    if components.size() > 0:
        for comp_idx in range(components.size()):
            var component = components[comp_idx]
            var star_indices = component.get("star_indices", [])
            
            # Determine component name
            var comp_name = ""
            var comp_stars = []
            for star_idx in star_indices:
                if star_idx < stars.size():
                    comp_stars.append(stars[star_idx])
            
            if comp_stars.size() == 1:
                comp_name = comp_stars[0].get("star_type", "Star")
            elif comp_stars.size() == 2:
                comp_name = comp_stars[0].get("star_type", "Star") + " + " + comp_stars[1].get("star_type", "Star")
            else:
                comp_name = "Component " + str(comp_idx + 1)
            
            # Create component tree item
            var comp_item = object_list.create_item(root)
            comp_item.set_text(0, "⭐ " + comp_name)
            comp_item.collapsed = true  # Start collapsed
            
            # Add individual stars as child items
            for i in range(star_indices.size()):
                var star_idx = star_indices[i]
                if star_idx < stars.size():
                    var star = stars[star_idx]
                    var obj = {"type": "Star", "index": star_idx, "data": star}
                    system_objects.append(obj)
                    
                    var star_item = object_list.create_item(comp_item)
                    star_item.set_text(0, "⭐ " + star.get("star_type", "Star"))
                    star_item.set_metadata(0, obj)
            
            # Add planets for this component
            var inner_planets = component.get("inner_planets", [])
            var outer_planets = component.get("outer_planets", [])
            var comp_planets = inner_planets + outer_planets
            
            for p_idx in range(comp_planets.size()):
                var planet = comp_planets[p_idx]
                var obj = {"type": "Planet", "index": global_planet_idx, "data": planet, "component": comp_idx}
                system_objects.append(obj)
                
                var planet_name = planet.get("planet_type", "Planet") + " " + str(p_idx + 1)
                var moons = planet.get("moons", [])
                
                var planet_item = object_list.create_item(comp_item)
                if moons.size() > 0:
                    planet_item.set_text(0, "🪐 " + planet_name + " (" + str(moons.size()) + " moons)")
                else:
                    planet_item.set_text(0, "🪐 " + planet_name)
                planet_item.set_metadata(0, obj)
                planet_item.collapsed = true
                
                # Add moons as children of planet
                for m_idx in range(moons.size()):
                    var moon = moons[m_idx]
                    var moon_obj = {"type": "Moon", "planet_index": global_planet_idx, "index": m_idx, "data": moon}
                    system_objects.append(moon_obj)
                    
                    var moon_item = object_list.create_item(planet_item)
                    moon_item.set_text(0, "🌙 Moon " + str(m_idx + 1))
                    moon_item.set_metadata(0, moon_obj)
                
                global_planet_idx += 1
        
        # Add asteroid belts at system level
        var belts = selected_system.get("asteroid_belts", [])
        if belts.size() > 0:
            var belts_item = object_list.create_item(root)
            belts_item.set_text(0, "💫 Asteroid Belts (" + str(belts.size()) + ")")
            belts_item.collapsed = true
            
            for i in range(belts.size()):
                var belt = belts[i]
                var obj = {"type": "AsteroidBelt", "index": i, "data": belt}
                system_objects.append(obj)
                
                var belt_item = object_list.create_item(belts_item)
                belt_item.set_text(0, "💫 " + belt.get("name", "Belt " + str(i + 1)))
                belt_item.set_metadata(0, obj)
    else:
        # Fallback: legacy flat list for systems without stellar_components
        _populate_legacy_objects_list(root, stars)

func _populate_legacy_objects_list(root: TreeItem, stars: Array):
    """Fallback for systems without stellar_components data"""
    for i in range(stars.size()):
        var star = stars[i]
        var obj = {"type": "Star", "index": i, "data": star}
        system_objects.append(obj)
        
        var item = object_list.create_item(root)
        item.set_text(0, "⭐ " + star.get("star_type", "Star"))
        item.set_metadata(0, obj)
    
    var inner = selected_system.get("inner_planets", [])
    var outer = selected_system.get("outer_planets", [])
    var all_planets = inner + outer
    for i in range(all_planets.size()):
        var planet = all_planets[i]
        var obj = {"type": "Planet", "index": i, "data": planet}
        system_objects.append(obj)
        
        var planet_name = planet.get("planet_type", "Planet") + " " + str(i + 1)
        var moons = planet.get("moons", [])
        
        var planet_item = object_list.create_item(root)
        if moons.size() > 0:
            planet_item.set_text(0, "🪐 " + planet_name + " (" + str(moons.size()) + " moons)")
        else:
            planet_item.set_text(0, "🪐 " + planet_name)
        planet_item.set_metadata(0, obj)
        planet_item.collapsed = true
        
        for j in range(moons.size()):
            var moon = moons[j]
            var moon_obj = {"type": "Moon", "planet_index": i, "index": j, "data": moon}
            system_objects.append(moon_obj)
            
            var moon_item = object_list.create_item(planet_item)
            moon_item.set_text(0, "🌙 Moon " + str(j + 1))
            moon_item.set_metadata(0, moon_obj)
    
    var belts = selected_system.get("asteroid_belts", [])
    for i in range(belts.size()):
        var belt = belts[i]
        var obj = {"type": "AsteroidBelt", "index": i, "data": belt}
        system_objects.append(obj)
        
        var item = object_list.create_item(root)
        item.set_text(0, "💫 " + belt.get("name", "Belt"))
        item.set_metadata(0, obj)

func _on_tree_item_selected():
    var selected = object_list.get_selected()
    if selected == null:
        return
    
    var obj_data = selected.get_metadata(0)
    if obj_data == null or not obj_data is Dictionary:
        return
    
    _on_system_object_selected(obj_data)

func _on_system_object_selected(obj_data: Dictionary):
    selected_system_object = obj_data
    # Find the pickable object to get position for selection marker
    if system_scene:
        for obj in system_scene.pickable_objects:
            var type_match = obj.get("type") == obj_data.get("type")
            var index_match = obj.get("index") == obj_data.get("index")
            
            # For moons, also check planet_index to avoid matching wrong moon
            if obj_data.get("type") == "Moon":
                var planet_match = obj.get("planet_index") == obj_data.get("planet_index")
                if type_match and index_match and planet_match:
                    system_scene.select_object(obj)
                    break
            elif type_match and index_match:
                system_scene.select_object(obj)
                break
    _update_selected_object_info()
    # Enable fly-to button when object is selected
    if fly_to_object_button:
        fly_to_object_button.disabled = obj_data.is_empty()

func _on_fly_to_object_pressed():
    if selected_system_object.is_empty() or camera == null:
        return
    
    # Find the object's position and size
    var target_pos = Vector3.ZERO
    var target_size = 1.0
    
    if system_scene:
        for obj in system_scene.pickable_objects:
            var type_match = obj.get("type") == selected_system_object.get("type")
            var index_match = obj.get("index") == selected_system_object.get("index")
            
            # For moons, also check planet_index to avoid matching wrong moon
            if selected_system_object.get("type") == "Moon":
                var planet_match = obj.get("planet_index") == selected_system_object.get("planet_index")
                if type_match and index_match and planet_match:
                    target_pos = obj.get("position", Vector3.ZERO)
                    target_size = obj.get("radius", 0.5) * 2.0
                    break
            elif type_match and index_match:
                target_pos = obj.get("position", Vector3.ZERO)
                target_size = obj.get("radius", 0.5) * 2.0
                break
    
    # Position camera at a distance where the object fills ~30% of view
    # Distance = size / (2 * tan(fov/2) * fill_fraction)
    var fov_rad = deg_to_rad(camera.fov)
    var view_distance = target_size / (2.0 * tan(fov_rad / 2.0) * 0.3)
    view_distance = max(view_distance, target_size * 3.0)  # At least 3x object size away
    
    # Calculate camera position offset from target
    var cam_offset = (camera.global_position - target_pos).normalized()
    if cam_offset.length() < 0.1:
        cam_offset = Vector3(0, 0.3, 1).normalized()
    
    var final_pos = target_pos + cam_offset * view_distance
    
    # Animate the camera to the target
    _fly_camera_to_object(final_pos, target_pos)

func _fly_camera_to_object(target_pos: Vector3, look_at_pos: Vector3):
    if fly_to_tween and fly_to_tween.is_valid():
        fly_to_tween.kill()
    
    var distance = camera.global_position.distance_to(target_pos)
    var duration = clamp(distance / 500.0, 0.5, 3.0)  # Faster for shorter distances
    
    fly_to_tween = create_tween()
    fly_to_tween.set_parallel(true)
    fly_to_tween.tween_property(camera, "global_position", target_pos, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
    fly_to_tween.set_parallel(false)
    fly_to_tween.tween_callback(func(): camera.look_at(look_at_pos, Vector3.UP))

func _update_selected_object_info():
    if selected_object_info == null:
        return
    
    var obj = selected_system_object
    if obj.is_empty():
        selected_object_info.text = "Select an object"
        return
    
    var info = ""
    var data = obj.get("data", {})
    var obj_type = obj.get("type", "Unknown")
    
    match obj_type:
        "Star":
            info = "★ STAR ★\n"
            info += "Type: " + str(data.get("star_type", "Unknown")) + "\n"
            info += "Temp: " + str(int(data.get("temperature", 0))) + " K\n"
            info += "Mass: " + str(snapped(data.get("mass", 0), 0.01)) + " M☉\n"
            info += "Luminosity: " + str(snapped(data.get("luminosity", 0), 0.01))
        "Planet":
            info = "● PLANET ●\n"
            info += "Type: " + str(data.get("planet_type", "Unknown")) + "\n"
            info += "Orbit: " + str(snapped(data.get("orbital_radius", 0), 0.01)) + " AU\n"
            info += "Mass: " + str(snapped(data.get("mass", 0), 0.01)) + " M⊕\n"
            info += "Moons: " + str(data.get("moon_count", 0))
        "Moon":
            info = "◐ MOON ◐\n"
            info += "Type: " + str(data.get("moon_type", "Unknown")) + "\n"
            info += "Orbit: " + str(snapped(data.get("orbital_radius", 0), 0.01)) + " km\n"
            info += "Mass: " + str(snapped(data.get("mass", 0), 0.0001))
        "AsteroidBelt":
            info = "✦ ASTEROID BELT ✦\n"
            info += "Name: " + str(data.get("name", "Belt")) + "\n"
            info += "Inner: " + str(snapped(data.get("inner_radius", 0), 0.01)) + " AU\n"
            info += "Outer: " + str(snapped(data.get("outer_radius", 0), 0.01)) + " AU\n"
            info += "Bodies: " + str(data.get("asteroid_count", 0))
    
    selected_object_info.text = info

func _process(delta: float):
    _update_flight_controls(delta)
    
    if vr_enabled:
        _handle_vr_input()
    
    if not in_system_view and galaxy_scene:
        galaxy_scene.update_rotation(delta)
        _maybe_update_nearby_stars()
        _update_selection_marker_scale()  # Keep marker size consistent as camera moves
    
    if in_system_view:
        _update_system_tooltip()
    
    _update_hud(delta)

func _maybe_update_nearby_stars():
    if galaxy_scene == null or camera == null:
        return
    
    # Skip updates during fly-to animation
    if is_flying_to_star or is_flying_to_position:
        return
    
    # Check for both position and rotation changes
    var is_moving = camera_velocity.length() > 0.01
    var current_rotation = camera.global_transform.basis.get_rotation_quaternion()
    var rotation_changed = not current_rotation.is_equal_approx(_last_camera_rotation)
    
    if is_moving or rotation_changed:
        last_move_time = Time.get_ticks_msec() / 1000.0
        _nearby_stars_dirty = true  # Mark for update when we stop
        _last_camera_rotation = current_rotation
        galaxy_scene.invalidate_pick_grid()  # Invalidate pick grid while moving/rotating
    else:
        var time_since_move = Time.get_ticks_msec() / 1000.0 - last_move_time
        # Only update nearby stars when in galaxy view (not system view)
        if time_since_move > DEBOUNCE_DELAY and _nearby_stars_dirty and not in_system_view:
            galaxy_scene.update_nearby_stars(camera.global_position)
            galaxy_scene.rebuild_pick_grid(camera)  # Rebuild pick grid when stopped
            _update_nearest_stars_list()
            _nearby_stars_dirty = false  # Only update once after stopping

func _update_hud(delta: float):
    if camera == null:
        return
    
    var cam_pos = camera.global_position
    
    if in_system_view:
        # System view: positions in AU (visual coords / SYSTEM_SCALE)
        const SYSTEM_SCALE = 1000.0  # Must match system.gd
        var pos_au = cam_pos / SYSTEM_SCALE
        x_position.text = "%.4f AU" % pos_au.x
        y_position.text = "%.4f AU" % pos_au.y
        z_position.text = "%.4f AU" % pos_au.z
    else:
        # Galaxy view: positions in light years
        var galaxy_scale = galaxy_scene.galaxy_scale if galaxy_scene else 0.001
        var pos_ly = cam_pos / galaxy_scale
        x_position.text = "%.4f ly" % pos_ly.x
        y_position.text = "%.4f ly" % pos_ly.y
        z_position.text = "%.4f ly" % pos_ly.z
    
    if fps_label:
        fps_label.text = "%.0f FPS" % (1.0 / delta)

func _is_mouse_over_ui() -> bool:
    # Check if mouse is over any visible UI panel that should block clicks
    var mouse_pos = get_viewport().get_mouse_position()
    
    # Get the HUD node
    var hud = camera.get_node_or_null("HUD") if camera else null
    if hud == null:
        return false
    
    # Check all panels and containers that should block clicks
    for child in hud.get_children():
        if child is Control and child.visible:
            var rect = child.get_global_rect()
            if rect.has_point(mouse_pos):
                return true
    return false

func _update_flight_controls(delta: float):
    if camera == null:
        return
    
    # Disable manual controls during fly-to animation
    if is_flying_to_star:
        return
    
    # In VR mode, we move the XR origin; otherwise move the camera
    var move_node: Node3D
    if vr_enabled and xr_origin:
        move_node = xr_origin
    else:
        move_node = camera
    var look_cam: Camera3D = _get_active_camera()
    
    # Movement input from project actions
    var input_dir = Vector3.ZERO
    if Input.is_action_pressed("move_forward"): input_dir.z += 1.0
    if Input.is_action_pressed("move_backward"): input_dir.z -= 1.0
    if Input.is_action_pressed("move_left"): input_dir.x -= 1.0
    if Input.is_action_pressed("move_right"): input_dir.x += 1.0
    if Input.is_action_pressed("move_up"): input_dir.y += 1.0
    if Input.is_action_pressed("move_down"): input_dir.y -= 1.0
    
    # Add virtual joystick input (Android touch controls)
    if move_joystick_value.length() > 0:
        input_dir.x += move_joystick_value.x
        input_dir.z -= move_joystick_value.y  # Y axis is inverted (up is negative Z)
    
    # Rotation input from project actions (for controller right stick)
    var rot_input = Vector2.ZERO
    if Input.is_action_pressed("rotate_left"): rot_input.x -= 1.0
    if Input.is_action_pressed("rotate_right"): rot_input.x += 1.0
    if Input.is_action_pressed("rotate_up"): rot_input.y -= 1.0
    if Input.is_action_pressed("rotate_down"): rot_input.y += 1.0
    
    # Add virtual joystick rotation input (Android touch controls)
    if rotate_joystick_value.length() > 0:
        rot_input += rotate_joystick_value
    
    var speed_mult = SHIFT_MULTIPLIER if Input.is_key_pressed(KEY_SHIFT) else 1.0
    
    if input_dir.length() > 0.0:
        input_dir = input_dir.normalized()
        var forward = -look_cam.global_transform.basis.z
        var right = look_cam.global_transform.basis.x
        var up = look_cam.global_transform.basis.y
        camera_velocity = (forward * input_dir.z + right * input_dir.x + up * input_dir.y) * camera_speed * speed_mult
    else:
        camera_velocity *= VELOCITY_DAMPING
    
    move_node.global_position += camera_velocity * delta
    
    # Camera rotation from mouse or controller
    var yaw = 0.0
    var pitch = 0.0
    var roll = 0.0
    
    if is_mouse_looking and mouse_motion.length() > 0:
        yaw = -mouse_motion.x * MOUSE_SENSITIVITY
        pitch = -mouse_motion.y * MOUSE_SENSITIVITY
        mouse_motion = Vector2.ZERO
    elif rot_input.length() > 0:
        yaw = -rot_input.x * delta * 2.0
        pitch = -rot_input.y * delta * 2.0
    
    # Roll input (Q/E or controller bumpers)
    if Input.is_action_pressed("roll_left"): roll += delta * 2.0
    if Input.is_action_pressed("roll_right"): roll -= delta * 2.0
    
    if yaw != 0.0 or pitch != 0.0 or roll != 0.0:
        if vr_enabled and xr_origin:
            # In VR: only apply yaw to XR origin for snap-turning
            # Pitch and roll are controlled by the headset
            if yaw != 0.0:
                xr_origin.rotate_y(yaw)
        else:
            # FPS-style rotation that prevents accidental roll:
            # - Yaw rotates around world Y axis (keeps horizon level)
            # - Pitch rotates around camera's local X axis
            # - Roll rotates around camera's local Z axis (manual control only)
            
            # Yaw around world up (prevents roll)
            var yaw_quat = Quaternion(Vector3.UP, yaw)
            
            # Apply yaw first, then pitch
            var new_quat = yaw_quat * camera.global_transform.basis.get_rotation_quaternion()
            new_quat = Quaternion(Basis(new_quat).x, pitch) * new_quat
            
            # Apply roll around local forward axis
            if roll != 0.0:
                new_quat = Quaternion(Basis(new_quat).z, roll) * new_quat
            
            camera.global_transform.basis = Basis(new_quat)

func _input(event: InputEvent):
    # Handle VR input first
    if vr_enabled:
        _handle_vr_input()
        return
    
    # Handle touch input for virtual joysticks
    if event is InputEventScreenTouch or event is InputEventScreenDrag:
        _handle_touch_input(event)
        return
    
    # Detect input device switching
    if event is InputEventJoypadButton or event is InputEventJoypadMotion:
        if not using_gamepad:
            using_gamepad = true
            _update_crosshair_visibility()
    elif event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventKey:
        if using_gamepad:
            using_gamepad = false
            _update_crosshair_visibility()
    
    if event is InputEventMouseButton:
        var mb = event as InputEventMouseButton
        
        # Right click - mouse look
        if mb.button_index == MOUSE_BUTTON_RIGHT:
            is_mouse_looking = mb.pressed
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE)
    
    if event is InputEventMouseMotion:
        var motion = event as InputEventMouseMotion
        mouse_motion = motion.relative
        # Alt + mouse motion also enables mouse looking (laptop-friendly)
        if Input.is_key_pressed(KEY_ALT):
            is_mouse_looking = true
    
    # Release mouse look when Alt is released
    if event is InputEventKey:
        var key = event as InputEventKey
        if key.keycode == KEY_ALT and not key.pressed:
            if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
                is_mouse_looking = false
    
    # Use project input actions for commands
    if Input.is_action_just_pressed("select"):
        if not (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
            # Don't handle clicks if mouse is over UI elements
            if _is_mouse_over_ui():
                return
            var select_pos = _get_selection_screen_pos()
            if in_system_view:
                _handle_system_object_click(select_pos)
            else:
                _handle_star_click(select_pos)
    
    if Input.is_action_just_pressed("increase_velocity") and not _is_mouse_over_ui():
        camera_speed = clamp(camera_speed * 1.3, 0.001, 100.0)
        _update_velocity_label()
    
    if Input.is_action_just_pressed("decrease_velocity") and not _is_mouse_over_ui():
        camera_speed = clamp(camera_speed / 1.3, 0.001, 100.0)
        _update_velocity_label()
    
    if Input.is_action_just_pressed("load_system"):
        if not in_system_view:
            _fly_to_system()
    
    if Input.is_action_just_pressed("back_to_galaxy_map"):
        if in_system_view:
            _exit_system_view()
    
    if Input.is_action_just_pressed("quit"):
        if in_system_view:
            _exit_system_view()
        else:
            get_tree().quit()
    
    # F11 - Toggle fullscreen
    if event is InputEventKey:
        var key = event as InputEventKey
        if key.pressed and not key.echo and key.keycode == KEY_F11:
            var mode = get_window().mode
            if mode == Window.MODE_FULLSCREEN:
                get_window().mode = Window.MODE_WINDOWED
            else:
                get_window().mode = Window.MODE_FULLSCREEN
    
    # Debug toggles (keeping these as hardcoded keys for now)
    if event is InputEventKey:
        var key = event as InputEventKey
        if key.pressed and not key.echo:
            match key.keycode:
                KEY_R:  # Toggle galaxy rotation
                    if galaxy_scene and not in_system_view:
                        galaxy_scene.rotation_enabled = not galaxy_scene.rotation_enabled
                KEY_G:  # Toggle galactic stars
                    if galaxy_scene and not in_system_view:
                        galaxy_scene.star_points.visible = not galaxy_scene.star_points.visible
                KEY_N:  # Toggle nearby stars
                    if galaxy_scene and not in_system_view:
                        galaxy_scene.nearby_stars.visible = not galaxy_scene.nearby_stars.visible
                KEY_V:  # Toggle VR mode
                    _toggle_vr_mode()

func _handle_touch_input(event: InputEvent):
    if not move_panel or not rotate_panel:
        return
    
    if event is InputEventScreenTouch:
        var touch = event as InputEventScreenTouch
        var touch_pos = touch.position
        
        if touch.pressed:
            # Touch started - check which joystick area
            if _is_point_in_control(touch_pos, move_panel) and move_touch_index == -1:
                move_touch_index = touch.index
                move_touch_start = touch_pos
                move_joystick_value = Vector2.ZERO
            elif _is_point_in_control(touch_pos, rotate_panel) and rotate_touch_index == -1:
                rotate_touch_index = touch.index
                rotate_touch_start = touch_pos
                rotate_joystick_value = Vector2.ZERO
        else:
            # Touch ended - release joystick
            if touch.index == move_touch_index:
                move_touch_index = -1
                move_joystick_value = Vector2.ZERO
            elif touch.index == rotate_touch_index:
                rotate_touch_index = -1
                rotate_joystick_value = Vector2.ZERO
    
    elif event is InputEventScreenDrag:
        var drag = event as InputEventScreenDrag
        var touch_pos = drag.position
        
        # Update joystick values based on drag
        if drag.index == move_touch_index:
            var offset = touch_pos - move_touch_start
            var distance = offset.length()
            if distance > 0:
                # Normalize and clamp to max distance
                var clamped_distance = min(distance, JOYSTICK_MAX_DISTANCE)
                move_joystick_value = offset.normalized() * (clamped_distance / JOYSTICK_MAX_DISTANCE)
                # Apply deadzone
                if move_joystick_value.length() < JOYSTICK_DEADZONE:
                    move_joystick_value = Vector2.ZERO
        
        elif drag.index == rotate_touch_index:
            var offset = touch_pos - rotate_touch_start
            var distance = offset.length()
            if distance > 0:
                var clamped_distance = min(distance, JOYSTICK_MAX_DISTANCE)
                rotate_joystick_value = offset.normalized() * (clamped_distance / JOYSTICK_MAX_DISTANCE)
                if rotate_joystick_value.length() < JOYSTICK_DEADZONE:
                    rotate_joystick_value = Vector2.ZERO

func _is_point_in_control(point: Vector2, control: Control) -> bool:
    if not control or not control.visible:
        return false
    var rect = control.get_global_rect()
    return rect.has_point(point)

func _handle_star_click(screen_pos: Vector2):
    if galaxy_scene == null or camera == null:
        return
    
    var star = galaxy_scene.find_star_at_screen_pos(screen_pos, camera, click_threshold)
    
    if star.is_empty():
        selected_star = {}
        selected_system = {}
        selection_marker.visible = false
        if star_info_label:
            star_info_label.text = "[center][color=#888888]Click a star to select[/color][/center]"
        return
    
    selected_star = star
    
    # Update selection marker
    var pos = star.get("position", {})
    var galaxy_scale = galaxy_scene.galaxy_scale
    var star_world_pos = Vector3(
        pos.get("x", 0.0) * galaxy_scale,
        pos.get("y", 0.0) * galaxy_scale,
        pos.get("z", 0.0) * galaxy_scale
    )
    selection_marker.global_position = star_world_pos
    selection_marker.visible = true
    _update_selection_marker_scale()
    
    # Query system data
    var star_id = str(star.get("id", "0"))
    selected_system = galaxy_scene.get_star_system(star_id)
    
    # Update fly button text
    _update_view_mode_label()
    
    # Calculate distance from camera to star (in light years)
    var star_pos_ly = Vector3(pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0))
    var cam_pos_ly = camera.global_position / galaxy_scale
    var distance_ly = cam_pos_ly.distance_to(star_pos_ly)
    
    # Update star info label using shared function
    _update_star_info_label(distance_ly)

func _on_seed_input_text_submitted(new_text: String):
    """Handle seed input text submission (Enter key pressed)"""
    var seed_text = new_text.strip_edges()
    if seed_text.is_valid_int():
        galaxy_seed = int(seed_text)
    else:
        # Use string hash as seed if not a valid integer
        galaxy_seed = seed_text.hash()
    print("Generating galaxy with seed: ", galaxy_seed)
    _regenerate_galaxy()

func _on_generate_button_pressed():
    # Get seed from input field
    if seed_input:
        var seed_text = seed_input.text.strip_edges()
        if seed_text.is_valid_int():
            galaxy_seed = int(seed_text)
        else:
            # Use string hash as seed if not a valid integer
            galaxy_seed = seed_text.hash()
        print("Generating galaxy with seed: ", galaxy_seed)
    _regenerate_galaxy()

func _on_fly_to_system_button_pressed():
    if in_system_view:
        _exit_system_view()
    elif not selected_star.is_empty():
        _fly_to_system()

func _on_flight_mode_toggled(button_pressed: bool):
    if button_pressed and not in_system_view and not selected_star.is_empty():
        _fly_to_system()
    elif not button_pressed and in_system_view:
        _exit_system_view()

func _on_goto_button_pressed():
    if goto_edit_mode:
        # "Go" was pressed - fly to the entered position
        _fly_to_entered_position()
    else:
        # "Goto" was pressed - switch to edit mode
        _enter_goto_edit_mode()

func _enter_goto_edit_mode():
    goto_edit_mode = true
    
    # Get current position in ly for default values
    var galaxy_scale = galaxy_scene.galaxy_scale if galaxy_scene else 0.001
    var pos_ly = camera.global_position / galaxy_scale if camera else Vector3.ZERO
    
    # Show inputs, hide labels
    if x_position: x_position.visible = false
    if y_position: y_position.visible = false
    if z_position: z_position.visible = false
    if x_input:
        x_input.visible = true
        x_input.text = "%.1f" % pos_ly.x
    if y_input:
        y_input.visible = true
        y_input.text = "%.1f" % pos_ly.y
    if z_input:
        z_input.visible = true
        z_input.text = "%.1f" % pos_ly.z
    
    # Change button text
    if goto_button:
        goto_button.text = "Go"

func _exit_goto_edit_mode():
    goto_edit_mode = false
    
    # Show labels, hide inputs
    if x_position: x_position.visible = true
    if y_position: y_position.visible = true
    if z_position: z_position.visible = true
    if x_input: x_input.visible = false
    if y_input: y_input.visible = false
    if z_input: z_input.visible = false
    
    # Change button text back
    if goto_button:
        goto_button.text = "Goto"

func _fly_to_entered_position():
    if not goto_edit_mode:
        return
    
    # Parse coordinates from inputs
    var target_x = float(x_input.text) if x_input and x_input.text.is_valid_float() else 0.0
    var target_y = float(y_input.text) if y_input and y_input.text.is_valid_float() else 0.0
    var target_z = float(z_input.text) if z_input and z_input.text.is_valid_float() else 0.0
    
    var galaxy_scale = galaxy_scene.galaxy_scale if galaxy_scene else 0.001
    var target_pos = Vector3(target_x, target_y, target_z) * galaxy_scale
    
    # Exit edit mode
    _exit_goto_edit_mode()
    
    # Start fly-to animation
    is_flying_to_position = true
    _update_view_mode_label()
    
    if fly_to_tween and fly_to_tween.is_valid():
        fly_to_tween.kill()
    
    var distance = camera.global_position.distance_to(target_pos)
    var flight_duration = clamp(distance * 0.5, 0.5, 3.0)
    
    fly_to_tween = create_tween()
    fly_to_tween.set_trans(Tween.TRANS_QUAD)
    fly_to_tween.set_ease(Tween.EASE_IN_OUT)
    fly_to_tween.tween_property(camera, "global_position", target_pos, flight_duration)
    fly_to_tween.parallel().tween_method(_look_at_target.bind(target_pos), 0.0, 1.0, flight_duration)
    fly_to_tween.tween_callback(_complete_fly_to_position)
    
    print("Flying to position (%.1f, %.1f, %.1f) ly..." % [target_x, target_y, target_z])

func _complete_fly_to_position():
    is_flying_to_position = false
    _update_view_mode_label()
    
    # Force update nearby stars at new position
    if galaxy_scene and camera:
        galaxy_scene.update_nearby_stars(camera.global_position, true)
        # Update nearest stars list after a short delay for stars to load
        await get_tree().create_timer(0.1).timeout
        _update_nearest_stars_list()

func _update_nearest_stars_list():
    if nearest_star_list == null or galaxy_scene == null or camera == null:
        return
    
    # Clear existing list
    for child in nearest_star_list.get_children():
        child.queue_free()
    
    nearby_stars_data.clear()
    
    var nearby = galaxy_scene.current_nearby_stars
    if nearby.is_empty():
        _update_nearby_panels_visibility()
        return
    
    var positions: PackedVector3Array = nearby.get("positions", PackedVector3Array())
    var ids: PackedInt64Array = nearby.get("ids", PackedInt64Array())
    var luminosities: PackedFloat32Array = nearby.get("luminosities", PackedFloat32Array())
    var temperatures: PackedFloat32Array = nearby.get("temperatures", PackedFloat32Array())
    var star_types: PackedStringArray = nearby.get("star_types", PackedStringArray())
    
    if positions.is_empty():
        _update_nearby_panels_visibility()
        return
    
    var galaxy_scale = galaxy_scene.galaxy_scale
    var cam_pos_ly = camera.global_position / galaxy_scale
    
    # Build list of star data with distances
    for i in range(positions.size()):
        var star_pos_ly = positions[i]
        var dist = cam_pos_ly.distance_to(star_pos_ly)
        nearby_stars_data.append({
            "dist": dist,
            "id": ids[i] if i < ids.size() else 0,
            "pos": star_pos_ly,
            "luminosity": luminosities[i] if i < luminosities.size() else 1.0,
            "temperature": temperatures[i] if i < temperatures.size() else 5000.0,
            "star_type": star_types[i] if i < star_types.size() else "Unknown"
        })
    
    # Sort by distance
    nearby_stars_data.sort_custom(func(a, b): return a.dist < b.dist)
    
    # Show nearest 10 as buttons
    var count = min(10, nearby_stars_data.size())
    for i in range(count):
        var star = nearby_stars_data[i]
        var btn = Button.new()
        btn.text = "%.1f ly - %s" % [star.dist, star.star_type]
        btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
        btn.pressed.connect(_on_nearby_star_selected.bind(star))
        nearest_star_list.add_child(btn)
    
    _update_nearby_panels_visibility()

func _on_nearby_star_selected(star_data: Dictionary):
    selected_nearby_star = star_data
    
    # Set up selected_star so fly-to-system works
    # Note: id must be a string to match find_star_at_screen_pos format
    var pos = star_data.get("pos", Vector3.ZERO)
    var star_id = str(star_data.get("id", 0))
    selected_star = {
        "id": star_id,
        "position": {"x": pos.x, "y": pos.y, "z": pos.z},
        "star_type": star_data.get("star_type", "Unknown"),
        "temperature": star_data.get("temperature", 5000.0),
        "luminosity": star_data.get("luminosity", 1.0),
    }
    
    # Update selection marker
    if galaxy_scene and selection_marker:
        var galaxy_scale = galaxy_scene.galaxy_scale
        var star_world_pos = Vector3(pos.x * galaxy_scale, pos.y * galaxy_scale, pos.z * galaxy_scale)
        selection_marker.global_position = star_world_pos
        selection_marker.visible = true
        _update_selection_marker_scale()
    
    # Query full system data for this star
    if galaxy_scene:
        selected_system = galaxy_scene.get_star_system(star_id)
    
    # Use the distance from nearby star data
    var distance_ly = star_data.get("dist", 0.0)
    _update_star_info_label(distance_ly)
    _update_view_mode_label()  # This updates the fly button

func _update_star_info_label(distance_ly: float):
    """Update the star info label with system details. Uses selected_system and selected_star."""
    if star_info_label == null:
        return
    
    if selected_system.is_empty() and selected_star.is_empty():
        star_info_label.text = "[center][color=#888888]Select a star[/color][/center]"
        return
    
    var info = ""
    
    # Show all stars in the system
    var stars = selected_system.get("stars", [])
    if stars.size() == 1:
        var s = stars[0]
        info += "[center][b][color=#ffdd44]★ %s ★[/color][/b][/center]\n\n" % s.get("star_type", "Unknown")
        info += "[color=#88ccff]📏 Distance:[/color] %.2f ly\n" % distance_ly
        info += "[color=#ff8844]🌡 Temperature:[/color] %.0f K\n" % s.get("temperature", 0)
        info += "[color=#ffaa00]☀ Luminosity:[/color] %.2f L☉\n" % s.get("luminosity", 0)
        info += "[color=#aaaaff]⚖ Mass:[/color] %.2f M☉\n" % s.get("mass", 0)
    elif stars.size() > 1:
        info += "[center][b][color=#ffdd44]✦ Multi-Star System ✦[/color][/b][/center]\n"
        info += "[center]%d stars[/center]\n\n" % stars.size()
        info += "[color=#88ccff]📏 Distance:[/color] %.2f ly\n\n" % distance_ly
        for i in range(stars.size()):
            var s = stars[i]
            var prefix = "[color=#ffcc00]Primary:[/color] " if i == 0 else "[color=#88aaff]Companion:[/color] "
            info += prefix + "%s (%.1f M☉)\n" % [s.get("star_type", "Unknown"), s.get("mass", 0)]
    else:
        # Fallback to selected_star data if system stars not available
        info += "[center][b][color=#ffdd44]★ %s ★[/color][/b][/center]\n\n" % selected_star.get("star_type", "Unknown")
        info += "[color=#88ccff]📏 Distance:[/color] %.2f ly\n" % distance_ly
        info += "[color=#ff8844]🌡 Temperature:[/color] %.0f K\n" % selected_star.get("temperature", 0)
        info += "[color=#ffaa00]☀ Luminosity:[/color] %.2f L☉\n" % selected_star.get("luminosity", 0)
        info += "[color=#aaaaff]⚖ Mass:[/color] %.2f M☉\n" % selected_star.get("mass", 0)
    
    # Planet count (check both legacy and stellar_components format)
    var total_planets = 0
    var components = selected_system.get("stellar_components", [])
    if components.size() > 0:
        for comp in components:
            total_planets += comp.get("inner_planets", []).size()
            total_planets += comp.get("outer_planets", []).size()
    else:
        var inner = selected_system.get("inner_planets", [])
        var outer = selected_system.get("outer_planets", [])
        total_planets = inner.size() + outer.size()
    
    if total_planets > 0:
        info += "\n[color=#44ddaa]🪐 Planets:[/color] %d\n" % total_planets
    
    var belts = selected_system.get("asteroid_belts", [])
    if belts.size() > 0:
        info += "[color=#888888]💫 Asteroid Belts:[/color] %d\n" % belts.size()
    
    if selected_system.has("oort_cloud"):
        info += "[color=#666688]☁ Oort Cloud[/color]\n"
    
    info += "\n[center][color=#66ff66]Press [F] or click button to visit[/color][/center]"
    star_info_label.text = info

func _update_nearby_panels_visibility():
    var show_panels = not in_system_view and not nearby_stars_data.is_empty()
    if nearest_stars_panel:
        nearest_stars_panel.visible = show_panels


func _handle_system_object_click(screen_pos: Vector2):
    if system_scene == null or camera == null:
        return
    
    # Get ray from camera through click position
    var ray_origin = camera.project_ray_origin(screen_pos)
    var ray_dir = camera.project_ray_normal(screen_pos)
    
    # First try to pick a 3D object (star, planet, moon)
    var picked = system_scene.pick_object_at_ray(ray_origin, ray_dir)
    
    if not picked.is_empty():
        selected_system_object = picked
        system_scene.select_object(picked)
        _update_selected_object_info()
        return
    
    # If no object hit, try picking an orbit line
    # Project click to the orbital plane (y=0)
    if ray_dir.y != 0:
        var t = -ray_origin.y / ray_dir.y
        if t > 0:
            var world_pos = ray_origin + ray_dir * t
            var orbit_pick = system_scene.pick_orbit_at_position(world_pos)
            if not orbit_pick.is_empty():
                selected_system_object = orbit_pick
                # For orbit picks, find the planet's pickable object to get position
                for obj in system_scene.pickable_objects:
                    if obj.get("type") == orbit_pick.get("type") and obj.get("index") == orbit_pick.get("index"):
                        system_scene.select_object(obj)
                        break
                _update_selected_object_info()
                return
    
    # Clear selection if clicked on nothing
    selected_system_object = {}
    system_scene.clear_selection()
    _update_selected_object_info()

func _update_system_tooltip():
    if not in_system_view or system_scene == null or camera == null or tooltip_label == null:
        if tooltip_label:
            tooltip_label.visible = false
        return
    
    # Don't show tooltip while mouse looking
    if is_mouse_looking:
        tooltip_label.visible = false
        return
    
    var screen_pos = _get_selection_screen_pos()
    var ray_origin = camera.project_ray_origin(screen_pos)
    var ray_dir = camera.project_ray_normal(screen_pos)
    
    var hovered = system_scene.pick_object_at_ray(ray_origin, ray_dir)
    
    if hovered.is_empty():
        tooltip_label.visible = false
        return
    
    var tooltip_text = system_scene.get_object_tooltip(hovered)
    if tooltip_text.is_empty():
        tooltip_label.visible = false
        return
    
    tooltip_label.text = tooltip_text
    tooltip_label.visible = true
    # Position tooltip near crosshair when using gamepad, near cursor otherwise
    if using_gamepad:
        tooltip_label.position = screen_pos + Vector2(20, 20)
    else:
        tooltip_label.position = screen_pos + Vector2(15, 15)

func _get_selection_screen_pos() -> Vector2:
    if using_gamepad:
        # Use screen center (where crosshair is)
        return get_viewport().get_visible_rect().size / 2.0
    else:
        return get_viewport().get_mouse_position()

func _update_crosshair_visibility():
    if crosshair:
        crosshair.visible = using_gamepad
