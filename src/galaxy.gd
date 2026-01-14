extends Node3D

signal star_selected(star_data: Dictionary, system_data: Dictionary)

@export var star_points: MultiMeshInstance3D
@export var nearby_stars: MultiMeshInstance3D

@export var galaxy_scale: float = 0.001  # Light years to visual units
@export var nearby_radius: float = 200.0
@export var nearby_refresh_distance: float = 100.0
@export var max_stars: int = 500000

var mei_galaxy: MeiGalaxy
var current_stars: Dictionary = {}  # Packed arrays: positions, ids, luminosities, temperatures, masses, star_types
var current_nearby_stars: Dictionary = {}
var last_query_position: Vector3 = Vector3.ZERO
var galaxy_center: Vector3 = Vector3.ZERO

# Screen-space hash grid for fast star picking
const PICK_GRID_SIZE: int = 32  # Pixels per grid cell
var _pick_grid: Dictionary = {}  # Vector2i -> Array of star indices
var _pick_grid_valid: bool = false
var _pick_grid_camera: Camera3D = null

# Galaxy rotation
var rotation_enabled: bool = false

func _format_number(n: int) -> String:
    if n >= 1_000_000_000:
        return "%.2f billion" % (n / 1_000_000_000.0)
    elif n >= 1_000_000:
        return "%.2f million" % (n / 1_000_000.0)
    elif n >= 1_000:
        return "%.1f thousand" % (n / 1_000.0)
    else:
        return str(n)

var rotation_speed: float = 0.03
var rotation_angle: float = 0.0

func _ready():
    _setup_multimesh_materials()

func _setup_multimesh_materials():
    _configure_instance_color_material(star_points)
    _configure_instance_color_material(nearby_stars)

func _configure_instance_color_material(mesh_instance: MultiMeshInstance3D):
    if mesh_instance == null:
        return
    var mat = mesh_instance.material_override
    if mat == null and mesh_instance.multimesh != null and mesh_instance.multimesh.mesh != null:
        mat = mesh_instance.multimesh.mesh.surface_get_material(0)
    if mat == null:
        mat = StandardMaterial3D.new()
        mesh_instance.material_override = mat
    if mat is StandardMaterial3D:
        mat.vertex_color_use_as_albedo = true
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func initialize(galaxy_seed: int):
    # Check if GDExtension loaded properly
    if not ClassDB.class_exists("MeiGalaxy"):
        push_error("MeiGalaxy class not found - GDExtension failed to load")
        return
    
    mei_galaxy = MeiGalaxy.new()
    if mei_galaxy == null:
        push_error("Failed to create MeiGalaxy instance")
        return
    
    mei_galaxy.seed = galaxy_seed
    add_child(mei_galaxy)
    await get_tree().process_frame
    
    # Load config from file - globalize path for Rust filesystem access
    var config_path = ProjectSettings.globalize_path("res://generator_config.toml")
    mei_galaxy.load_config(config_path)
    
    current_stars = mei_galaxy.get_structure(max_stars)
    galaxy_center = Vector3.ZERO
    
    var estimated_total = current_stars.get("estimated_total_stars", 0)
    print("Galaxy initialized - Estimated total stars: ", _format_number(estimated_total))
    
    render_stars(current_stars)
    
    # Initial nearby stars query
    update_nearby_stars(galaxy_center, true)

func reinitialize(galaxy_seed: int):
    # Remove old MeiGalaxy instance
    if mei_galaxy:
        mei_galaxy.queue_free()
        mei_galaxy = null
    
    # Create new instance with new seed
    mei_galaxy = MeiGalaxy.new()
    mei_galaxy.seed = galaxy_seed
    add_child(mei_galaxy)
    await get_tree().process_frame
    
    # Load config from file - globalize path for Rust filesystem access
    var config_path = ProjectSettings.globalize_path("res://generator_config.toml")
    mei_galaxy.load_config(config_path)
    
    current_stars = mei_galaxy.get_structure(max_stars)
    current_nearby_stars = {}
    last_query_position = Vector3.ZERO
    galaxy_center = Vector3.ZERO
    
    var estimated_total = current_stars.get("estimated_total_stars", 0)
    print("Galaxy reinitialized - Estimated total stars: ", _format_number(estimated_total))
    
    render_stars(current_stars)
    update_nearby_stars(galaxy_center, true)

