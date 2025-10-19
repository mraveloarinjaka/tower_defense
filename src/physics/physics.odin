package physics

import "core:log"
import "core:math"

import b2 "vendor:box2d"

PHYSICS_SCALE :: 30.0 // Pixels per meter for b2
VELOCITY_ITERATIONS :: 4
POSITION_ITERATIONS :: 2

ScreenPosition :: [2]f32

PhysicsWorld :: struct {
	world:       b2.WorldId,
	bodies:      map[string]b2.BodyId,
	projectiles: map[b2.BodyId]string,
	enemies:     map[b2.BodyId]string,
	debug_draw:  bool,
}

// Initialize physics world
init_physics :: proc() -> PhysicsWorld {
	physics: PhysicsWorld

	// Create b2 world with zero gravity (top-down game)
	world_def := b2.DefaultWorldDef()
	world_def.gravity = b2.Vec2{0, 0}
	physics.world = b2.CreateWorld(world_def)

	physics.bodies = make(map[string]b2.BodyId)
	physics.debug_draw = true

	return physics
}

destroy_physics :: proc(physics: ^PhysicsWorld) {
	delete(physics.enemies)
	delete(physics.projectiles)
	for _, body in physics.bodies {
		b2.DestroyBody(body)
	}
	delete(physics.bodies)
	b2.DestroyWorld(physics.world)
}

// Update physics world
update_physics :: proc(physics: ^PhysicsWorld, time_step: f32) {
	b2.World_Step(
		physics.world,
		time_step,
		VELOCITY_ITERATIONS,
		//, POSITION_ITERATIONS
	)
}

// Create a static body (for walls, obstacles, tower base)
toWorldPosition :: proc(position: ScreenPosition) -> b2.Vec2 {
	return b2.Vec2{position.x / PHYSICS_SCALE, position.y / PHYSICS_SCALE}
}

create_static_body :: proc(
	physics: ^PhysicsWorld,
	extent: ScreenPosition,
	width, height: f32,
) -> b2.BodyId {
	body_def := b2.DefaultBodyDef()
	body_def.type = .staticBody
	body_def.position = toWorldPosition(extent)

	body := b2.CreateBody(physics.world, body_def)

	body_shape_def := b2.DefaultShapeDef()
	body_shape_def.density = 0.0 // Static bodies have zero density
	body_shape_def.material.friction = 0.3
	body_shape_def.material.restitution = 0.1 // Slight bounce

	body_shape_def.filter.categoryBits = u64(bit_set[BodyType]{.WALL})

	box_shape := b2.CreatePolygonShape(
		body,
		body_shape_def,
		b2.MakeBox(width / (2 * PHYSICS_SCALE), height / (2 * PHYSICS_SCALE)),
	)

	return body
}

// Create a circular static body (for tower)
create_static_circle :: proc(
	physics: ^PhysicsWorld,
	name: string,
	center: ScreenPosition,
	radius: f32,
) -> b2.BodyId {
	// Create body definition
	body_def := b2.DefaultBodyDef()
	body_def.type = .staticBody
	body_def.position = toWorldPosition(center)

	// Create body
	body := b2.CreateBody(physics.world, body_def)

	body_shape_def := b2.DefaultShapeDef()
	body_shape_def.density = 0.0 // Static bodies have zero density
	body_shape_def.material.friction = 0.3
	body_shape_def.material.restitution = 0.1 // Slight bounce

	// Create circle shape
	circle_shape := b2.CreateCircleShape(
		body,
		body_shape_def,
		b2.Circle{body_def.position, radius / PHYSICS_SCALE},
	)

	return body
}

BodyType :: enum {
	WALL,
	ENEMY,
	PROJECTILE,
}

