extends Node3D
class_name SystemStar

var mesh: MeshInstance3D
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D
var accretion_disk: MeshInstance3D = null
var pulse_light: OmniLight3D = null

var star_data: Dictionary = {}
var star_index: int = 0
var star_type: String = ""
var pulse_time: float = 0.0

# Exotic star type identifiers
const COMPACT_TYPES = ["NeutronStar", "Pulsar", "Magnetar", "BlackHole", "WhiteDwarf"]
const PULSING_TYPES = ["Pulsar", "Magnetar", "CataclysmicVariable"]

func _process(delta: float):
	if star_type in PULSING_TYPES:
		pulse_time += delta
		_update_pulse_effect()

func setup(data: Dictionary, index: int, size: float):
	star_data = data
	star_index = index
	star_type = data.get("star_type", "YellowStar")
	
	# Get nodes directly since setup is called before _ready
	mesh = $Mesh
	collision_body = $CollisionBody
	collision_shape = $CollisionBody/CollisionShape
	
	# Scale the mesh - compact objects are much smaller visually
	var visual_size = size
	if star_type in COMPACT_TYPES:
		visual_size = size * 0.1  # Compact objects are tiny
		if star_type == "BlackHole":
			visual_size = size * 0.05  # Black holes even smaller (event horizon)
	
	scale = Vector3(visual_size, visual_size, visual_size)
	
	# Setup collision shape
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 0.5
	collision_shape.shape = sphere_shape
	
	# Set appearance based on star type
	_setup_star_appearance(data, visual_size)
	
	# Store metadata for picking
	set_meta("object_type", "Star")
	set_meta("object_index", index)
	set_meta("object_data", data)

func _setup_star_appearance(data: Dictionary, size: float):
	var temp = data.get("temperature", 5000.0)
	var luminosity = data.get("luminosity", 1.0)
	var mat = mesh.get_surface_override_material(0).duplicate()
	
	match star_type:
		"BlackHole":
			_setup_black_hole(mat, size)
		"NeutronStar":
			_setup_neutron_star(mat, temp, luminosity)
		"Pulsar":
			_setup_pulsar(mat, temp, luminosity)
		"Magnetar":
			_setup_magnetar(mat, temp, luminosity)
		"WhiteDwarf":
			_setup_white_dwarf(mat, temp, luminosity)
		"WolfRayet":
			_setup_wolf_rayet(mat, temp, luminosity)
		"CarbonStar":
			_setup_carbon_star(mat, luminosity)
		_:
			_setup_normal_star(mat, temp, luminosity)
	
	mesh.set_surface_override_material(0, mat)
	
	# Configure light based on star properties
	_configure_star_light(temp, luminosity)

func _configure_star_light(temp: float, luminosity: float):
	"""Configure the omni light based on star's physical properties.
	
	Uses high energy with low attenuation to simulate realistic light falloff.
	At SYSTEM_SCALE=1000, 1 AU = 1000 visual units.
	Light follows inverse-square law: intensity = luminosity / distance^2
	"""
	var light = get_node_or_null("OmniLight3D")
	if light == null:
		return
	
	# Set light color from temperature
	light.light_color = MeiUtils.temperature_to_color(temp)
	
	# Use low attenuation for gradual falloff (0 = no falloff, 1 = linear, 2 = inverse square)
	# Lower values mean light reaches further with less falloff
	light.omni_attenuation = 0.15
	
	# Keep range reasonable - this is the hard cutoff
	light.omni_range = 4096.0
	
	# Scale energy very high to compensate for attenuation over distance
	# At 1 AU (1000 units) with attenuation 0.5, we want reasonable brightness
	# Energy needs to be high enough that falloff still provides visible light
	# Base: Sun-like star (luminosity=1) should illuminate planets nicely
	var base_energy = 16.0  # Base energy for luminosity = 1
	var energy = base_energy * luminosity
	energy = clamp(energy, 0.5, 1000.0)
	light.light_energy = energy

