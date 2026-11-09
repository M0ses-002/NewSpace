extends Node2D

const Orbit = preload("res://scripts/kepler_orbit.gd")
var team: String
var attraction_radius: float
var collision_radius: float
var orbit: Dictionary
var center: Vector2
var mean_anomaly: float
var direction: float
var mu: float

func initialize(origin: Vector2, velocity: Vector2, focus: Vector2, gravity: float, faction: String, settings: Dictionary) -> bool:
	center = focus
	mu = gravity
	team = faction
	attraction_radius = float(settings.attraction_radius_km)
	collision_radius = float(settings.radius_km)
	var r := origin - center
	var radius := r.length()
	if radius <= 0.000001 or mu <= 0.0:
		return false
	var energy := velocity.length_squared() * 0.5 - mu / radius
	var momentum := r.cross(velocity)
	var eccentricity := Vector2(velocity.y * momentum / mu, -velocity.x * momentum / mu) - r / radius
	if energy < 0.0 and absf(momentum) > 0.000001 and eccentricity.length() < 1.0:
		orbit = Orbit.make(-mu / (2.0 * energy), eccentricity.length(), eccentricity.angle() if eccentricity.length() > 0.000001 else 0.0)
		direction = 1.0 if momentum > 0.0 else -1.0
	else:
		orbit = Orbit.make(radius, 0.0, r.angle())
		direction = -1.0 if momentum < 0.0 else 1.0
	mean_anomaly = Orbit.mean_at(orbit, r)
	global_position = origin
	$Body.color = Color("#ff9b55") if team == "enemy" else Color("#66ccff")
	return true

func advance(dt: float) -> void:
	mean_anomaly += direction * sqrt(mu / pow(float(orbit.a), 3)) * dt
	global_position = center + Orbit.state_at(orbit, mean_anomaly, direction, mu).position