func update_nearby_stars(camera_pos_visual: Vector3, force: bool = false):
    if mei_galaxy == null or nearby_stars == null or not is_instance_valid(mei_galaxy):
        return
    
    var query_x = camera_pos_visual.x / galaxy_scale
    var query_y = camera_pos_visual.y / galaxy_scale
    var query_z = camera_pos_visual.z / galaxy_scale
    
    var current_pos_ly = Vector3(query_x, query_y, query_z)
    var distance_moved = current_pos_ly.distance_to(last_query_position)
    
    if force or distance_moved >= nearby_refresh_distance:
        last_query_position = current_pos_ly
        current_nearby_stars = mei_galaxy.get_nearby_stars(query_x, query_y, query_z, nearby_radius)
        var count = current_nearby_stars.get("count", 0)
        print("Galaxy: Updated nearby stars, got ", count, " stars at position ", current_pos_ly)
        render_nearby_stars(current_nearby_stars)
        _pick_grid_valid = false  # Invalidate pick grid when stars change

func rebuild_pick_grid(camera: Camera3D):
    """Rebuild the screen-space hash grid for fast star picking.
    Call this after camera stops moving.
    Grid stores [source, index] pairs where source=0 for galactic, source=1 for nearby."""
    if camera == null:
        return
    
    _pick_grid.clear()
    _pick_grid_camera = camera
    
    var galactic_count = 0
    var nearby_count = 0
    
    # Add galactic structure stars (source=0)
    var positions: PackedVector3Array = current_stars.get("positions", PackedVector3Array())
    for i in range(positions.size()):
        var star_world_pos = positions[i] * galaxy_scale
        
        # Skip stars behind camera or outside frustum
        if not camera.is_position_in_frustum(star_world_pos):
            continue
        
        var screen_pos = camera.unproject_position(star_world_pos)
        var cell = Vector2i(int(screen_pos.x) / PICK_GRID_SIZE, int(screen_pos.y) / PICK_GRID_SIZE)
        
        if not _pick_grid.has(cell):
            _pick_grid[cell] = []
        _pick_grid[cell].append([0, i])  # source=0 for galactic
        galactic_count += 1
    
    # Add nearby stars (source=1)
    var nearby_positions: PackedVector3Array = current_nearby_stars.get("positions", PackedVector3Array())
    for i in range(nearby_positions.size()):
        var star_world_pos = nearby_positions[i] * galaxy_scale
        
        if not camera.is_position_in_frustum(star_world_pos):
            continue
        
        var screen_pos = camera.unproject_position(star_world_pos)
        var cell = Vector2i(int(screen_pos.x) / PICK_GRID_SIZE, int(screen_pos.y) / PICK_GRID_SIZE)
        
        if not _pick_grid.has(cell):
            _pick_grid[cell] = []
        _pick_grid[cell].append([1, i])  # source=1 for nearby
        nearby_count += 1
    
    _pick_grid_valid = true
    print("Pick grid rebuilt: ", _pick_grid.size(), " cells (", galactic_count, " galactic, ", nearby_count, " nearby)")

func invalidate_pick_grid():
    """Mark pick grid as needing rebuild (call when camera moves)."""
    _pick_grid_valid = false

func update_rotation(delta: float):
    if not rotation_enabled:
        return
    
    rotation_angle += rotation_speed * delta
    var rotation_transform = Transform3D()
    rotation_transform = rotation_transform.rotated(Vector3.UP, rotation_angle)
    rotation_transform.origin = galaxy_center
    
    if star_points != null:
        star_points.transform = rotation_transform
    if nearby_stars != null:
        nearby_stars.transform = rotation_transform

func get_star_system(star_id: String) -> Dictionary:
    if mei_galaxy == null or not is_instance_valid(mei_galaxy):
        return {}
    return mei_galaxy.get_star_system(star_id)

