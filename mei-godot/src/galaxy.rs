use godot::prelude::*;
use godot::classes::Node;
use mei::api::galaxy_api::{GalaxyAPI, SystemQuery};
use mei::generation::config::GeneratorConfig;
use mei::util::vec::Vec3;

/// MEI Galaxy node for Godot - provides direct access to galaxy generation
#[derive(GodotClass)]
#[class(base=Node)]
pub struct MeiGalaxy {
    base: Base<Node>,
    #[var]
    seed: i64,
    api: Option<GalaxyAPI>,
}

#[godot_api]
impl INode for MeiGalaxy {
    /// Initializes a new `MeiGalaxy` instance.
    ///
    /// # Arguments
    ///
    /// * `base` - The Godot Node base
    ///
    /// # Returns
    ///
    /// A new `MeiGalaxy` instance with default seed (0) and uninitialized API
    fn init(base: Base<Node>) -> Self {
        Self {
            base,
            seed: 0,
            api: None,
        }
    }

    /// Called when the node is ready in the Godot scene tree.
    ///
    /// Initializes the galaxy API with the current seed value.
    fn ready(&mut self) {
        self.api = Some(GalaxyAPI::new(self.seed as u64));
        godot_print!("MeiGalaxy initialized with seed {}", self.seed);
    }
}

#[godot_api]
impl MeiGalaxy {
    /// Sets the galaxy seed and reinitializes the generator.
    ///
    /// # Arguments
    ///
    /// * `seed` - The seed value for procedural generation
    ///
    /// # Examples
    ///
    /// ```gdscript
    /// galaxy.set_galaxy_seed(42)
    /// ```
    #[func]
    fn set_galaxy_seed(&mut self, seed: i64) {
        self.seed = seed;
        self.api = Some(GalaxyAPI::new(self.seed as u64));
        godot_print!("MeiGalaxy seed changed to {}", self.seed);
    }

    /// Loads generator configuration from a TOML file and reinitializes.
    ///
    /// # Arguments
    ///
    /// * `path` - Path to the TOML configuration file
    ///
    /// # Examples
    ///
    /// ```gdscript
    /// galaxy.load_config("res://config/galaxy.toml")
    /// ```
    #[func]
    fn load_config(&mut self, path: GString) {
        let config = GeneratorConfig::load_from_file(&path.to_string());
        self.api = Some(GalaxyAPI::new_with_config(self.seed as u64, config.clone()));
        godot_print!("MeiGalaxy config loaded from {}: nearby_max_radius={}, structure_block_size={}", 
            path, config.nearby_max_radius, config.structure_block_size);
    }

    /// Sets the maximum radius for nearby star queries.
    ///
    /// # Arguments
    ///
    /// * `radius` - Maximum radius in light-years
    #[func]
    fn set_nearby_max_radius(&mut self, radius: f64) {
        if let Some(api) = &mut self.api {
            api.generator.config.nearby_max_radius = radius;
            godot_print!("MeiGalaxy nearby_max_radius set to {}", radius);
        }
    }

    /// Gets the current maximum radius for nearby star queries.
    ///
    /// # Returns
    ///
    /// Maximum radius in light-years (default: 16.0)
    #[func]
    fn get_nearby_max_radius(&self) -> f64 {
        self.api.as_ref().map(|api| api.generator.config.nearby_max_radius).unwrap_or(16.0)
    }

    /// Sets the structure block size, affecting galactic structure sampling resolution.
    ///
    /// # Arguments
    ///
    /// * `size` - Block size in light-years
    #[func]
    fn set_structure_block_size(&mut self, size: f64) {
        if let Some(api) = &mut self.api {
            api.generator.config.structure_block_size = size;
            godot_print!("MeiGalaxy structure_block_size set to {}", size);
        }
    }

    /// Sets the number of samples per structure block, affecting sampling density.
    ///
    /// # Arguments
    ///
    /// * `samples` - Number of samples per block
    #[func]
    fn set_structure_samples_per_block(&mut self, samples: i64) {
        if let Some(api) = &mut self.api {
            api.generator.config.structure_samples_per_block = samples as u64;
            godot_print!("MeiGalaxy structure_samples_per_block set to {}", samples);
        }
    }

