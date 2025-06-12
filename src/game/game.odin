package game

import "../physics"
import "core:c"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

// Game constants
SCREEN_WIDTH :: 1024
SCREEN_HEIGHT :: 768
TITLE :: "Tower Defense Game"
TARGET_FPS :: 60

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

// Enemy structure
Enemy :: struct {
	id:         string,
	type:       EnemyType,
	health:     int,
	max_health: int,
	speed:      f32,
	damage:     int,
	active:     bool,
	value:      int, // Score value when defeated
}

// Tower structure
Tower :: struct {
	id:             string,
	type:           TowerType,
	health:         int,
	max_health:     int,
	damage:         int,
	range:          f32,
	cooldown:       f32,
	cooldown_timer: f32,
	center:         [2]f32,
	radius:         f32,
	target:         string, // ID of the current target enemy
}

// Projectile structure
Projectile :: struct {
	id:     string,
	damage: int,
	speed:  f32,
	target: string, // ID of the target enemy
	active: bool,
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

	// Create game boundaries
	physics.create_boundaries(&game.physics, SCREEN_WIDTH, SCREEN_HEIGHT)

	// Initialize tower
	game.tower = create_tower(&game, SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2)

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
	// Clean up dynamic arrays
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
	tower.health = 100
	tower.max_health = 100
	tower.damage = 10
	tower.range = 150
	tower.cooldown = 1.0
	tower.cooldown_timer = 0

	// Create physics body for tower
	physics.create_tower(&game.physics, tower.id, {x, y}, 20)

	//// Create range sensor
	//physics.create_sensor(&game.physics, "tower_range", x, y, tower.range)

	return tower
}

// Create an enemy
create_enemy :: proc(game: ^Game, x, y: f32, type: EnemyType) -> Enemy {
	enemy: Enemy
	enemy.type = type

	// Generate unique ID
	game.enemy_count += 1
	enemy.id = strings.clone(fmt.tprintf("enemy_%d", game.enemy_count))

	// Set properties based on type
	switch type {
	case .BASIC:
		enemy.health = 30
		enemy.max_health = 30
		enemy.speed = 50
		enemy.damage = 5
		enemy.value = 10

		physics.create_dynamic_body(&game.physics, enemy.id, {x, y}, 10)

	case .FAST:
		enemy.health = 15
		enemy.max_health = 15
		enemy.speed = 80
		enemy.damage = 3
		enemy.value = 15

		physics.create_dynamic_body(&game.physics, enemy.id, {x, y}, 8)

	case .TANK:
		enemy.health = 60
		enemy.max_health = 60
		enemy.speed = 30
		enemy.damage = 10
		enemy.value = 20

		physics.create_dynamic_body(&game.physics, enemy.id, {x, y}, 15)
	}

	enemy.active = true

	return enemy
}

destroy_enemy :: proc(enemy: ^Enemy) {
	delete(enemy.id)
}

