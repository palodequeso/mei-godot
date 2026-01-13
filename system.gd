extends Node3D

signal exit_system_requested
signal object_selected(object_node: Node3D)

# Scene templates for instancing
var StarScene = preload("res://objects/system_star.tscn")
var PlanetScene = preload("res://objects/system_planet.tscn")
var MoonScene = preload("res://objects/system_moon.tscn")
var SelectionMarkerScene = preload("res://objects/selection_marker.tscn")

# Material resources for orbit lines
var OrbitMaterial = preload("res://objects/orbit_material.tres")
var BeltOrbitMaterial = preload("res://objects/belt_orbit_material.tres")

@export var distant_stars: MultiMeshInstance3D  # Nearby galaxy stars still use multimesh (thousands)
@export var asteroid_belt_viz: MultiMeshInstance3D  # Asteroid belt particles still use multimesh
@export var orbit_lines_container: Node3D  # Container for orbit line meshes

# Containers for instanced objects (set in scene)
@export var stars_container: Node3D
@export var planets_container: Node3D
@export var moons_container: Node3D

# =============================================================================
# REALISTIC SYSTEM SCALE CONSTANTS
# =============================================================================
# Using 100x visual scale for rendering (1 AU = 100 visual units)
# This keeps proportions realistic while making objects visible
#
# Real scale reference (diameters in AU, visual = x100):
# - Sun: 0.0093 AU → 0.93 visual units
# - Jupiter: 0.00095 AU → 0.095 visual units
# - Earth: 0.000085 AU → 0.0085 visual units
# - Moon: 0.000023 AU → 0.0023 visual units
# =============================================================================
const SYSTEM_SCALE: float = 100.0  # 1 AU = 100 visual units
const DISTANT_STAR_SCALE: float = 4000.0 # SYSTEM_SCALE * 50.0  # Background stars at ~50 AU radius

# Minimum visual size to ensure objects remain clickable
const MIN_CLICKABLE_SIZE: float = 0.1

var current_system: Dictionary = {}
var system_center: Vector3 = Vector3.ZERO
var star_galactic_position: Vector3 = Vector3.ZERO

# Rendered object nodes
var star_nodes: Array = []
var planet_nodes: Array = []
var moon_nodes: Array = []

# Selection marker
var selection_marker: Node3D
var selected_object: Node3D = null

# Camera reference for updating distant star canopy position
var camera: Camera3D = null

func _ready():
    _setup_selection_marker()
    _setup_distant_stars_material()

func _process(_delta):
    # Update distant star canopy to follow camera
    if camera and distant_stars:
        distant_stars.global_position = camera.global_position

func _setup_selection_marker():
    selection_marker = SelectionMarkerScene.instantiate()
    add_child(selection_marker)

func _setup_distant_stars_material():
    if distant_stars and distant_stars.multimesh:
        var mat = distant_stars.material_override
        if mat == null:
            mat = StandardMaterial3D.new()
            distant_stars.material_override = mat
        if mat is StandardMaterial3D:
            mat.vertex_color_use_as_albedo = true
            mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    
    if asteroid_belt_viz and asteroid_belt_viz.multimesh:
        var mat = asteroid_belt_viz.material_override
        if mat == null:
            mat = StandardMaterial3D.new()
            asteroid_belt_viz.material_override = mat
        if mat is StandardMaterial3D:
            mat.vertex_color_use_as_albedo = true
            mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func _clear_system_objects():
    star_nodes.clear()
    for child in stars_container.get_children():
        child.queue_free()
    
    planet_nodes.clear()
    for child in planets_container.get_children():
        child.queue_free()
    
    moon_nodes.clear()
    for child in moons_container.get_children():
        child.queue_free()

func set_camera(cam: Camera3D):
    """Set the camera reference for the distant star canopy to follow"""
    camera = cam