    /// Retrieves galactic structure as packed arrays for efficient rendering.
    ///
    /// # Arguments
    ///
    /// * `max_stars` - Maximum number of stars to return
    ///
    /// # Returns
    ///
    /// A `Dictionary` containing:
    /// - `positions`: `PackedVector3Array` of star positions
    /// - `ids`: `PackedInt64Array` of star IDs
    /// - `luminosities`: `PackedFloat32Array` of star luminosities
    /// - `temperatures`: `PackedFloat32Array` of star temperatures
    /// - `masses`: `PackedFloat32Array` of star masses
    /// - `star_types`: `PackedStringArray` of star type names
    /// - `count`: Number of stars returned
    /// - `estimated_total_stars`: Estimated total stars in galaxy
    #[func]
    fn get_structure(&self, max_stars: i64) -> Dictionary {
        let Some(api) = &self.api else {
            godot_error!("MeiGalaxy not initialized");
            return Dictionary::new();
        };

        let stars = api.generator.get_galactic_structure(max_stars as usize);
        let count = stars.len();
        
        let mut positions = PackedVector3Array::new();
        let mut ids = PackedInt64Array::new();
        let mut luminosities = PackedFloat32Array::new();
        let mut temperatures = PackedFloat32Array::new();
        let mut masses = PackedFloat32Array::new();
        let mut star_types = PackedStringArray::new();
        
        for star in &stars {
            positions.push(Vector3::new(
                star.position.x as f32,
                star.position.y as f32,
                star.position.z as f32,
            ));
            ids.push(star.id as i64);
            luminosities.push(star.luminosity() as f32);
            temperatures.push(star.temperature() as f32);
            masses.push(star.mass as f32);
            star_types.push(&GString::from(format!("{:?}", star.star_type)));
        }
        
        let estimated_total = api.generator.estimate_total_stars(500.0);
        
        let mut result = Dictionary::new();
        result.set("positions", positions);
        result.set("ids", ids);
        result.set("luminosities", luminosities);
        result.set("temperatures", temperatures);
        result.set("masses", masses);
        result.set("star_types", star_types);
        result.set("count", count as i64);
        result.set("estimated_total_stars", estimated_total as i64);

        godot_print!("Generated {} stars (packed), estimated total: {}", count, estimated_total);
        result
    }

    /// Gets the galaxy radius.
    ///
    /// # Returns
    ///
    /// Galaxy radius in light-years, or 0.0 if not initialized
    #[func]
    fn get_galaxy_radius(&self) -> f64 {
        let Some(api) = &self.api else {
            return 0.0;
        };
        api.generator.galaxy.radius
    }

    /// Gets nearby stars at a specific position as packed arrays.
    ///
    /// Uses a default maximum of 10,000 stars to match the Rust viewer's limit.
    ///
    /// # Arguments
    ///
    /// * `x` - X coordinate in light-years
    /// * `y` - Y coordinate in light-years
    /// * `z` - Z coordinate in light-years
    /// * `radius` - Search radius in light-years (clamped to `nearby_max_radius`)
    ///
    /// # Returns
    ///
    /// A `Dictionary` with the same structure as `get_structure`
    #[func]
    fn get_nearby_stars(&mut self, x: f64, y: f64, z: f64, radius: f64) -> Dictionary {
        self.get_nearby_stars_limited(x, y, z, radius, 10000)
    }
    