// Create a projectile
create_projectile :: proc(game: ^Game, x, y: f32, target: string, damage: int) -> Projectile {
	projectile: Projectile

	// Generate unique ID
	game.projectile_count += 1
	projectile.id = fmt.tprintf("projectile_%d", game.projectile_count)

	projectile.damage = damage
	projectile.speed = 200
	projectile.target = target
	projectile.active = true

	// Create physics body
	physics.create_dynamic_body(&game.physics, projectile.id, {x, y}, 5)

	return projectile
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

		// Update enemies
		update_enemies(game, delta_time)

		// Update projectiles
		update_projectiles(game, delta_time)

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
		// Get tower position
		tower_x, tower_y := physics.get_body_position(game.physics, game.tower.id)

		// Get target position
		target_x, target_y := physics.get_body_position(game.physics, game.tower.target)

		// Calculate distance
		dx := target_x - tower_x
		dy := target_y - tower_y
		distance := math.sqrt(dx * dx + dy * dy)

		// Check if target is within range
		if distance <= game.tower.range {
			// Fire projectile
			projectile := create_projectile(
				game,
				tower_x,
				tower_y,
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
update_enemies :: proc(game: ^Game, delta_time: f32) {
	tower_x, tower_y := physics.get_body_position(game.physics, game.tower.id)

	for &enemy in game.enemies {
		//if !game.enemies[i].active {
		//   continue
		//}

		// Move towards tower
		physics.move_body_towards(&game.physics, enemy.id, tower_x, tower_y, enemy.speed)

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

	//// Remove inactive enemies
	//i := 0
	//for i < len(game.enemies) {
	//   if !game.enemies[i].active {
	//      // Remove enemy without preserving order
	//      game.enemies[i] = game.enemies[len(game.enemies) - 1]
	//      pop(&game.enemies)
	//   } else {
	//      i += 1
	//   }
	//}
}

// Update projectiles state
update_projectiles :: proc(game: ^Game, delta_time: f32) {
	for i := 0; i < len(game.projectiles); i += 1 {
		if !game.projectiles[i].active {
			continue
		}

		// Check if target still exists
		target_index := find_enemy_by_id(game, game.projectiles[i].target)
		if target_index < 0 {
			// Target no longer exists, deactivate projectile
			game.projectiles[i].active = false
			physics.remove_body(&game.physics, game.projectiles[i].id)
			continue
		}

		// Move towards target
		target_x, target_y := physics.get_body_position(game.physics, game.projectiles[i].target)
		physics.move_body_towards(
			&game.physics,
			game.projectiles[i].id,
			target_x,
			target_y,
			game.projectiles[i].speed,
		)

		// Check collision with target
		if physics.check_collision(
			&game.physics,
			game.projectiles[i].id,
			game.projectiles[i].target,
		) {
			// Damage enemy
			game.enemies[target_index].health -= game.projectiles[i].damage

			// Check if enemy is defeated
			if game.enemies[target_index].health <= 0 {
				// Add score
				game.score += game.enemies[target_index].value

				// Deactivate enemy
				game.enemies[target_index].active = false
				physics.remove_body(&game.physics, game.enemies[target_index].id)
			}

			// Deactivate projectile
			game.projectiles[i].active = false
			physics.remove_body(&game.physics, game.projectiles[i].id)
		}
	}

	// Remove inactive projectiles
	i := 0
	for i < len(game.projectiles) {
		if !game.projectiles[i].active {
			// Remove projectile without preserving order
			game.projectiles[i] = game.projectiles[len(game.projectiles) - 1]
			pop(&game.projectiles)
		} else {
			i += 1
		}
	}
}

// Spawn a new enemy
spawn_enemy :: proc(game: ^Game) {
	// Determine spawn position (random position along the edges)
	side := rand.int_max(4)
	x, y: f32

	switch side {
	case 0:
		// Top
		x = f32(rand.int_max(SCREEN_WIDTH))
		y = 20
	case 1:
		// Right
		x = SCREEN_WIDTH - 20
		y = f32(rand.int_max(SCREEN_HEIGHT))
	case 2:
		// Bottom
		x = f32(rand.int_max(SCREEN_WIDTH))
		y = SCREEN_HEIGHT - 20
	case 3:
		// Left
		x = 20
		y = f32(rand.int_max(SCREEN_HEIGHT))
	}

	// Determine enemy type based on wave and randomness
	enemy_type: EnemyType
	roll := rand.int_max(100)

	if game.wave >= 5 && roll < 20 {
		enemy_type = .TANK
	} else if game.wave >= 3 && roll < 40 {
		enemy_type = .FAST
	} else {
		enemy_type = .BASIC
	}

	// Create and add enemy
	enemy := create_enemy(game, x, y, enemy_type)
	append(&game.enemies, enemy)
}

// Find the closest enemy to the tower
find_closest_enemy :: proc(game: ^Game) -> string {
	if len(game.enemies) == 0 {
		return ""
	}

	tower_x, tower_y := physics.get_body_position(game.physics, game.tower.id)
	closest_distance := f32(1000000)
	closest_id := ""

	for enemy in game.enemies {
		if !enemy.active {
			continue
		}

		enemy_x, enemy_y := physics.get_body_position(game.physics, enemy.id)

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
handle_input :: proc(game: ^Game) {
	if game.state == .MENU {
		if rl.IsKeyPressed(.ENTER) {
			game.state = .PLAYING

			// Initialize random seed
			rand.reset(u64(time.now()._nsec))
		}
	} else if game.state == .PLAYING {
		// Toggle debug mode with F1
		//if rl.IsKeyPressed(.F1) {
		//   renderer.toggle_debug_mode(&game.renderer)
		//}
	} else if game.state == .GAME_OVER {
		if rl.IsKeyPressed(.ENTER) {
			// Clean up old game
			destroy_game(game)

			// Reinitialize game
			new_game := init_game()
			game^ = new_game
		}
	}
}