func load_system(system_data: Dictionary, star_data: Dictionary, nearby_stars: Dictionary):
    current_system = system_data
    _clear_system_objects()
    
    var star_pos = star_data.get("position", {})
    star_galactic_position = Vector3(
        star_pos.get("x", 0.0),
        star_pos.get("y", 0.0),
        star_pos.get("z", 0.0)
    )
    
    system_center = Vector3.ZERO
    
    render_system_stars(system_data.get("stars", []))
    
    # Render planets and orbits for each stellar component
    var stellar_components = system_data.get("stellar_components", [])
    var configuration = system_data.get("configuration", "Single")
    
    if stellar_components.size() > 0:
        _render_multi_star_system(stellar_components, system_data.get("stars", []))
    else:
        # Legacy: single component system
        render_planets(system_data.get("inner_planets", []), system_data.get("outer_planets", []))
        render_orbit_lines(system_data.get("inner_planets", []), system_data.get("outer_planets", []), system_data.get("asteroid_belts", []))
    
    render_asteroid_belts(system_data.get("asteroid_belts", []))
    render_distant_stars(nearby_stars, star_galactic_position)
    
    _print_system_info(system_data, configuration)

func render_system_stars(stars: Array):
    for i in range(stars.size()):
        var star = stars[i]
        var pos = star.get("position", {})
        
        var star_pos = Vector3(
            pos.get("x", 0.0) * SYSTEM_SCALE,
            pos.get("y", 0.0) * SYSTEM_SCALE,
            pos.get("z", 0.0) * SYSTEM_SCALE
        )
        
        # REALISTIC star size based on luminosity, scaled for visibility
        var luminosity = star.get("luminosity", 1.0)
        var size = MeiUtils.get_star_size(luminosity) * SYSTEM_SCALE
        
        var star_node = StarScene.instantiate()
        star_node.position = star_pos
        star_node.setup(star, i, size)
        stars_container.add_child(star_node)
        star_nodes.append(star_node)

func render_planets(inner: Array, outer: Array):
    # Clear existing orbit lines for legacy mode
    if orbit_lines_container:
        for child in orbit_lines_container.get_children():
            orbit_lines_container.remove_child(child)
            child.free()
    
    var all_planets = inner + outer
    
    for i in range(all_planets.size()):
        var planet = all_planets[i]
        var orbital_radius = planet.get("orbital_radius", planet.get("position", {}).get("x", 1.0))
        
        var angle = i * TAU / max(all_planets.size(), 1) + i * 0.5
        var planet_pos = Vector3(
            cos(angle) * orbital_radius * SYSTEM_SCALE,
            0,
            sin(angle) * orbital_radius * SYSTEM_SCALE
        )
        
        var planet_type = planet.get("planet_type", "Terrestrial")
        var mass = planet.get("mass", 1.0)
        var size = get_planet_size(planet_type, mass) * SYSTEM_SCALE
        
        var planet_node = PlanetScene.instantiate()
        planet_node.position = planet_pos
        planet_node.setup(planet, i, size)
        planets_container.add_child(planet_node)
        planet_nodes.append(planet_node)
        
        # Render moons for this planet
        var planet_moons = planet.get("moons", [])
        for j in range(planet_moons.size()):
            var moon = planet_moons[j]
            _render_moon(moon, j, i, planet_pos)

func _render_moon(moon: Dictionary, moon_idx: int, planet_idx: int, planet_pos: Vector3):
    # Get orbital radius in km - do NOT use position as fallback (that's galactic coordinates!)
    var orbital_radius_km = moon.get("orbital_radius", 10000.0)
    
    # Debug output to catch issues
    if not moon.has("orbital_radius"):
        print("WARNING: Moon ", moon_idx, " of planet ", planet_idx, " missing orbital_radius, using default 10000 km")
        print("  Moon data: ", moon)
    
    # REALISTIC: Convert km to AU (no multiplier - true scale)
    var orbital_radius_au = orbital_radius_km / MeiUtils.KM_PER_AU
    
    var angle = moon_idx * TAU / 7.0
    var moon_pos = planet_pos + Vector3(
        cos(angle) * orbital_radius_au * SYSTEM_SCALE,
        0,
        sin(angle) * orbital_radius_au * SYSTEM_SCALE
    )
    
    # Debug moon placement
    var distance_from_planet = planet_pos.distance_to(moon_pos)
    if distance_from_planet > 10.0:  # More than 10 visual units seems suspicious
        print("WARNING: Moon ", moon_idx, " placed ", distance_from_planet, " units from planet ", planet_idx)
        print("  Orbital radius: ", orbital_radius_km, " km (", orbital_radius_au, " AU)")
        print("  Planet pos: ", planet_pos, " Moon pos: ", moon_pos)
    
    # REALISTIC moon size based on mass, scaled for visibility
    var size = MeiUtils.get_moon_size(moon.get("mass", 0.01)) * SYSTEM_SCALE
    
    var moon_node = MoonScene.instantiate()
    moon_node.position = moon_pos
    moon_node.setup(moon, moon_idx, planet_idx, size)
    moons_container.add_child(moon_node)
    moon_nodes.append(moon_node)
    
    # Draw moon orbit line around planet
    _draw_moon_orbit(planet_pos, orbital_radius_au * SYSTEM_SCALE)