    /// Gets nearby stars with an explicit maximum limit as packed arrays.
    ///
    /// # Arguments
    ///
    /// * `x` - X coordinate in light-years
    /// * `y` - Y coordinate in light-years
    /// * `z` - Z coordinate in light-years
    /// * `radius` - Search radius in light-years (clamped to `nearby_max_radius`)
    /// * `max_stars` - Maximum number of stars to return
    ///
    /// # Returns
    ///
    /// A `Dictionary` containing:
    /// - `positions`: `PackedVector3Array` of star positions
    /// - `ids`: `PackedInt64Array` of star IDs
    /// - `luminosities`: `PackedFloat32Array` of star luminosities
    /// - `temperatures`: `PackedFloat32Array` of star temperatures
    /// - `masses`: `PackedFloat32Array` of star masses
    /// - `star_types`: `PackedStringArray` of star type names
    /// - `count`: Number of stars returned
    #[func]
    fn get_nearby_stars_limited(&mut self, x: f64, y: f64, z: f64, radius: f64, max_stars: i64) -> Dictionary {
        let Some(api) = &mut self.api else {
            godot_error!("MeiGalaxy not initialized");
            return Dictionary::new();
        };

        let position = Vec3::new(x, y, z);
        let clamped_radius = radius.min(api.generator.config.nearby_max_radius);
        let stars = api.generator.get_nearby_stars(&position, radius, max_stars as usize);
        let count = stars.len();
        
        let mut positions = PackedVector3Array::new();
        let mut ids = PackedInt64Array::new();
        let mut luminosities = PackedFloat32Array::new();
        let mut temperatures = PackedFloat32Array::new();
        let mut masses = PackedFloat32Array::new();
        let mut star_types = PackedStringArray::new();
        
        for star in &stars {
            positions.push(Vector3::new(
                star.position.x as f32,
                star.position.y as f32,
                star.position.z as f32,
            ));
            ids.push(star.id as i64);
            luminosities.push(star.star_type.luminosity() as f32);
            temperatures.push(star.star_type.temperature() as f32);
            masses.push(star.mass as f32);
            star_types.push(&GString::from(format!("{:?}", star.star_type)));
        }
        
        let mut result = Dictionary::new();
        result.set("positions", positions);
        result.set("ids", ids);
        result.set("luminosities", luminosities);
        result.set("temperatures", temperatures);
        result.set("masses", masses);
        result.set("star_types", star_types);
        result.set("count", count as i64);

        godot_print!("Found {} nearby stars at ({:.1}, {:.1}, {:.1}) radius {} ly (clamped to {} ly)", count, x, y, z, radius, clamped_radius);
        result
    }