func find_star_at_screen_pos(screen_pos: Vector2, camera: Camera3D, _click_threshold: float) -> Dictionary:
    if camera == null:
        return {}
    
    # Fixed pixel threshold for precise clicking
    const CLICK_THRESHOLD_PX: float = 5.0
    
    # Get data from both star sources
    var galactic_positions: PackedVector3Array = current_stars.get("positions", PackedVector3Array())
    var galactic_ids: PackedInt64Array = current_stars.get("ids", PackedInt64Array())
    var galactic_luminosities: PackedFloat32Array = current_stars.get("luminosities", PackedFloat32Array())
    var galactic_temperatures: PackedFloat32Array = current_stars.get("temperatures", PackedFloat32Array())
    var galactic_masses: PackedFloat32Array = current_stars.get("masses", PackedFloat32Array())
    var galactic_star_types: PackedStringArray = current_stars.get("star_types", PackedStringArray())
    
    var nearby_positions: PackedVector3Array = current_nearby_stars.get("positions", PackedVector3Array())
    var nearby_ids: PackedInt64Array = current_nearby_stars.get("ids", PackedInt64Array())
    var nearby_luminosities: PackedFloat32Array = current_nearby_stars.get("luminosities", PackedFloat32Array())
    var nearby_temperatures: PackedFloat32Array = current_nearby_stars.get("temperatures", PackedFloat32Array())
    var nearby_masses: PackedFloat32Array = current_nearby_stars.get("masses", PackedFloat32Array())
    var nearby_star_types: PackedStringArray = current_nearby_stars.get("star_types", PackedStringArray())
    
    if galactic_positions.is_empty() and nearby_positions.is_empty():
        return {}
    
    var best_source = -1  # 0=galactic, 1=nearby
    var best_idx = -1
    var best_dist = CLICK_THRESHOLD_PX  # Simple: closest star within threshold wins
    
    # Use grid-based lookup if valid, otherwise fall back to full scan
    var candidates: Array = []  # Array of [source, index]
    if _pick_grid_valid and _pick_grid_camera == camera:
        # Get candidates from grid cells in search radius
        var search_radius = int(CLICK_THRESHOLD_PX / PICK_GRID_SIZE) + 1
        var center_cell = Vector2i(int(screen_pos.x) / PICK_GRID_SIZE, int(screen_pos.y) / PICK_GRID_SIZE)
        
        for dx in range(-search_radius, search_radius + 1):
            for dy in range(-search_radius, search_radius + 1):
                var cell = center_cell + Vector2i(dx, dy)
                if _pick_grid.has(cell):
                    candidates.append_array(_pick_grid[cell])
    else:
        # Fallback: check all stars from both sources (slow path)
        for i in range(galactic_positions.size()):
            candidates.append([0, i])
        for i in range(nearby_positions.size()):
            candidates.append([1, i])
    
    # Check nearby stars first (they're more precise), then galactic
    # This matches mei-viewer's prioritization
    for pass_nearby in [true, false]:
        for candidate in candidates:
            var source = candidate[0]
            var is_nearby = (source == 1)
            
            # Skip if not matching current pass
            if is_nearby != pass_nearby:
                continue
            
            var idx = candidate[1]
            
            var star_world_pos: Vector3
            if source == 0:
                star_world_pos = galactic_positions[idx] * galaxy_scale
            else:
                star_world_pos = nearby_positions[idx] * galaxy_scale
            
            if not camera.is_position_in_frustum(star_world_pos):
                continue
            
            var star_screen_pos = camera.unproject_position(star_world_pos)
            var screen_dist = screen_pos.distance_to(star_screen_pos)
            
            # Simple distance check - closest within threshold wins
            if screen_dist < best_dist:
                best_dist = screen_dist
                best_source = source
                best_idx = idx
        
        # If we found a nearby star, don't check galactic stars
        if pass_nearby and best_idx >= 0:
            break
    
    if best_idx < 0:
        return {}
    
    # Return a dictionary with star data from the correct source
    if best_source == 0:
        return {
            "id": str(galactic_ids[best_idx]),
            "position": {"x": galactic_positions[best_idx].x, "y": galactic_positions[best_idx].y, "z": galactic_positions[best_idx].z},
            "star_type": galactic_star_types[best_idx],
            "luminosity": galactic_luminosities[best_idx],
            "temperature": galactic_temperatures[best_idx],
            "mass": galactic_masses[best_idx]
        }
    else:
        return {
            "id": str(nearby_ids[best_idx]),
            "position": {"x": nearby_positions[best_idx].x, "y": nearby_positions[best_idx].y, "z": nearby_positions[best_idx].z},
            "star_type": nearby_star_types[best_idx],
            "luminosity": nearby_luminosities[best_idx],
            "temperature": nearby_temperatures[best_idx],
            "mass": nearby_masses[best_idx]
        }

