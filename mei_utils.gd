extends Node

## Shared utility functions for MEI viewer
## Registered as autoload "MeiUtils"

# =============================================================================
# REALISTIC SCALE CONSTANTS (in AU)
# =============================================================================
# 1 AU = 149,597,870.7 km (Earth-Sun distance)
# All sizes are DIAMETERS in AU for direct use as object scale
#
# Reference objects:
# - Sun diameter: 0.00930 AU (1,392,680 km)
# - Jupiter diameter: 0.000954 AU (142,984 km) - 11.2x Earth
# - Earth diameter: 0.0000852 AU (12,742 km)
# - Moon diameter: 0.0000232 AU (3,474 km)
# - Earth-Moon distance: 0.00257 AU (384,400 km)
# =============================================================================

# Conversion constants
const KM_PER_AU: float = 149597870.7
const SOLAR_RADIUS_AU: float = 0.00465  # Sun radius in AU
const EARTH_RADIUS_AU: float = 0.0000426  # Earth radius in AU
const JUPITER_RADIUS_AU: float = 0.000477  # Jupiter radius in AU

# Planet type colors - based on actual planetary appearances
const PLANET_COLORS = {
	"GasGiant": Color(0.85, 0.65, 0.45, 1.0),    # Jupiter - tan/orange bands
	"IceGiant": Color(0.4, 0.6, 0.85, 1.0),      # Neptune/Uranus - blue-cyan
	"Terrestrial": Color(0.35, 0.45, 0.65, 1.0), # Earth-like - blue with hints
	"Dwarf": Color(0.55, 0.5, 0.45, 1.0),        # Rocky/cratered - gray-brown
}

# Realistic planet radius ranges by type (in Earth radii)
# Based on actual solar system and exoplanet data
# Note: No minimum clamping - let the physics formulas determine size
const PLANET_RADIUS_RANGES = {
	"GasGiant": {"min": 5.0, "max": 12.0},     # Saturn=9.4, Jupiter=11.2 Earth radii
	"IceGiant": {"min": 2.0, "max": 4.5},      # Uranus=4.0, Neptune=3.9 Earth radii
	"Terrestrial": {"min": 0.3, "max": 1.8},   # Mars=0.53, Earth=1.0, super-Earths ~1.5
	"Dwarf": {"min": 0.05, "max": 0.4},        # Pluto=0.19, Ceres=0.07 Earth radii
}

## Convert stellar temperature (Kelvin) to RGB color
## Based on realistic blackbody radiation and stellar spectral classes
## Reference: Mitchell Charity's "What color are the stars?" and CIE color matching
func temperature_to_color(temp: float) -> Color:
	# Clamp temperature to reasonable stellar range
	temp = clamp(temp, 1000.0, 40000.0)
	
	var r: float
	var g: float
	var b: float
	
	# Using realistic color values for stellar spectral classes
	# Based on blackbody radiation chromaticity
	if temp < 2400:
		# Very cool (L/T class brown dwarfs) - deep red
		r = 1.0
		g = 0.2 + 0.15 * (temp / 2400.0)
		b = 0.05
	elif temp < 3700:
		# M class (Red dwarfs, red giants) - orange-red
		var t = (temp - 2400.0) / 1300.0
		r = 1.0
		g = 0.35 + 0.35 * t
		b = 0.08 + 0.17 * t
	elif temp < 5200:
		# K class (Orange stars) - orange to pale orange-white
		var t = (temp - 3700.0) / 1500.0
		r = 1.0
		g = 0.75 + 0.15 * t
		b = 0.4 + 0.4 * t
	elif temp < 6000:
		# G class (Yellow stars like Sun) - nearly white with very slight warmth
		# Sun at 5778K appears white to pale yellow-white
		var t = (temp - 5200.0) / 800.0
		r = 1.0
		g = 0.95 + 0.03 * t
		b = 0.85 + 0.13 * t
	elif temp < 7500:
		# F class (Yellow-white stars) - white with barely perceptible warmth
		var t = (temp - 6000.0) / 1500.0
		r = 1.0 - 0.02 * t
		g = 0.98 - 0.01 * t
		b = 0.98 + 0.02 * t
	elif temp < 10000:
		# A class (White stars like Sirius, Vega) - pure white to blue-white
		var t = (temp - 7500.0) / 2500.0
		r = 0.98 - 0.15 * t
		g = 0.97 - 0.07 * t
		b = 1.0
	elif temp < 30000:
		# B class (Blue-white stars) - distinctly blue
		var t = clamp((temp - 10000.0) / 20000.0, 0.0, 1.0)
		r = 0.8 - 0.25 * t
		g = 0.85 - 0.15 * t
		b = 1.0
	else:
		# O class (Blue stars, hottest) - deep blue
		var t = clamp((temp - 30000.0) / 10000.0, 0.0, 1.0)
		r = 0.55 - 0.1 * t
		g = 0.7 - 0.1 * t
		b = 1.0
	
	return Color(r, g, b, 1.0)