// Create a dynamic body (for enemies)
create_dynamic_body :: proc(
	physics: ^PhysicsWorld,
	categoryBits: u64,
	maskBits: u64,
	position: ScreenPosition,
	radius: f32,
) -> b2.BodyId {
	body_def := b2.DefaultBodyDef()
	body_def.type = .dynamicBody
	body_def.position = toWorldPosition(position)
	body_def.linearDamping = 0.5 // Add some damping to prevent excessive sliding

	body := b2.CreateBody(physics.world, body_def)

	body_shape_def := b2.DefaultShapeDef()
	body_shape_def.density = 1.0
	body_shape_def.material.friction = 0.3
	body_shape_def.material.restitution = 0.2 // Slight bounce

	// Add user data for collision filtering
	body_shape_def.enableContactEvents = true
	body_shape_def.filter.categoryBits = categoryBits
	body_shape_def.filter.maskBits = maskBits

	circle_shape := b2.CreateCircleShape(
		body,
		body_shape_def,
		b2.Circle{body_def.position, radius / PHYSICS_SCALE},
	)

	return body
}

create_projectile :: proc(
	physics: ^PhysicsWorld,
	name: string,
	position: ScreenPosition,
	radius: f32,
) -> b2.BodyId {
	body := create_dynamic_body(
		physics,
		u64(bit_set[BodyType]{.PROJECTILE}),
		u64(bit_set[BodyType]{.ENEMY}),
		position,
		radius,
	)
	physics.bodies[name] = body
	physics.projectiles[body] = name
	return body
}

create_enemy :: proc(
	physics: ^PhysicsWorld,
	name: string,
	position: ScreenPosition,
	radius: f32,
) -> b2.BodyId {
	body := create_dynamic_body(
		physics,
		u64(bit_set[BodyType]{.ENEMY}),
		u64(bit_set[BodyType]{.PROJECTILE, .ENEMY, .WALL}),
		position,
		radius,
	)
	physics.bodies[name] = body
	physics.enemies[body] = name
	return body
}

// Create a sensor (for tower range detection)
//create_sensor :: proc(physics: ^PhysicsWorld, name: string, x, y, radius: f32) -> b2.BodyId {
//   body_def := b2.DefaultBodyDef()
//   body_def.type = .staticBody
//   body_def.position = b2.Vec2{x / PHYSICS_SCALE, y / PHYSICS_SCALE}

//   body := b2.CreateBody(physics.world, body_def)

//   // Create circle shape
//   shape_def := b2.DefaultShapeDef()
//   shape_def.isSensor = true
//   // Add user data for collision filtering
//   shape_def.filter.categoryBits = 0x0004 // Sensor category
//   shape_def.filter.maskBits = 0x0002 // Only detect enemies

//   circle_shape := b2.CreateCircleShape(
//      body,
//      shape_def,
//      b2.Circle{{0, 0}, radius / PHYSICS_SCALE},
//   )

//   physics.bodies[name] = body

//   return body
//}

// Apply force to move a body towards a target
move_body_towards :: proc(
	physics: ^PhysicsWorld,
	body_name: string,
	target_name: string,
	force_magnitude: f32,
) {
	body, body_exists := physics.bodies[body_name]
	_, target_exists := physics.bodies[target_name]

	if !(body_exists && target_exists) {
		return
	}

	// Get positions
	current_x, current_y := get_body_position(physics, body_name)
	target_x, target_y := get_body_position(physics, target_name)

	// Calculate direction
	dir_x := target_x - current_x
	dir_y := target_y - current_y
	distance := math.sqrt(dir_x * dir_x + dir_y * dir_y)

	// Normalize direction
	if distance > 0 {
		dir_x /= distance
		dir_y /= distance
	}

	// Apply force
	force := b2.Vec2{dir_x * force_magnitude, dir_y * force_magnitude}
	b2.Body_ApplyForceToCenter(body, force, true)
}

// Get position of a body
get_body_position :: proc(physics: ^PhysicsWorld, body_name: string) -> (x, y: f32) {
	body, exists := physics.bodies[body_name]
	if !exists {
		return 0, 0
	}

	position := b2.Body_GetPosition(body)
	return position.x * PHYSICS_SCALE, position.y * PHYSICS_SCALE
}

