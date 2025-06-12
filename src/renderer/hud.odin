package renderer

import "../game"
import "core:c"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// Draw the UI
draw_hud :: proc(renderer: ^Renderer) {
	// Draw score
	score_text := fmt.tprintf("Score: %d", renderer.world.score)
	rl.DrawText(strings.clone_to_cstring(score_text), 10, 10, 20, rl.DARKGRAY)

	// Draw wave
	wave_text := fmt.tprintf("Wave: %d", renderer.world.wave)
	rl.DrawText(strings.clone_to_cstring(wave_text), 10, 40, 20, rl.DARKGRAY)

	// Draw lives
	lives_text := fmt.tprintf("Lives: %d", renderer.world.lives)
	rl.DrawText(strings.clone_to_cstring(lives_text), 10, 70, 20, rl.DARKGRAY)

	// Draw tower health
	health_text := fmt.tprintf(
		"Tower Health: %d/%d",
		renderer.world.tower.health,
		renderer.world.tower.max_health,
	)
	rl.DrawText(
		strings.clone_to_cstring(health_text),
		game.SCREEN_WIDTH - 200,
		10,
		20,
		rl.DARKGRAY,
	)

	// Draw health bar
	bar_width := 180
	bar_height := 10
	bar_x := game.SCREEN_WIDTH - 200
	bar_y := 40

	// Background (empty) health bar
	rl.DrawRectangle(c.int(bar_x), c.int(bar_y), c.int(bar_width), c.int(bar_height), rl.GRAY)

	// Filled health bar
	health_percent := f32(renderer.world.tower.health) / f32(renderer.world.tower.max_health)
	filled_width := i32(f32(bar_width) * health_percent)

	// Color based on health percentage
	health_color: rl.Color
	if health_percent > 0.6 {
		health_color = rl.GREEN
	} else if health_percent > 0.3 {
		health_color = rl.YELLOW
	} else {
		health_color = rl.RED
	}

	rl.DrawRectangle(c.int(bar_x), c.int(bar_y), filled_width, c.int(bar_height), health_color)

	// Draw debug info if enabled
	draw_debug_info(renderer, 100)
}

// Draw debug information
draw_debug_info :: proc(renderer: ^Renderer, last_text_line: i32) {
	if !renderer.debug_mode || renderer.world == nil {
		return
	}

	// Draw physics world information
	debug_text := fmt.tprintf("Bodies: %d", len(renderer.world.physics.bodies))
	rl.DrawText(strings.clone_to_cstring(debug_text), 10, last_text_line, 20, rl.DARKGRAY)

	// Draw FPS
	rl.DrawFPS(10, last_text_line + 30)
}

