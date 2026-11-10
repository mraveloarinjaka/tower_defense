package game

import "../physics"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"
import "core:time"

import rl "vendor:raylib"

// Game constants
SCREEN_WIDTH :: 1024 // Window/UI width in px
SCREEN_HEIGHT :: 768 // Window/UI height in px
TITLE :: "Tower Defense Game"
TARGET_FPS :: 60

// World-space arena dimensions in meters
WORLD_WIDTH :: 68.0
WORLD_HEIGHT :: 50.0
SPAWN_MARGIN :: 0.6666667

// Tower defaults
DEFAULT_TOWER_HEALTH :: 100
DEFAULT_TOWER_DAMAGE :: 10
DEFAULT_TOWER_RANGE :: 5.0 // meters
DEFAULT_TOWER_COOLDOWN :: 1.0

// Tower tuning limits, used to keep interactive edits playable
MIN_TOWER_DAMAGE :: 1
MAX_TOWER_DAMAGE :: 1000
MIN_TOWER_RANGE :: 0.6666667 // meters
MAX_TOWER_RANGE :: 20.0 // meters
MIN_TOWER_COOLDOWN :: 0.05
MAX_TOWER_COOLDOWN :: 3.0

GameState :: enum {
	MENU,
	PLAYING,
	GAME_OVER,
}

EnemyType :: enum {
	BASIC,
	FAST,
	TANK,
}

TowerType :: enum {
	BASIC,
}

TOWER_RADIUS :: 1.0 // Collision radius of the tower body (m)
ORBIT_GAP_MIN :: 0.2 // Min extra clearance between enemy edge and tower edge while orbiting (m)
ORBIT_ENGAGE_RANGE :: 2.0 // Enemies switch to orbiting once within this distance of the ring (m)

// Projectile defaults
PROJECTILE_RADIUS :: 0.1666667 // Collision radius (m)
PROJECTILE_THRUST_N :: 200.0 // Propulsion force (N)

// Enemy structure
Enemy :: struct {
	id:              string,
	type:            EnemyType,
	health:          int,
	max_health:      int,
	thrust_n:        f32, // Propulsion force used when chasing (N)
	orbit_speed_mps: f32, // Tangential orbit speed (m/s)
	damage:          int,
	active:          bool,
	value:           int, // Score value when defeated
	radius:          f32, // Collision radius (m)
	orbit_direction: f32, // +1 or -1, chosen at spawn
	orbit_mix:       f32, // 0..1, where the orbit ring sits between min clearance and tower range
	orbiting:        bool, // True once the enemy has reached the orbit ring
}

// Tower structure
Tower :: struct {
	id:             string,
	type:           TowerType,
	health:         int,
	max_health:     int,
	damage:         int,
	range:          f32, // Targeting range (m)
	cooldown:       f32,
	cooldown_timer: f32,
	center:         [2]f32, // World position (m)
	radius:         f32, // Collision radius (m)
	target:         string, // ID of the current target enemy
}

// Projectile structure
Projectile :: struct {
	id:       string,
	damage:   int,
	thrust_n: f32, // Propulsion force (N)
	target:   string, // ID of the target enemy
	active:   bool,
}

// Game context
Game :: struct {
	state:            GameState,
	physics:          physics.PhysicsWorld,
	tower:            Tower,
	enemies:          [dynamic]Enemy,
	projectiles:      [dynamic]Projectile,
	score:            int,
	wave:             int,
	lives:            int,
	enemy_count:      int, // Counter for generating unique enemy IDs
	projectile_count: int, // Counter for generating unique projectile IDs
	spawn_timer:      f32,
	spawn_interval:   f32,
	game_time:        f32,
}

// Initialize the game
init_game :: proc() -> Game {
	game: Game
	game.state = .MENU

	// Initialize physics
	game.physics = physics.init_physics()

	// Create game boundaries (world meters)
	physics.create_boundaries(&game.physics, WORLD_WIDTH, WORLD_HEIGHT)

	// Initialize tower at the arena center (world meters)
	game.tower = create_tower(&game, WORLD_WIDTH / 2.0, WORLD_HEIGHT / 2.0)

	// Initialize enemies array
	game.enemies = make([dynamic]Enemy)

	// Initialize projectiles array
	game.projectiles = make([dynamic]Projectile)

	// Initialize game state
	game.score = 0
	game.wave = 1
	game.lives = 10
	game.enemy_count = 0
	game.projectile_count = 0
	game.spawn_timer = 0
	game.spawn_interval = 2.0 // Seconds between enemy spawns
	game.game_time = 0

	return game
}