func _draw_moon_orbit(center: Vector3, radius: float):
    if radius < 0.001:
        return
    
    # Use fewer segments for moon orbits since they're smaller
    var segments = 32
    var mesh = _create_circle_mesh(radius, segments)
    var instance = MeshInstance3D.new()
    instance.mesh = mesh
    
    # Moon orbits are subtle gray/blue
    var mat = OrbitMaterial.duplicate()
    mat.albedo_color = Color(0.5, 0.6, 0.8, 0.3)
    instance.material_override = mat
    instance.position = center
    orbit_lines_container.add_child(instance)

func select_object_node(obj_node: Node3D):
    if obj_node == null:
        clear_selection()
        return
    
    selected_object = obj_node
    var size = obj_node.scale.x * 1.2
    selection_marker.scale = Vector3(size, size, size)
    selection_marker.global_position = obj_node.global_position
    selection_marker.visible = true
    object_selected.emit(obj_node)

func clear_selection():
    selected_object = null
    selection_marker.visible = false

func get_planet_size(planet_type: String, mass: float) -> float:
    return MeiUtils.get_planet_size(planet_type, mass)

func render_orbit_lines(inner: Array, outer: Array, asteroid_belts: Array = [], center: Vector3 = Vector3.ZERO, orbit_color: Color = Color.WHITE):
    if orbit_lines_container == null:
        return
    
    var all_planets = inner + outer
    
    for i in range(all_planets.size()):
        var planet = all_planets[i]
        var orbital_radius = planet.get("orbital_radius", 0.0)
        if orbital_radius == 0.0:
            orbital_radius = planet.get("position", {}).get("x", 1.0)
        orbital_radius *= SYSTEM_SCALE
        if orbital_radius < 0.01:
            continue
        
        var orbit_mesh = _create_circle_mesh(orbital_radius, 64)
        var mesh_instance = MeshInstance3D.new()
        mesh_instance.mesh = orbit_mesh
        var mat = OrbitMaterial.duplicate()
        if orbit_color != Color.WHITE:
            mat.albedo_color = orbit_color
        mesh_instance.material_override = mat
        mesh_instance.position = center
        orbit_lines_container.add_child(mesh_instance)
    
    for belt in asteroid_belts:
        var inner_radius = belt.get("inner_radius", 0.0) * SYSTEM_SCALE
        var outer_radius = belt.get("outer_radius", 0.0) * SYSTEM_SCALE
        
        if inner_radius > 0.01:
            var inner_mesh = _create_circle_mesh(inner_radius, 64)
            var inner_instance = MeshInstance3D.new()
            inner_instance.mesh = inner_mesh
            inner_instance.material_override = BeltOrbitMaterial.duplicate()
            inner_instance.position = center
            orbit_lines_container.add_child(inner_instance)
        
        if outer_radius > 0.01:
            var outer_mesh = _create_circle_mesh(outer_radius, 64)
            var outer_instance = MeshInstance3D.new()
            outer_instance.mesh = outer_mesh
            outer_instance.material_override = BeltOrbitMaterial.duplicate()
            outer_instance.position = center
            orbit_lines_container.add_child(outer_instance)