    /// Retrieves a detailed star system by star ID.
    ///
    /// # Arguments
    ///
    /// * `star_id` - The unique identifier for the star
    ///
    /// # Returns
    ///
    /// A `Dictionary` containing complete system information:
    /// - `star_id`: The queried star ID
    /// - `position`: System position in galactic coordinates
    /// - `stars`: Array of star data (mass, luminosity, temperature, type)
    /// - `configuration`: Stellar configuration (Single, Binary, Triple, etc.)
    /// - `stellar_components`: Individual stellar components with their planets
    /// - `inner_planets`: Rocky planets inside frost line
    /// - `outer_planets`: Gas/ice giants beyond frost line
    /// - `asteroid_belts`: Asteroid belt data
    /// - `oort_cloud`: Oort cloud data (if present)
    /// - `frost_line`: Frost line distance in AU
    /// - `habitable_zone_inner`: Inner edge of habitable zone in AU
    /// - `habitable_zone_outer`: Outer edge of habitable zone in AU
    #[func]
    fn get_star_system(&self, star_id: GString) -> Dictionary {
        let Some(api) = &self.api else {
            godot_error!("MeiGalaxy not initialized");
            return Dictionary::new();
        };

        let query = SystemQuery {
            star_id: star_id.to_string(),
            position: None,
        };

        let system = api.get_star_system(&query);

        let mut result = Dictionary::new();
        result.set("star_id", star_id.clone());
        result.set("frost_line", system.frost_line);
        result.set("habitable_zone_inner", system.habitable_zone_inner);
        result.set("habitable_zone_outer", system.habitable_zone_outer);
        
        // Position
        let mut pos = Dictionary::new();
        pos.set("x", system.position.x);
        pos.set("y", system.position.y);
        pos.set("z", system.position.z);
        result.set("position", pos);
        
        // Stars (can be multiple in binary/trinary systems)
        let mut stars_arr = Array::<Dictionary>::new();
        for star in &system.stars {
            let mut star_dict = Dictionary::new();
            star_dict.set("id", star.id as i64);
            star_dict.set("star_type", format!("{:?}", star.star_type).to_godot());
            star_dict.set("mass", star.mass);
            star_dict.set("luminosity", star.star_type.luminosity());
            star_dict.set("temperature", star.star_type.temperature());
            
            let mut star_pos = Dictionary::new();
            star_pos.set("x", star.position.x);
            star_pos.set("y", star.position.y);
            star_pos.set("z", star.position.z);
            star_dict.set("position", star_pos);
            
            stars_arr.push(&star_dict);
        }
        result.set("stars", stars_arr);
        
        // Stellar configuration
        let config_dict = match &system.configuration {
            mei::space_objects::system::StellarConfiguration::Single => {
                let mut d = Dictionary::new();
                d.set("type", "Single".to_godot());
                d
            }
            mei::space_objects::system::StellarConfiguration::CloseBinary { separation_au, is_contact } => {
                let mut d = Dictionary::new();
                d.set("type", "CloseBinary".to_godot());
                d.set("separation_au", *separation_au);
                d.set("is_contact", *is_contact);
                d
            }
            mei::space_objects::system::StellarConfiguration::WideBinary { separation_au } => {
                let mut d = Dictionary::new();
                d.set("type", "WideBinary".to_godot());
                d.set("separation_au", *separation_au);
                d
            }
            mei::space_objects::system::StellarConfiguration::HierarchicalTriple { inner_separation_au, outer_separation_au } => {
                let mut d = Dictionary::new();
                d.set("type", "HierarchicalTriple".to_godot());
                d.set("inner_separation_au", *inner_separation_au);
                d.set("outer_separation_au", *outer_separation_au);
                d
            }
            mei::space_objects::system::StellarConfiguration::UnstableTriple => {
                let mut d = Dictionary::new();
                d.set("type", "UnstableTriple".to_godot());
                d
            }
        };
        result.set("configuration", config_dict);
        
        // Stellar components (each can have planets orbiting)
        let mut components_arr = Array::<Dictionary>::new();
        for component in &system.stellar_components {
            let mut comp_dict = Dictionary::new();
            
            // Star indices in this component
            let mut indices = PackedInt64Array::new();
            for idx in &component.star_indices {
                indices.push(*idx as i64);
            }
            comp_dict.set("star_indices", indices);
            
            // Barycenter position (AU)
            let mut bary = Dictionary::new();
            bary.set("x", component.barycenter.x);
            bary.set("y", component.barycenter.y);
            bary.set("z", component.barycenter.z);
            comp_dict.set("barycenter", bary);
            
            comp_dict.set("combined_mass", component.combined_mass);
            comp_dict.set("internal_separation", component.internal_separation);
            comp_dict.set("is_interacting", component.is_interacting);
            comp_dict.set("planet_inner_limit", component.planet_inner_limit);
            comp_dict.set("planet_outer_limit", component.planet_outer_limit);
            comp_dict.set("frost_line", component.frost_line);
            comp_dict.set("habitable_zone_inner", component.habitable_zone_inner);
            comp_dict.set("habitable_zone_outer", component.habitable_zone_outer);
            
            // Inner planets for this component
            let mut inner = Array::<Dictionary>::new();
            for planet in &component.inner_planets {
                inner.push(&planet_to_dict(planet));
            }
            comp_dict.set("inner_planets", inner);
            
            // Outer planets for this component
            let mut outer = Array::<Dictionary>::new();
            for planet in &component.outer_planets {
                outer.push(&planet_to_dict(planet));
            }
            comp_dict.set("outer_planets", outer);
            
            components_arr.push(&comp_dict);
        }
        result.set("stellar_components", components_arr);

        // Inner planets
        let mut inner_planets = Array::<Dictionary>::new();
        for planet in &system.inner_planets {
            inner_planets.push(&planet_to_dict(planet));
        }
        result.set("inner_planets", inner_planets);

        // Outer planets
        let mut outer_planets = Array::<Dictionary>::new();
        for planet in &system.outer_planets {
            outer_planets.push(&planet_to_dict(planet));
        }
        result.set("outer_planets", outer_planets);

        // Asteroid belts
        let mut asteroid_belts = Array::<Dictionary>::new();
        for belt in &system.asteroid_belts {
            asteroid_belts.push(&asteroid_belt_to_dict(belt));
        }
        result.set("asteroid_belts", asteroid_belts);

        // Oort cloud (if present)
        if let Some(oort) = &system.oort_cloud {
            result.set("oort_cloud", oort_cloud_to_dict(oort));
        }

        let total_planets = system.inner_planets.len() + system.outer_planets.len();
        let total_moons: usize = system.inner_planets.iter().chain(system.outer_planets.iter())
            .map(|p| p.moons.len()).sum();
        godot_print!("System has {} stars, {} planets, {} moons, {} asteroid belts", 
            system.stars.len(), total_planets, total_moons, system.asteroid_belts.len());
        result
    }
}

