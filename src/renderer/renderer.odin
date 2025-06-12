package renderer

import "../game"
import "../physics"
import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import b2 "vendor:box2d"
import rl "vendor:raylib"

// Debug drawing colors
DEBUG_COLOR_STATIC :: rl.BLUE
DEBUG_COLOR_DYNAMIC :: rl.RED
DEBUG_COLOR_SENSOR :: rl.GREEN
DEBUG_COLOR_JOINT :: rl.PURPLE
DEBUG_COLOR_AABB :: rl.SKYBLUE
DEBUG_COLOR_SHAPE :: rl.DARKBLUE

PHYSICS_SCALE :: physics.PHYSICS_SCALE

// Renderer context
Renderer :: struct {
	world:      ^game.Game,
	debug_mode: bool,
	camera:     rl.Camera2D,
}

// Initialize renderer
init_renderer :: proc(world: ^game.Game) -> Renderer {
	renderer: Renderer
	renderer.world = world
	renderer.debug_mode = true

	renderer.camera = rl.Camera2D{}
	renderer.camera.zoom = 1.0

	return renderer
}

// Begin rendering frame
begin_render :: proc(renderer: ^Renderer, clear_color: rl.Color) {
	rl.BeginDrawing()
	rl.ClearBackground(clear_color)

	// Begin 2D camera mode if needed
	if renderer.camera.zoom != 1.0 {
		rl.BeginMode2D(renderer.camera)
	}
}

// End rendering frame
end_render :: proc(renderer: ^Renderer) {
	// End 2D camera mode if needed
	if renderer.camera.zoom != 1.0 {
		rl.EndMode2D()
	}

	rl.EndDrawing()
}

// Draw the game
draw_game :: proc(renderer: ^Renderer) {
	begin_render(renderer, rl.RAYWHITE)
	defer end_render(renderer)

	if renderer.world.state == .MENU {
		draw_menu()
	} else if renderer.world.state == .PLAYING {
		draw_boundaries(renderer)
		draw_tower(renderer, renderer.world.tower.id, {}, renderer.world.tower.range)
		for enemy in renderer.world.enemies {
			if enemy.active {
				draw_enemy(renderer, enemy.id, {}, enemy.health, enemy.max_health)
			}
		}

		//// Draw projectiles
		//for projectile in game.projectiles {
		//   if projectile.active {
		//      renderer.draw_projectile(&renderer, projectile.id)
		//   }
		//}

		draw_hud(renderer)
	} else if renderer.world.state == .GAME_OVER {
		draw_game_over(renderer.world.score)
	}
}

// Draw a tower
draw_tower :: proc(
	renderer: ^Renderer,
	body_name: string,
	texture: rl.Texture2D = {},
	range: f32 = 0,
) {
	if renderer.world == nil {
		return
	}

	// Draw the tower body
	draw_body(renderer, body_name, rl.BLUE, texture)

	// Draw range indicator if specified
	if range > 0 {
		x, y := physics.get_body_position(renderer.world.physics, body_name)

		// Draw range circle with transparency
		range_color := rl.SKYBLUE
		range_color.a = 100
		rl.DrawCircleLines(cast(i32)x, cast(i32)y, range, range_color)
	}
}

// Draw an enemy
draw_enemy :: proc(
	renderer: ^Renderer,
	body_name: string,
	texture: rl.Texture2D = {},
	health: int = 0,
	max_health: int = 0,
) {
	if renderer.world == nil {
		return
	}

	// Draw the enemy body
	draw_body(renderer, body_name, rl.RED, texture)

	// Draw health bar if health is provided
	//if max_health > 0 {
	//   x, y := physics.get_body_position(renderer.world.physics, body_name)

	//   // Get body radius (assuming circular shape)
	//   body, exists := renderer.world.physics.bodies[body_name]
	//   if !exists {
	//      return
	//   }

	//   fixture := b2.get_fixture_list(body)
	//   if fixture == nil {
	//      return
	//   }

	//   shape := b2.get_shape(fixture)
	//   shape_type := b2.get_type(shape)

	//   radius: f32 = 10 // Default radius
	//   if shape_type == .CIRCLE {
	//      circle_shape := b2.get_circle(shape)
	//      radius = circle_shape.radius * physics.PHYSICS_SCALE
	//   }

	//   // Draw health bar above enemy
	//   bar_width := radius * 2
	//   bar_height := 5.0
	//   bar_x := x - radius
	//   bar_y := y - radius - 10

	//   // Background (empty) health bar
	//   rl.draw_rectangle(
	//      cast(i32)bar_x,
	//      cast(i32)bar_y,
	//      cast(i32)bar_width,
	//      cast(i32)bar_height,
	//      rl.GRAY,
	//   )

	//   // Filled health bar
	//   health_percent := f32(health) / f32(max_health)
	//   filled_width := bar_width * health_percent

	//   // Color based on health percentage
	//   health_color: rl.Color
	//   if health_percent > 0.6 {
	//      health_color = rl.GREEN
	//   } else if health_percent > 0.3 {
	//      health_color = rl.YELLOW
	//   } else {
	//      health_color = rl.RED
	//   }

	//   rl.draw_rectangle(
	//      cast(i32)bar_x,
	//      cast(i32)bar_y,
	//      cast(i32)filled_width,
	//      cast(i32)bar_height,
	//      health_color,
	//   )
	//}
}

// Draw a projectile
draw_projectile :: proc(renderer: ^Renderer, body_name: string, texture: rl.Texture2D = {}) {
	if renderer.world == nil {
		return
	}

	// Draw the projectile body
	draw_body(renderer, body_name, rl.YELLOW, texture)
}

// Draw game boundaries
draw_boundaries :: proc(renderer: ^Renderer) {
	draw_body(renderer, physics.WALLS[.TOP], rl.DARKGRAY)
	draw_body(renderer, physics.WALLS[.BOTTOM], rl.DARKGRAY)
	draw_body(renderer, physics.WALLS[.LEFT], rl.DARKGRAY)
	draw_body(renderer, physics.WALLS[.RIGHT], rl.DARKGRAY)
}

// Draw a path (for enemy movement)
draw_path :: proc(renderer: ^Renderer, points: []rl.Vector2, color: rl.Color) {
	if len(points) < 2 {
		return
	}

	// Draw lines connecting the points
	for i := 0; i < len(points) - 1; i += 1 {
		rl.DrawLineV(points[i], points[i + 1], color)
	}

	// Draw points
	for point in points {
		rl.DrawCircleV(point, 3, color)
	}
}

// Draw explosion effect
draw_explosion :: proc(renderer: ^Renderer, position: rl.Vector2, radius: f32, color: rl.Color) {
	// Draw outer circle
	outer_color := color
	outer_color.a = 100
	rl.DrawCircleV(position, radius, outer_color)

	// Draw inner circle
	inner_color := color
	inner_color.a = 200
	rl.DrawCircleV(position, radius * 0.7, inner_color)

	// Draw center
	rl.DrawCircleV(position, radius * 0.3, rl.WHITE)
}

// Set camera position
set_camera_position :: proc(renderer: ^Renderer, x, y: f32) {
	renderer.camera.target = rl.Vector2{x, y}
}

// Set camera zoom
set_camera_zoom :: proc(renderer: ^Renderer, zoom: f32) {
	renderer.camera.zoom = zoom
}

// Toggle debug mode
toggle_debug_mode :: proc(renderer: ^Renderer) {
	renderer.debug_mode = !renderer.debug_mode
}