// Check if two bodies are colliding
check_collision :: proc(physics: ^PhysicsWorld, body_name_a, body_name_b: string) -> bool {
	body_a, exists_a := physics.bodies[body_name_a]
	if !exists_a {
		return false
	}
	body_b, exists_b := physics.bodies[body_name_b]
	if !exists_b {
		return false
	}

	// Get first shape of each body
	tmp: [2]b2.ShapeId
	shapes_a := b2.Body_GetShapes(body_a, tmp[0:1])
	shapes_b := b2.Body_GetShapes(body_b, tmp[1:])
	if shapes_a == nil || shapes_b == nil {
		return false
	}

	shape_a := shapes_a[0]
	shape_b := shapes_b[0]

	// Overlap test using current transforms
	xf_a := b2.Body_GetTransform(body_a)
	xf_b := b2.Body_GetTransform(body_b)

	// If your binding exposes Shape_TestOverlap instead, swap the call accordingly.
	//return b2.Shape_TestOverlap(shape_a, 0, shape_b, 0, xf_a, xf_b)
	return false
}


// Calculate distance between two bodies
calculate_distance :: proc(physics: ^PhysicsWorld, body_name_a, body_name_b: string) -> f32 {
	x1, y1 := get_body_position(physics, body_name_a)
	x2, y2 := get_body_position(physics, body_name_b)

	dx := x2 - x1
	dy := y2 - y1

	return math.sqrt(dx * dx + dy * dy)
}

// Create boundary walls for the game area

Location :: enum {
	TOP,
	BOTTOM,
	LEFT,
	RIGHT,
}

WALLS: [Location]string = {
	.TOP    = "wall_top",
	.BOTTOM = "wall_bottom",
	.LEFT   = "wall_left",
	.RIGHT  = "wall_right",
}

create_boundaries :: proc(physics: ^PhysicsWorld, width, height: f32) {
	wall_thickness :: 10

	physics.bodies[WALLS[.TOP]] = create_static_body(
		physics,
		{width / 2, wall_thickness / 2},
		width,
		wall_thickness,
	)

	physics.bodies[WALLS[.BOTTOM]] = create_static_body(
		physics,
		{width / 2, height - (wall_thickness / 2)},
		width,
		wall_thickness,
	)

	physics.bodies[WALLS[.LEFT]] = create_static_body(
		physics,
		{wall_thickness / 2, height / 2},
		wall_thickness,
		height,
	)

	physics.bodies[WALLS[.RIGHT]] = create_static_body(
		physics,
		{width - (wall_thickness / 2), height / 2},
		wall_thickness,
		height,
	)
}

create_tower :: proc(physics: ^PhysicsWorld, name: string, center: ScreenPosition, radius: f32) {
	physics.bodies[name] = create_static_circle(physics, name, center, 20)
}

// Remove a body from the physics world
remove_body :: proc(physics: ^PhysicsWorld, body_name: string) {
	body, exists := physics.bodies[body_name]
	if exists {
		b2.DestroyBody(body)
		delete_key(&physics.bodies, body_name)
	}
}

distance :: proc(world: ^PhysicsWorld, from, to: string) -> f32 {
	// Get tower position
	from_x, from_y := get_body_position(world, from)

	// Get target position
	to_x, to_y := get_body_position(world, to)

	// Calculate distance
	dx := to_x - from_x
	dy := to_y - from_y
	return math.sqrt(dx * dx + dy * dy)
}

Colliding :: map[string]struct{}

check_collisions :: proc(physics: ^PhysicsWorld) -> Colliding {
	colliding : Colliding
	events := b2.World_GetContactEvents(physics.world)
	if events.beginCount > 0 {
		for event_idx in 0 ..< events.beginCount {
			event := events.beginEvents[event_idx]
			bodyA := b2.Shape_GetBody(event.shapeIdA)
			bodyB := b2.Shape_GetBody(event.shapeIdB)
			if (bodyA in physics.projectiles && bodyB in physics.enemies) ||
			   (bodyA in physics.enemies && bodyB in physics.projectiles) {
				if name, ok := physics.projectiles[bodyA]; ok {
					log.debugf("collision detected with projectile %v", name)
					colliding[name] = {}
				}
				if name, ok := physics.projectiles[bodyB]; ok {
					log.debugf("collision detected with projectile %v", name)
					colliding[name] = {}
				}
			}
		}
	}
	return colliding
}