// Clean up game resources
destroy_game :: proc(game: ^Game) {
	for &projectile in game.projectiles {
		destroy_projectile(&projectile)
	}
	delete(game.projectiles)
	for &enemy in game.enemies {
		destroy_enemy(&enemy)
	}
	delete(game.enemies)

	// Clean up physics
	physics.destroy_physics(&game.physics)
}

// Create a tower
create_tower :: proc(game: ^Game, x, y: f32) -> Tower {
	tower: Tower
	tower.id = "tower"
	tower.type = .BASIC
	tower.health = DEFAULT_TOWER_HEALTH
	tower.max_health = DEFAULT_TOWER_HEALTH
	tower.damage = DEFAULT_TOWER_DAMAGE
	tower.range = DEFAULT_TOWER_RANGE
	tower.cooldown = DEFAULT_TOWER_COOLDOWN
	tower.cooldown_timer = 0
	tower.center = {x, y}
	tower.radius = TOWER_RADIUS

	// Create physics body for tower
	physics.create_tower(&game.physics, tower.id, {x, y}, tower.radius)

	//// Create range sensor
	//physics.create_sensor(&game.physics, "tower_range", x, y, tower.range)

	return tower
}

// Keep tower tuning values within playable limits.
// A cooldown of 0 would spawn a projectile (and its physics body) every frame.
clamp_tower_tuning :: proc(tower: ^Tower) {
	tower.damage = clamp(tower.damage, MIN_TOWER_DAMAGE, MAX_TOWER_DAMAGE)
	tower.range = clamp(tower.range, MIN_TOWER_RANGE, MAX_TOWER_RANGE)
	tower.cooldown = clamp(tower.cooldown, MIN_TOWER_COOLDOWN, MAX_TOWER_COOLDOWN)

	// Do not make the tower wait longer than the new cooldown.
	tower.cooldown_timer = clamp(tower.cooldown_timer, 0, tower.cooldown)
}

// Restore the default tuning values (health is intentionally left untouched).
reset_tower_tuning :: proc(tower: ^Tower) {
	tower.damage = DEFAULT_TOWER_DAMAGE
	tower.range = DEFAULT_TOWER_RANGE
	tower.cooldown = DEFAULT_TOWER_COOLDOWN
	tower.cooldown_timer = 0
}

// Create an enemy
create_enemy :: proc(game: ^Game, x, y: f32, type: EnemyType) -> Enemy {
	enemy: Enemy
	enemy.type = type

	// Generate unique ID
	game.enemy_count += 1
	enemy.id = strings.clone(fmt.tprintf("enemy_%d", game.enemy_count))

	// Set properties based on type
	physics_radius: f32
	switch type {
	case .BASIC:
		enemy.health = 30
		enemy.max_health = 30
		enemy.thrust_n = 50.0
		enemy.orbit_speed_mps = 1.6666667
		enemy.damage = 5
		enemy.value = 10
		physics_radius = 0.3333333

	case .FAST:
		enemy.health = 15
		enemy.max_health = 15
		enemy.thrust_n = 80.0
		enemy.orbit_speed_mps = 2.6666667
		enemy.damage = 3
		enemy.value = 15
		physics_radius = 0.2666667

	case .TANK:
		enemy.health = 60
		enemy.max_health = 60
		enemy.thrust_n = 30.0
		enemy.orbit_speed_mps = 1.0
		enemy.damage = 10
		enemy.value = 20
		physics_radius = 0.5
	}
	physics.create_enemy(&game.physics, enemy.id, {x, y}, physics_radius)

	enemy.active = true
	enemy.radius = physics_radius
	enemy.orbit_direction = 1
	if rand.int_max(2) == 0 {
		enemy.orbit_direction = -1
	}
	enemy.orbit_mix = rand.float32()
	enemy.orbiting = false

	return enemy
}

destroy_enemy :: proc(enemy: ^Enemy) {
	delete(enemy.id)
}