/// Converts a planet to a Godot Dictionary.
///
/// # Arguments
///
/// * `planet` - Reference to the planet object
///
/// # Returns
///
/// A `Dictionary` containing planet data:
/// - `planet_type`: Type of planet (Terrestrial, GasGiant, IceGiant, Dwarf)
/// - `mass`: Planet mass in Earth masses
/// - `orbital_radius`: Distance from star in AU
/// - `position`: 3D position vector
/// - `moons`: Array of moon dictionaries
/// - `moon_count`: Number of moons
fn planet_to_dict(planet: &mei::space_objects::planet::Planet) -> Dictionary {
    let mut dict = Dictionary::new();
    
    // Map planet type to string
    let planet_type_str = match planet.planet_type {
        mei::space_objects::planet::PlanetType::Dwarf => "Dwarf",
        mei::space_objects::planet::PlanetType::Terrestrial => "Terrestrial",
        mei::space_objects::planet::PlanetType::SuperEarth => "SuperEarth",
        mei::space_objects::planet::PlanetType::Desert => "Desert",
        mei::space_objects::planet::PlanetType::Ocean => "Ocean",
        mei::space_objects::planet::PlanetType::Lava => "Lava",
        mei::space_objects::planet::PlanetType::MiniNeptune => "MiniNeptune",
        mei::space_objects::planet::PlanetType::SubNeptune => "SubNeptune",
        mei::space_objects::planet::PlanetType::IceGiant => "IceGiant",
        mei::space_objects::planet::PlanetType::GasGiant => "GasGiant",
        mei::space_objects::planet::PlanetType::HotJupiter => "HotJupiter",
        mei::space_objects::planet::PlanetType::Chthonian => "Chthonian",
        mei::space_objects::planet::PlanetType::Carbon => "Carbon",
        mei::space_objects::planet::PlanetType::Coreless => "Coreless",
    };
    dict.set("planet_type", planet_type_str.to_godot());
    dict.set("mass", planet.mass);
    dict.set("orbital_radius", planet.position.x); // x position is orbital radius in AU
    
    let mut pos = Dictionary::new();
    pos.set("x", planet.position.x);
    pos.set("y", planet.position.y);
    pos.set("z", planet.position.z);
    dict.set("position", pos);
    
    // Moons with full detail (using same pattern as stars_arr which works)
    let mut moons_arr = Array::<Dictionary>::new();
    for moon in &planet.moons {
        moons_arr.push(&moon_to_dict(moon));
    }
    dict.set("moons", moons_arr);
    dict.set("moon_count", planet.moons.len() as i64);
    dict
}

/// Converts a moon to a Godot Dictionary.
///
/// # Arguments
///
/// * `moon` - Reference to the moon object
///
/// # Returns
///
/// A `Dictionary` containing moon data:
/// - `moon_type`: Type of moon (Rock, Ice, Water, Gas)
/// - `mass`: Moon mass in lunar masses
/// - `orbital_radius`: Distance from planet in kilometers
/// - `position`: 3D position vector
fn moon_to_dict(moon: &mei::space_objects::moon::Moon) -> Dictionary {
    let mut dict = Dictionary::new();
    
    let moon_type_str = match moon.moon_type {
        mei::space_objects::moon::MoonType::Rocky => "Rocky",
        mei::space_objects::moon::MoonType::Icy => "Icy",
        mei::space_objects::moon::MoonType::IceRock => "IceRock",
        mei::space_objects::moon::MoonType::Ocean => "Ocean",
        mei::space_objects::moon::MoonType::Volcanic => "Volcanic",
        mei::space_objects::moon::MoonType::Captured => "Captured",
        mei::space_objects::moon::MoonType::Atmospheric => "Atmospheric",
    };
    dict.set("moon_type", moon_type_str.to_godot());
    dict.set("mass", moon.mass);
    dict.set("orbital_radius", moon.position.x); // x position is orbital radius in km
    
    let mut pos = Dictionary::new();
    pos.set("x", moon.position.x);
    pos.set("y", moon.position.y);
    pos.set("z", moon.position.z);
    dict.set("position", pos);
    
    dict
}

/// Converts an asteroid belt to a Godot Dictionary.
///
/// # Arguments
///
/// * `belt` - Reference to the asteroid belt object
///
/// # Returns
///
/// A `Dictionary` containing asteroid belt data:
/// - `name`: Belt name
/// - `inner_radius`: Inner radius in AU
/// - `outer_radius`: Outer radius in AU
/// - `total_mass`: Total mass of the belt
/// - `asteroid_count`: Number of asteroids
/// - `largest_bodies`: Array of notable asteroid dictionaries
fn asteroid_belt_to_dict(belt: &mei::space_objects::asteroid::AsteroidBelt) -> Dictionary {
    let mut dict = Dictionary::new();
    
    dict.set("name", belt.name.to_godot());
    dict.set("inner_radius", belt.inner_radius);
    dict.set("outer_radius", belt.outer_radius);
    dict.set("total_mass", belt.total_mass);
    dict.set("asteroid_count", belt.asteroid_count as i64);
    
    // Notable/largest bodies
    let mut asteroids = Array::<Dictionary>::new();
    for asteroid in &belt.largest_bodies {
        asteroids.push(&asteroid_to_dict(asteroid));
    }
    dict.set("largest_bodies", asteroids);
    
    dict
}

