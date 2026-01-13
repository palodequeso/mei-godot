extends Node3D
class_name SystemPlanet

var mesh: MeshInstance3D
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D

var planet_data: Dictionary = {}
var planet_index: int = 0

func setup(data: Dictionary, index: int, size: float):
    planet_data = data
    planet_index = index
    
    # Get nodes directly since setup is called before _ready
    mesh = $Mesh
    collision_body = $CollisionBody
    collision_shape = $CollisionBody/CollisionShape
    
    # Scale the mesh
    scale = Vector3(size, size, size)
    
    # Setup collision shape
    var sphere_shape = SphereShape3D.new()
    sphere_shape.radius = 0.5  # Will be scaled with node
    collision_shape.shape = sphere_shape
    
    # Set texture and color based on planet type
    var planet_type = data.get("planet_type", "Terrestrial")
    var planet_id = data.get("id", index)  # Use planet ID for consistent texture selection
    
    var mat = mesh.get_surface_override_material(0).duplicate()
    
    # Try to load a texture first
    var texture_path = MeiUtils.get_planet_texture(planet_type, planet_id)
    print("Planet ", planet_index, " (", planet_type, "): trying texture ", texture_path)
    
    if texture_path != "" and ResourceLoader.exists(texture_path):
        var texture = load(texture_path)
        if texture != null:
            mat.albedo_texture = texture
            # Use white albedo to show texture colors accurately
            mat.albedo_color = Color.WHITE
            print("  -> Texture loaded successfully")
        else:
            # Fallback to color only
            mat.albedo_color = MeiUtils.get_planet_color(planet_type)
            print("  -> Texture failed to load, using color")
    else:
        # Fallback to color only
        mat.albedo_color = MeiUtils.get_planet_color(planet_type)
        print("  -> Texture path invalid or doesn't exist, using color")
    
    mesh.set_surface_override_material(0, mat)
    
    # Store metadata for picking
    set_meta("object_type", "Planet")
    set_meta("object_index", index)
    set_meta("object_data", data)