func _render_multi_star_system(components: Array, _stars: Array):
    # Clear existing orbit lines
    if orbit_lines_container:
        for child in orbit_lines_container.get_children():
            orbit_lines_container.remove_child(child)
            child.free()
    
    # Colors for different components' orbits
    var component_colors = [
        Color(0.3, 0.5, 1.0, 0.6),   # Blue for primary
        Color(1.0, 0.5, 0.3, 0.6),   # Orange for secondary
        Color(0.3, 1.0, 0.5, 0.6),   # Green for tertiary
    ]
    
    var total_planets = 0
    
    for comp_idx in range(components.size()):
        var component = components[comp_idx]
        var inner_planets = component.get("inner_planets", [])
        var outer_planets = component.get("outer_planets", [])
        
        # Get barycenter position for this component
        var barycenter_data = component.get("barycenter", {})
        var barycenter = Vector3(
            barycenter_data.get("x", 0.0) * SYSTEM_SCALE,
            barycenter_data.get("y", 0.0) * SYSTEM_SCALE,
            barycenter_data.get("z", 0.0) * SYSTEM_SCALE
        )
        
        # Get star indices for this component
        var star_indices = component.get("star_indices", [])
        var is_binary_component = star_indices.size() >= 2
        
        # Choose orbit color based on component index
        var orbit_color = component_colors[comp_idx % component_colors.size()]
        
        # Render planets for this component (positioned relative to barycenter)
        if inner_planets.size() > 0 or outer_planets.size() > 0:
            _render_component_planets(inner_planets, outer_planets, barycenter, comp_idx)
            render_orbit_lines(inner_planets, outer_planets, [], barycenter, orbit_color)
            total_planets += inner_planets.size() + outer_planets.size()
        
        # For binary components, draw a line showing the binary orbit
        if is_binary_component and star_indices.size() >= 2:
            var separation = component.get("internal_separation", 0.0) * SYSTEM_SCALE
            if separation > 0.01:
                _draw_binary_orbit(barycenter, separation, Color(1.0, 1.0, 0.5, 0.4))
    
    print("Multi-star system: ", components.size(), " components, ", total_planets, " total planets")

func _render_component_planets(inner: Array, outer: Array, barycenter: Vector3, component_idx: int):
    var all_planets = inner + outer
    var base_planet_idx = planet_nodes.size()
    
    for i in range(all_planets.size()):
        var planet = all_planets[i]
        var orbital_radius = planet.get("orbital_radius", planet.get("position", {}).get("x", 1.0))
        
        # Position planet on orbit around barycenter
        var angle = i * TAU / max(all_planets.size(), 1) + i * 0.5 + component_idx * 0.7
        var planet_pos = barycenter + Vector3(
            cos(angle) * orbital_radius * SYSTEM_SCALE,
            0,
            sin(angle) * orbital_radius * SYSTEM_SCALE
        )
        
        var planet_type = planet.get("planet_type", "Terrestrial")
        var mass = planet.get("mass", 1.0)
        var size = get_planet_size(planet_type, mass) * SYSTEM_SCALE
        
        var planet_node = PlanetScene.instantiate()
        planet_node.position = planet_pos
        planet_node.setup(planet, base_planet_idx + i, size)
        planets_container.add_child(planet_node)
        planet_nodes.append(planet_node)
        
        # Render moons for this planet
        var planet_moons = planet.get("moons", [])
        for j in range(planet_moons.size()):
            var moon = planet_moons[j]
            _render_moon(moon, j, base_planet_idx + i, planet_pos)

func _draw_binary_orbit(center: Vector3, radius: float, color: Color):
    var orbit_mesh = _create_circle_mesh(radius / 2.0, 32)
    var mesh_instance = MeshInstance3D.new()
    mesh_instance.mesh = orbit_mesh
    var mat = OrbitMaterial.duplicate()
    mat.albedo_color = color
    mesh_instance.material_override = mat
    mesh_instance.position = center
    orbit_lines_container.add_child(mesh_instance)