/// Converts an asteroid to a Godot Dictionary.
///
/// # Arguments
///
/// * `asteroid` - Reference to the asteroid object
///
/// # Returns
///
/// A `Dictionary` containing asteroid data:
/// - `asteroid_type`: Type of asteroid (Carbonaceous, Silicate, Metallic)
/// - `mass`: Asteroid mass
/// - `diameter`: Diameter in kilometers
/// - `orbital_radius`: Distance from star in AU
/// - `position`: 3D position vector
fn asteroid_to_dict(asteroid: &mei::space_objects::asteroid::Asteroid) -> Dictionary {
    let mut dict = Dictionary::new();
    
    let asteroid_type_str = match asteroid.asteroid_type {
        mei::space_objects::asteroid::AsteroidType::Carbonaceous => "Carbonaceous",
        mei::space_objects::asteroid::AsteroidType::Silicate => "Silicate",
        mei::space_objects::asteroid::AsteroidType::Metallic => "Metallic",
    };
    dict.set("asteroid_type", asteroid_type_str.to_godot());
    dict.set("mass", asteroid.mass);
    dict.set("diameter", asteroid.diameter);
    dict.set("orbital_radius", asteroid.orbital_radius);
    
    let mut pos = Dictionary::new();
    pos.set("x", asteroid.position.x);
    pos.set("y", asteroid.position.y);
    pos.set("z", asteroid.position.z);
    dict.set("position", pos);
    
    dict
}

/// Converts an Oort cloud to a Godot Dictionary.
///
/// # Arguments
///
/// * `oort` - Reference to the Oort cloud object
///
/// # Returns
///
/// A `Dictionary` containing Oort cloud data:
/// - `inner_radius`: Inner radius in AU
/// - `outer_radius`: Outer radius in AU
/// - `estimated_population`: Estimated number of objects
/// - `total_mass`: Total mass of the cloud
/// - `notable_comets`: Array of notable comet dictionaries
fn oort_cloud_to_dict(oort: &mei::space_objects::comet::OortCloud) -> Dictionary {
    let mut dict = Dictionary::new();
    
    dict.set("inner_radius", oort.inner_radius);
    dict.set("outer_radius", oort.outer_radius);
    dict.set("estimated_population", oort.estimated_population as i64);
    dict.set("total_mass", oort.total_mass);
    
    // Notable comets
    let mut comets = Array::<Dictionary>::new();
    for comet in &oort.notable_comets {
        comets.push(&comet_to_dict(comet));
    }
    dict.set("notable_comets", comets);
    
    dict
}

/// Converts a comet to a Godot Dictionary.
///
/// # Arguments
///
/// * `comet` - Reference to the comet object
///
/// # Returns
///
/// A `Dictionary` containing comet data:
/// - `comet_type`: Type of comet (ShortPeriod, LongPeriod, Hyperbolic)
/// - `mass`: Comet mass
/// - `nucleus_diameter`: Diameter of nucleus in kilometers
/// - `orbital_radius`: Semi-major axis in AU
/// - `eccentricity`: Orbital eccentricity
/// - `position`: 3D position vector
fn comet_to_dict(comet: &mei::space_objects::comet::Comet) -> Dictionary {
    let mut dict = Dictionary::new();
    
    let comet_type_str = match comet.comet_type {
        mei::space_objects::comet::CometType::ShortPeriod => "ShortPeriod",
        mei::space_objects::comet::CometType::LongPeriod => "LongPeriod",
        mei::space_objects::comet::CometType::Hyperbolic => "Hyperbolic",
    };
    dict.set("comet_type", comet_type_str.to_godot());
    dict.set("mass", comet.mass);
    dict.set("nucleus_diameter", comet.nucleus_diameter);
    dict.set("orbital_radius", comet.orbital_radius);
    dict.set("eccentricity", comet.eccentricity);
    
    let mut pos = Dictionary::new();
    pos.set("x", comet.position.x);
    pos.set("y", comet.position.y);
    pos.set("z", comet.position.z);
    dict.set("position", pos);
    
    dict
}