## Get color for a planet type
func get_planet_color(planet_type: String) -> Color:
	return PLANET_COLORS.get(planet_type, Color(0.5, 0.5, 0.5, 1.0))

## Get random texture path for a planet type
func get_planet_texture(planet_type: String, planet_id: int = 0) -> String:
	# Use planet_id as seed for consistent texture selection per planet
	var rng = RandomNumberGenerator.new()
	rng.seed = planet_id
	
	var texture_folders = []
	
	match planet_type:
		"GasGiant":
			texture_folders = ["Gaseous", "Methane"]
		"IceGiant":
			texture_folders = ["Snowy", "Tundra"]
		"Terrestrial":
			texture_folders = ["Grassland", "Jungle", "Marshy", "Sandy", "Arid"]
		"Dwarf":
			texture_folders = ["Barren", "Dusty", "Martian"]
		_:
			texture_folders = ["Barren"]  # Default fallback
	
	# Pick random folder
	var folder = texture_folders[rng.randi() % texture_folders.size()]
	
	# Get available textures in that folder
	var dir = DirAccess.open("res://assets/PlanetTextures/" + folder)
	if dir == null:
		return ""  # Folder doesn't exist
	
	var textures = []
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".png") and not file_name.ends_with(".import"):
			textures.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	if textures.is_empty():
		return ""  # No textures found
	
	# Pick random texture
	var texture_file = textures[rng.randi() % textures.size()]
	return "res://assets/PlanetTextures/" + folder + "/" + texture_file

## Calculate REALISTIC diameter for a planet based on type and mass (in AU)
## Uses mass-radius relationship: R ∝ M^0.27 for rocky, R ∝ M^0.5 for gas giants
func get_planet_size(planet_type: String, mass: float) -> float:
	var ranges = PLANET_RADIUS_RANGES.get(planet_type, {"min": 0.5, "max": 2.0})
	var radius_earth: float
	
	match planet_type:
		"GasGiant":
			# Gas giants: R ∝ M^0.5 (roughly), mass in Jupiter masses
			# Jupiter = 318 Earth masses, radius = 11.2 Earth radii
			var mass_jupiter = mass / 318.0
			radius_earth = 11.2 * pow(mass_jupiter, 0.5)
		"IceGiant":
			# Ice giants: similar scaling, mass in Neptune masses
			# Neptune = 17 Earth masses, radius = 3.88 Earth radii
			var mass_neptune = mass / 17.0
			radius_earth = 3.88 * pow(mass_neptune, 0.4)
		"Terrestrial":
			# Rocky planets: R ∝ M^0.27 (tighter relationship)
			radius_earth = pow(mass, 0.27)
		"Dwarf":
			# Small bodies: R ∝ M^0.3
			radius_earth = 0.4 * pow(mass + 0.01, 0.3)
		_:
			radius_earth = pow(mass, 0.27)
	
	radius_earth = clamp(radius_earth, ranges["min"], ranges["max"])
	
	# Convert to diameter in AU (Earth radius = 0.0000426 AU)
	return radius_earth * EARTH_RADIUS_AU * 2.0

## Calculate REALISTIC diameter for a star based on luminosity (in AU)
## Uses different relationships for different stellar types
func get_star_size(luminosity: float, _scale_factor: float = 0.5) -> float:
	var radius_solar: float
	
	if luminosity < 0.01:
		# Very dim red dwarfs: R ∝ L^0.1 (they're small but not as small as sqrt suggests)
		# Proxima Centauri: L=0.0017, R=0.154
		radius_solar = 0.15 * pow(luminosity / 0.001, 0.1)
	elif luminosity < 1.0:
		# Red/orange dwarfs: R ∝ L^0.25 (main sequence M/K stars)
		# Better fit for low-mass main sequence stars
		radius_solar = pow(luminosity, 0.25)
	elif luminosity < 100.0:
		# Sun-like to bright stars: R ∝ L^0.5
		radius_solar = pow(luminosity, 0.5)
	else:
		# Giants and supergiants: can be very large
		radius_solar = pow(luminosity, 0.6)
	
	# Clamp to reasonable stellar sizes (0.08 to 2000 solar radii)
	radius_solar = clamp(radius_solar, 0.08, 2000.0)
	# Return diameter in AU
	return radius_solar * SOLAR_RADIUS_AU * 2.0

## Get moon diameter in AU based on mass (in Earth masses)
func get_moon_size(mass: float) -> float:
	# Moons follow rocky body scaling: R ∝ M^0.27
	# Our Moon: mass = 0.0123 Earth masses, radius = 0.273 Earth radii
	var radius_earth = 0.273 * pow(mass / 0.0123, 0.27)
	radius_earth = clamp(radius_earth, 0.05, 0.5)  # 0.05 to 0.5 Earth radii
	return radius_earth * EARTH_RADIUS_AU * 2.0