create_projectile :: proc(game: ^Game, source, target: string, damage: int) -> Projectile {
	projectile: Projectile

	game.projectile_count += 1
	projectile.id = strings.clone(fmt.tprintf("projectile_%d", game.projectile_count))
	projectile.damage = damage
	projectile.thrust_n = PROJECTILE_THRUST_N
	projectile.target = target
	projectile.active = true

	source_x, source_y := physics.get_body_position(&game.physics, source)
	target_x, target_y := physics.get_body_position(&game.physics, target)

	// Spawn at the rim of the firing tower, toward the target, so the
	// projectile body starts outside the tower's collision circle instead
	// of embedded inside it.
	dx := target_x - source_x
	dy := target_y - source_y
	target_distance := math.sqrt(dx * dx + dy * dy)
	if target_distance > 0 {
		rim_fraction := (game.tower.radius + PROJECTILE_RADIUS) / target_distance
		source_x += dx * rim_fraction
		source_y += dy * rim_fraction
	}

	physics.create_projectile(&game.physics, projectile.id, {source_x, source_y}, PROJECTILE_RADIUS)

	return projectile
}

destroy_projectile :: proc(projectile: ^Projectile) {
	delete(projectile.id)
}

// Update the game state
update_game :: proc(game: ^Game, delta_time: f32) {
	if game.state == .PLAYING {
		// Update game time
		game.game_time += delta_time

		// Update physics
		physics.update_physics(&game.physics, delta_time)

		// Update tower
		update_tower(game, delta_time)

		collisions := physics.check_collisions(&game.physics)
		defer {
			delete(collisions.enemies_to_projectiles)
			delete(collisions.projectiles_to_enemies)
			delete(collisions.projectiles_to_walls)
		}

		// Update enemies
		update_enemies(game, collisions, delta_time)

		// Update projectiles
		update_projectiles(game, collisions, delta_time)

		// Handle enemy spawning
		game.spawn_timer -= delta_time
		if game.spawn_timer <= 0 {
			spawn_enemy(game)
			game.spawn_timer = game.spawn_interval

			// Gradually decrease spawn interval as game progresses
			game.spawn_interval = max(0.5, 2.0 - game.game_time / 120.0)
		}

		// Check game over condition
		if game.lives <= 0 {
			game.state = .GAME_OVER
		}
	}
}

// Update tower state
update_tower :: proc(game: ^Game, delta_time: f32) {
	// Update cooldown timer
	if game.tower.cooldown_timer > 0 {
		game.tower.cooldown_timer -= delta_time
	}

	// Find target if none exists
	if game.tower.target == "" || !is_enemy_active(game, game.tower.target) {
		game.tower.target = find_closest_enemy(game)
	}

	// Attack target if available and cooldown is ready
	if game.tower.target != "" && game.tower.cooldown_timer <= 0 {

		distance := physics.distance(&game.physics, game.tower.id, game.tower.target)

		// Check if target is within range
		if distance <= game.tower.range {
			// Fire projectile
			projectile := create_projectile(
				game,
				game.tower.id,
				game.tower.target,
				game.tower.damage,
			)
			append(&game.projectiles, projectile)

			// Reset cooldown
			game.tower.cooldown_timer = game.tower.cooldown
		}
	}
}

// Update enemies state
update_enemies :: proc(game: ^Game, collisions: physics.Colliding, delta_time: f32) {
	for &enemy in game.enemies {
		if !enemy.active {
			continue
		}

		if enemy.id in collisions.enemies_to_projectiles {
			enemy.active = false
			continue
		}

		// Approach until within engage distance of the orbit ring, then orbit forever
		// Ring radius is random between touching-plus-gap and the tower's range
		orbit_min_m := game.tower.radius + enemy.radius + ORBIT_GAP_MIN
		orbit_max_m := max(orbit_min_m, game.tower.range)
		orbit_radius_m := orbit_min_m + enemy.orbit_mix * (orbit_max_m - orbit_min_m)
		if !enemy.orbiting {
			dist_m := physics.distance(&game.physics, enemy.id, game.tower.id)
			if dist_m <= orbit_radius_m + ORBIT_ENGAGE_RANGE {
				enemy.orbiting = true
			}
		}

		if enemy.orbiting {
			physics.orbit_body_around(
				&game.physics,
				enemy.id,
				game.tower.id,
				orbit_radius_m,
				enemy.orbit_speed_mps,
				enemy.orbit_direction,
			)
		} else {
			physics.move_body_towards(&game.physics, enemy.id, game.tower.id, enemy.thrust_n)
		}

		//// Check collision with tower
		//if physics.check_collision(&game.physics, game.enemies[i].id, game.tower.id) {
		//   // Enemy damages tower
		//   game.tower.health -= game.enemies[i].damage

		//   // Enemy is destroyed
		//   game.enemies[i].active = false
		//   physics.remove_body(&game.physics, game.enemies[i].id)

		//   // Reduce lives
		//   game.lives -= 1
		//}
	}

	// Remove inactive enemies
	i := 0
	for i < len(game.enemies) {
		if enemy := game.enemies[i]; !enemy.active {
			physics.remove_body(&game.physics, enemy.id)
			unordered_remove(&game.enemies, i)
		} else {
			i += 1
		}
	}
}