func _print_system_info(system_data: Dictionary, configuration):
    var stars = system_data.get("stars", [])
    var components = system_data.get("stellar_components", [])
    var config_str = _get_configuration_string(configuration)
    
    var total_planets = 0
    for comp in components:
        total_planets += comp.get("inner_planets", []).size()
        total_planets += comp.get("outer_planets", []).size()
    
    # Add legacy planets if no components
    if components.size() == 0:
        total_planets = system_data.get("inner_planets", []).size() + system_data.get("outer_planets", []).size()
    
    print("System loaded: ", stars.size(), " stars (", config_str, "), ", 
        components.size(), " components, ", total_planets, " planets")

func _get_configuration_string(configuration) -> String:
    if configuration is Dictionary:
        var config_type = configuration.get("type", "Single")
        match config_type:
            "CloseBinary":
                return "Close Binary (%.2f AU)" % configuration.get("separation_au", 0)
            "WideBinary":
                return "Wide Binary (%.1f AU)" % configuration.get("separation_au", 0)
            "HierarchicalTriple":
                return "Hierarchical Triple (inner: %.2f AU, outer: %.1f AU)" % [
                    configuration.get("inner_separation_au", 0),
                    configuration.get("outer_separation_au", 0)
                ]
            "UnstableTriple":
                return "Unstable Triple"
            _:
                return config_type
    elif configuration is String:
        return configuration
    return "Single"

# =============================================================================
# POSITION UTILITIES - Convert between visual units and AU
# =============================================================================

func visual_to_au(visual_pos: Vector3) -> Vector3:
    return visual_pos / SYSTEM_SCALE

func au_to_visual(au_pos: Vector3) -> Vector3:
    return au_pos * SYSTEM_SCALE

func get_position_in_au(visual_pos: Vector3) -> Dictionary:
    var au_pos = visual_to_au(visual_pos)
    return {
        "x": au_pos.x,
        "y": au_pos.y,
        "z": au_pos.z,
        "distance_au": au_pos.length()
    }

func get_nearest_object_at_position(visual_pos: Vector3) -> Dictionary:
    var au_pos = visual_to_au(visual_pos)
    var nearest = {}
    var nearest_dist = INF
    
    # Check stars
    for node in star_nodes:
        var star_au = visual_to_au(node.global_position)
        var dist = au_pos.distance_to(star_au)
        if dist < nearest_dist:
            nearest_dist = dist
            nearest = {
                "type": "Star",
                "index": node.star_index,
                "data": node.star_data,
                "distance_au": dist,
                "position_au": {"x": star_au.x, "y": star_au.y, "z": star_au.z}
            }
    
    # Check planets
    for node in planet_nodes:
        var planet_au = visual_to_au(node.global_position)
        var dist = au_pos.distance_to(planet_au)
        if dist < nearest_dist:
            nearest_dist = dist
            nearest = {
                "type": "Planet",
                "index": node.planet_index,
                "data": node.planet_data,
                "distance_au": dist,
                "position_au": {"x": planet_au.x, "y": planet_au.y, "z": planet_au.z}
            }
    
    return nearest

func get_object_position_in_au(obj_type: String, index: int) -> Dictionary:
    var node = find_object_node(obj_type, index)
    if node:
        return get_position_in_au(node.global_position)
    return {}

func _create_circle_mesh(radius: float, segments: int) -> ArrayMesh:
    var mesh = ArrayMesh.new()
    var vertices = PackedVector3Array()
    
    for i in range(segments + 1):
        var angle = float(i) / float(segments) * TAU
        vertices.append(Vector3(cos(angle) * radius, 0, sin(angle) * radius))
    
    var arrays = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
    return mesh

