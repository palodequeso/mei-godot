extends Node3D
class_name SystemMoon

var mesh: MeshInstance3D
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D

var moon_data: Dictionary = {}
var moon_index: int = 0
var planet_index: int = 0

func setup(data: Dictionary, index: int, p_index: int, size: float):
	moon_data = data
	moon_index = index
	planet_index = p_index
	
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
	
	# Set material with white albedo
	var mat = mesh.get_surface_override_material(0).duplicate()
	mat.albedo_color = Color.WHITE
	mesh.set_surface_override_material(0, mat)
	
	# Store metadata for picking
	set_meta("object_type", "Moon")
	set_meta("object_index", index)
	set_meta("planet_index", p_index)
	set_meta("object_data", data)