// Update projectiles state
update_projectiles :: proc(game: ^Game, collisions: physics.Colliding, delta_time: f32) {
	for &projectile, index in game.projectiles {

		if !projectile.active {
			continue
		}

		if projectile.id in collisions.projectiles_to_enemies {
			projectile.active = false
			continue
		}

		if projectile.id in collisions.projectiles_to_walls {
			projectile.active = false
			continue
		}

		target_index := find_enemy_by_id(game, projectile.target)
		if target_index < 0 {
			// Target no longer exists, deactivate projectile
			projectile.active = false
			continue
		}

		physics.move_body_towards(
			&game.physics,
			projectile.id,
			projectile.target,
			projectile.thrust_n,
		)
	}

	// Remove inactive projectiles
	i := 0
	for i < len(game.projectiles) {
		if projectile := game.projectiles[i]; !projectile.active {
			//// Remove projectile without preserving order
			//game.projectiles[i] = game.projectiles[len(game.projectiles) - 1]
			//pop(&game.projectiles)
			physics.remove_body(&game.physics, projectile.id)
			unordered_remove(&game.projectiles, i)
		} else {
			i += 1
		}
	}
}

// Spawn a new enemy
spawn_enemy :: proc(game: ^Game) {
	// Determine spawn position (random position along the edges, world meters)
	side := rand.int_max(4)
	x, y: f32

	switch side {
	case 0:
		// Top
		x = rand.float32_range(0, WORLD_WIDTH)
		y = SPAWN_MARGIN
	case 1:
		// Right
		x = WORLD_WIDTH - SPAWN_MARGIN
		y = rand.float32_range(0, WORLD_HEIGHT)
	case 2:
		// Bottom
		x = rand.float32_range(0, WORLD_WIDTH)
		y = WORLD_HEIGHT - SPAWN_MARGIN
	case 3:
		// Left
		x = SPAWN_MARGIN
		y = rand.float32_range(0, WORLD_HEIGHT)
	}

	// Pick a random enemy type from all available types
	enemy_type := EnemyType(rand.int_max(len(EnemyType)))

	// Create and add enemy
	enemy := create_enemy(game, x, y, enemy_type)
	append(&game.enemies, enemy)
}

// Find the closest enemy to the tower
find_closest_enemy :: proc(game: ^Game) -> string {
	if len(game.enemies) == 0 {
		return ""
	}

	tower_x, tower_y := physics.get_body_position(&game.physics, game.tower.id)
	closest_distance := f32(1000000)
	closest_id := ""

	for enemy in game.enemies {
		if !enemy.active {
			continue
		}

		enemy_x, enemy_y := physics.get_body_position(&game.physics, enemy.id)

		dx := enemy_x - tower_x
		dy := enemy_y - tower_y
		distance := math.sqrt(dx * dx + dy * dy)

		if distance < closest_distance {
			closest_distance = distance
			closest_id = enemy.id
		}
	}

	return closest_id
}

// Check if an enemy with the given ID is active
is_enemy_active :: proc(game: ^Game, id: string) -> bool {
	for enemy in game.enemies {
		if enemy.id == id && enemy.active {
			return true
		}
	}

	return false
}

// Find enemy index by ID
find_enemy_by_id :: proc(game: ^Game, id: string) -> int {
	for i := 0; i < len(game.enemies); i += 1 {
		if game.enemies[i].id == id {
			return i
		}
	}

	return -1
}

// Handle input

InputResult :: enum {
	CONTINUE,
	QUIT,
}

handle_input :: proc(game: ^Game) -> (result: InputResult = .CONTINUE) {
	if game.state == .MENU {
		if rl.IsKeyPressed(.ENTER) {
			game.state = .PLAYING

			// Initialize random seed
			rand.reset(u64(time.now()._nsec))
		}
	} else if game.state == .PLAYING {
		if rl.IsKeyPressed(.ESCAPE) {
			game.state = .GAME_OVER
		}
	} else if game.state == .GAME_OVER {
		if rl.IsKeyPressed(.ENTER) {
			// Clean up old game
			destroy_game(game)

			// Reinitialize game
			new_game := init_game()
			game^ = new_game
		} else if rl.IsKeyPressed(.ESCAPE) {
			result = .QUIT
		}
	}
	return
}