func _setup_normal_star(mat: StandardMaterial3D, temp: float, luminosity: float):
	var color = MeiUtils.temperature_to_color(temp)
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0 + luminosity * 0.5

func _setup_black_hole(mat: StandardMaterial3D, size: float):
	# Black hole: pure black sphere with no emission
	mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	mat.emission_enabled = false
	mat.metallic = 1.0
	mat.roughness = 0.0
	
	# Create accretion disk
	_create_accretion_disk(size)
	
	# Disable the light for black holes
	var light = get_node_or_null("OmniLight3D")
	if light:
		light.visible = false

func _setup_neutron_star(mat: StandardMaterial3D, _temp: float, _luminosity: float):
	# Neutron stars: extremely hot, blue-white, small
	var color = Color(0.7, 0.8, 1.0, 1.0)
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 5.0

func _setup_pulsar(mat: StandardMaterial3D, _temp: float, _luminosity: float):
	# Pulsar: like neutron star but with pulsing effect
	var color = Color(0.6, 0.7, 1.0, 1.0)
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	
	# Add a secondary light for pulse effect
	_create_pulse_light(color)

func _setup_magnetar(mat: StandardMaterial3D, _temp: float, _luminosity: float):
	# Magnetar: intense purple-blue glow
	var color = Color(0.6, 0.3, 1.0, 1.0)
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 8.0
	
	# Add pulsing light
	_create_pulse_light(color)

func _setup_white_dwarf(mat: StandardMaterial3D, temp: float, _luminosity: float):
	# White dwarf: hot but dim, blue-white
	var color = MeiUtils.temperature_to_color(temp)
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.0  # Dim

func _setup_wolf_rayet(mat: StandardMaterial3D, _temp: float, _luminosity: float):
	# Wolf-Rayet: extremely hot, blue with intense stellar wind appearance
	var color = Color(0.5, 0.6, 1.0, 1.0)
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 10.0

func _setup_carbon_star(mat: StandardMaterial3D, _luminosity: float):
	# Carbon star: deep red, cool
	var color = Color(1.0, 0.3, 0.1, 1.0)
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0

func _create_accretion_disk(_star_size: float):
	# Create a torus-like disk around black hole
	accretion_disk = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 2.0
	torus.outer_radius = 8.0
	torus.rings = 32
	torus.ring_segments = 64
	accretion_disk.mesh = torus
	
	# Accretion disk material - hot glowing gas
	var disk_mat = StandardMaterial3D.new()
	disk_mat.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
	disk_mat.emission_enabled = true
	disk_mat.emission = Color(1.0, 0.5, 0.1, 1.0)
	disk_mat.emission_energy_multiplier = 5.0
	disk_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	accretion_disk.material_override = disk_mat
	
	# Tilt the disk slightly
	accretion_disk.rotation_degrees.x = 75.0
	
	add_child(accretion_disk)

func _create_pulse_light(color: Color):
	pulse_light = OmniLight3D.new()
	pulse_light.light_color = color
	pulse_light.omni_range = 100.0
	pulse_light.light_energy = 2.0
	add_child(pulse_light)

func _update_pulse_effect():
	if pulse_light == null:
		return
	
	var pulse_freq = 2.0  # Hz
	if star_type == "Magnetar":
		pulse_freq = 0.5  # Slower, more dramatic
	elif star_type == "CataclysmicVariable":
		pulse_freq = 0.1  # Very slow, irregular
	
	var pulse_value = (sin(pulse_time * pulse_freq * TAU) + 1.0) / 2.0
	pulse_light.light_energy = 1.0 + pulse_value * 5.0
	
	# Also pulse the emission on the mesh
	var mat = mesh.get_surface_override_material(0)
	if mat:
		mat.emission_energy_multiplier = 3.0 + pulse_value * 5.0