func find_star_along_ray(ray_origin: Vector3, ray_dir: Vector3, threshold: float) -> Dictionary:
    var positions: PackedVector3Array = current_stars.get("positions", PackedVector3Array())
    if positions.is_empty():
        return {}
    
    var ids: PackedInt64Array = current_stars.get("ids", PackedInt64Array())
    var luminosities: PackedFloat32Array = current_stars.get("luminosities", PackedFloat32Array())
    var temperatures: PackedFloat32Array = current_stars.get("temperatures", PackedFloat32Array())
    var masses: PackedFloat32Array = current_stars.get("masses", PackedFloat32Array())
    var star_types: PackedStringArray = current_stars.get("star_types", PackedStringArray())
    
    var closest_idx = -1
    var best_score = INF
    
    for i in range(positions.size()):
        var star_world_pos = positions[i] * galaxy_scale
        
        # Calculate closest point on ray to star
        var to_star = star_world_pos - ray_origin
        var t = to_star.dot(ray_dir)
        
        # Skip stars behind the ray origin
        if t < 0:
            continue
        
        var closest_point = ray_origin + ray_dir * t
        var dist_to_ray = star_world_pos.distance_to(closest_point)
        
        # Adaptive threshold based on distance (further stars need larger threshold)
        var dist_from_origin = ray_origin.distance_to(star_world_pos)
        var adaptive_threshold = threshold * max(0.01, dist_from_origin * 0.1)
        
        if dist_to_ray > adaptive_threshold:
            continue
        
        # Score: prefer stars closer to ray and closer to origin
        var score = dist_to_ray + dist_from_origin * 0.01
        
        if score < best_score:
            best_score = score
            closest_idx = i
    
    if closest_idx < 0:
        return {}
    
    return {
        "id": str(ids[closest_idx]),
        "position": {"x": positions[closest_idx].x, "y": positions[closest_idx].y, "z": positions[closest_idx].z},
        "star_type": star_types[closest_idx],
        "luminosity": luminosities[closest_idx],
        "temperature": temperatures[closest_idx],
        "mass": masses[closest_idx]
    }

func render_stars(star_data: Dictionary):
    var positions: PackedVector3Array = star_data.get("positions", PackedVector3Array())
    var luminosities: PackedFloat32Array = star_data.get("luminosities", PackedFloat32Array())
    var temperatures: PackedFloat32Array = star_data.get("temperatures", PackedFloat32Array())
    
    var star_count = positions.size()
    if star_count == 0:
        return
    
    var multimesh = star_points.multimesh
    multimesh.use_colors = true
    multimesh.instance_count = star_count
    
    for i in range(star_count):
        var star_position = positions[i] * galaxy_scale
        
        var star_transform = Transform3D()
        star_transform.origin = star_position
        
        var luminosity = luminosities[i]
        var size = clamp(log(luminosity + 1.0) * 0.5 + 0.5, 0.1, 5.0)
        star_transform = star_transform.scaled(Vector3(size, size, size))
        
        multimesh.set_instance_transform(i, star_transform)
        multimesh.set_instance_color(i, temperature_to_color(temperatures[i]))

func render_nearby_stars(star_data: Dictionary):
    if nearby_stars == null or nearby_stars.multimesh == null:
        return
    
    var positions: PackedVector3Array = star_data.get("positions", PackedVector3Array())
    var luminosities: PackedFloat32Array = star_data.get("luminosities", PackedFloat32Array())
    var temperatures: PackedFloat32Array = star_data.get("temperatures", PackedFloat32Array())
    
    var star_count = positions.size()
    if star_count == 0:
        nearby_stars.multimesh.instance_count = 0
        return
    
    var multimesh = nearby_stars.multimesh
    multimesh.instance_count = 0  # Reset before changing use_colors
    multimesh.use_colors = true
    multimesh.instance_count = star_count
    
    for i in range(star_count):
        var star_position = positions[i] * galaxy_scale
        
        var luminosity = luminosities[i]
        var size = clamp(log(luminosity + 1.0) * 0.3 + 0.1, 0.05, 2.0)
        
        var star_transform = Transform3D()
        star_transform.basis = star_transform.basis.scaled(Vector3(size, size, size))
        star_transform.origin = star_position
        
        multimesh.set_instance_transform(i, star_transform)
        multimesh.set_instance_color(i, temperature_to_color(temperatures[i]))

func temperature_to_color(temp: float) -> Color:
    return MeiUtils.temperature_to_color(temp)