func render_asteroid_belts(belts: Array):
    if asteroid_belt_viz == null or asteroid_belt_viz.multimesh == null:
        return
    
    var all_asteroids = []
    for belt in belts:
        for asteroid in belt.get("largest_bodies", []):
            asteroid["belt_name"] = belt.get("name", "Belt")
            all_asteroids.append(asteroid)
    
    var count = all_asteroids.size()
    if count == 0:
        asteroid_belt_viz.multimesh.instance_count = 0
        return
    
    var multimesh = asteroid_belt_viz.multimesh
    multimesh.instance_count = 0  # Reset before changing use_colors
    multimesh.use_colors = true
    multimesh.instance_count = count
    
    for i in range(count):
        var asteroid = all_asteroids[i]
        var pos = asteroid.get("position", {})
        
        var asteroid_pos = Vector3(
            pos.get("x", 0.0) * SYSTEM_SCALE,
            pos.get("y", 0.0) * SYSTEM_SCALE,
            pos.get("z", 0.0) * SYSTEM_SCALE
        )
        
        var size = 0.005 + asteroid.get("diameter", 100.0) / 10000.0
        
        var transform = Transform3D()
        transform.basis = transform.basis.scaled(Vector3(size, size, size))
        transform.origin = asteroid_pos
        multimesh.set_instance_transform(i, transform)
        multimesh.set_instance_color(i, Color(0.5, 0.45, 0.4, 1.0))

func render_distant_stars(nearby_stars: Dictionary, current_star_pos: Vector3):
    if distant_stars == null or distant_stars.multimesh == null:
        return
    
    var positions: PackedVector3Array = nearby_stars.get("positions", PackedVector3Array())
    var luminosities: PackedFloat32Array = nearby_stars.get("luminosities", PackedFloat32Array())
    var temperatures: PackedFloat32Array = nearby_stars.get("temperatures", PackedFloat32Array())
    
    print("render_distant_stars called with ", positions.size(), " nearby stars")
    
    var count = positions.size() - 1
    if count <= 0:
        distant_stars.multimesh.instance_count = 0
        return
    
    print("Rendering ", count, " distant stars")
    
    var multimesh = distant_stars.multimesh
    multimesh.instance_count = 0  # Reset before changing use_colors
    multimesh.use_colors = true
    multimesh.instance_count = count
    
    var idx = 0
    for i in range(positions.size()):
        if idx >= count:
            break
        
        var star_world_pos = positions[i]
        
        # Get direction relative to current star's galactic position
        var relative_pos = star_world_pos - current_star_pos
        var dir = relative_pos.normalized()
        if dir.length() < 0.1:
            continue
        
        var distant_pos = dir * DISTANT_STAR_SCALE
        var luminosity = luminosities[i]
        # Scale down to small points - at 5000 units, sizes 0.5-3.0 appear as distant pinpoints
        var size = clamp(log(luminosity + 1.0) * 0.5 + 0.5, 0.5, 3.0)
        
        var instance_transform = Transform3D()
        instance_transform.basis = instance_transform.basis.scaled(Vector3(size, size, size))
        instance_transform.origin = distant_pos
        multimesh.set_instance_transform(idx, instance_transform)
        
        var temp = temperatures[i]
        multimesh.set_instance_color(idx, temperature_to_color(temp))
        idx += 1

func temperature_to_color(temp: float) -> Color:
    return MeiUtils.temperature_to_color(temp)

func get_recommended_camera_position() -> Vector3:
    # Position camera to see the star well
    # Star diameter is ~0.0093 AU, so at SYSTEM_SCALE it's 0.0093 * SYSTEM_SCALE visual units
    # Position camera at ~2.5x star diameter distance for a good view
    var star_diameter = 0.0093 * SYSTEM_SCALE
    return Vector3(0, star_diameter * 0.5, star_diameter * 2.5)

func get_system_velocity_scale() -> float:
    return SYSTEM_SCALE

# For compatibility with main.gd picking - find object by type and index
func find_object_node(obj_type: String, index: int) -> Node3D:
    match obj_type:
        "Star":
            if index < star_nodes.size():
                return star_nodes[index]
        "Planet":
            if index < planet_nodes.size():
                return planet_nodes[index]
        "Moon":
            if index < moon_nodes.size():
                return moon_nodes[index]
    return null

# Legacy compatibility for main.gd
var pickable_objects: Array:
    get:
        var result = []
        for node in star_nodes:
            result.append({
                "position": node.global_position,
                "radius": node.scale.x * 0.5,
                "type": "Star",
                "index": node.star_index,
                "data": node.star_data
            })
        for node in planet_nodes:
            result.append({
                "position": node.global_position,
                "radius": node.scale.x * 0.5,
                "type": "Planet",
                "index": node.planet_index,
                "data": node.planet_data
            })
        for node in moon_nodes:
            result.append({
                "position": node.global_position,
                "radius": node.scale.x * 0.5,
                "type": "Moon",
                "planet_index": node.planet_index,
                "index": node.moon_index,
                "data": node.moon_data
            })
        return result

func pick_object_at_ray(ray_origin: Vector3, ray_dir: Vector3, max_distance: float = 10000.0) -> Dictionary:
    # Use Godot's physics raycast with collision layer 2 (pickable objects)
    var space_state = get_world_3d().direct_space_state
    var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * max_distance)
    query.collision_mask = 2  # Only hit layer 2 (pickable objects)
    
    var result = space_state.intersect_ray(query)
    
    if result.is_empty():
        return {}
    
    # Get the collider and find its parent (the SystemStar/Planet/Moon node)
    var collider = result.collider
    var parent = collider.get_parent()
    
    # Build dictionary matching the old format for compatibility
    if parent is SystemStar:
        return {
            "type": "Star",
            "index": parent.star_index,
            "data": parent.star_data,
            "position": parent.global_position,
            "radius": parent.scale.x * 0.5
        }
    elif parent is SystemPlanet:
        return {
            "type": "Planet",
            "index": parent.planet_index,
            "data": parent.planet_data,
            "position": parent.global_position,
            "radius": parent.scale.x * 0.5
        }
    elif parent is SystemMoon:
        return {
            "type": "Moon",
            "index": parent.moon_index,
            "planet_index": parent.planet_index,
            "data": parent.moon_data,
            "position": parent.global_position,
            "radius": parent.scale.x * 0.5
        }
    
    return {}

func pick_orbit_at_position(world_pos: Vector3) -> Dictionary:
    var inner = current_system.get("inner_planets", [])
    var outer = current_system.get("outer_planets", [])
    var all_planets = inner + outer
    
    var click_dist_from_center = Vector2(world_pos.x, world_pos.z).length()
    
    for i in range(all_planets.size()):
        var planet = all_planets[i]
        var orbital_radius = planet.get("orbital_radius", planet.get("position", {}).get("x", 1.0)) * SYSTEM_SCALE
        
        # Precise orbit picking - small tolerance
        var tolerance = orbital_radius * 0.02  # 2% of orbital radius for precise selection
        if abs(click_dist_from_center - orbital_radius) < tolerance:
            return {"type": "Planet", "index": i, "data": planet}
    
    var belts = current_system.get("asteroid_belts", [])
    for i in range(belts.size()):
        var belt = belts[i]
        var inner_r = belt.get("inner_radius", 0.0) * SYSTEM_SCALE
        var outer_r = belt.get("outer_radius", 0.0) * SYSTEM_SCALE
        
        if click_dist_from_center >= inner_r and click_dist_from_center <= outer_r:
            return {"type": "AsteroidBelt", "index": i, "data": belt}
    
    return {}

func get_object_tooltip(obj: Dictionary) -> String:
    if obj.is_empty():
        return ""
    
    var obj_type = obj.get("type", "")
    var data = obj.get("data", {})
    
    match obj_type:
        "Star":
            return data.get("star_type", "Star")
        "Planet":
            return data.get("planet_type", "Planet") + " " + str(obj.get("index", 0) + 1)
        "Moon":
            return "Moon " + str(obj.get("index", 0) + 1)
        "AsteroidBelt":
            return data.get("name", "Asteroid Belt")
    
    return ""

func select_object(obj: Dictionary):
    if obj.is_empty():
        clear_selection()
        return
    
    var obj_type = obj.get("type", "")
    var index = obj.get("index", 0)
    var node = find_object_node(obj_type, index)
    
    if node:
        select_object_node(node)
    else:
        # Fallback for objects without nodes (like asteroid belts)
        var pos = obj.get("position", Vector3.ZERO)
        var radius = obj.get("radius", 0.5)
        var marker_size = radius * 2.5
        selection_marker.scale = Vector3(marker_size, marker_size, marker_size)
        selection_marker.global_position = pos
        selection_marker.visible = true
