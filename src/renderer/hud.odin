package renderer

import "../game"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// Vertical spacing between debug text lines
LINE_SPACING :: 30

// Draw a single line of HUD text at the given screen position
draw_text_line :: proc(text: string, x, y: i32, color: rl.Color = rl.DARKGRAY) {
	c_text := strings.clone_to_cstring(text, context.temp_allocator)
	rl.DrawText(c_text, x, y, 20, color)
}

// Draw a health bar: gray background plus a color-coded fill
draw_health_bar :: proc(x, y, width, height: i32, health, max_health: int) {
	// Background (empty) health bar
	rl.DrawRectangle(x, y, width, height, rl.GRAY)

	// Guard against division by zero when there is no maximum health
	health_percent: f32 = 0
	if max_health > 0 {
		health_percent = f32(health) / f32(max_health)
	}

	// Color based on health percentage
	health_color: rl.Color
	if health_percent > 0.6 {
		health_color = rl.GREEN
	} else if health_percent > 0.3 {
		health_color = rl.YELLOW
	} else {
		health_color = rl.RED
	}

	// Filled health bar
	filled_width := i32(f32(width) * health_percent)
	rl.DrawRectangle(x, y, filled_width, height, health_color)
}

// Draw the UI
draw_hud :: proc(renderer: ^Renderer) {
	// Draw score
	score_text := fmt.tprintf("Score: %d", renderer.world.score)
	draw_text_line(score_text, 10, 10)

	// Draw wave
	wave_text := fmt.tprintf("Wave: %d", renderer.world.wave)
	draw_text_line(wave_text, 10, 40)

	// Draw lives
	lives_text := fmt.tprintf("Lives: %d", renderer.world.lives)
	draw_text_line(lives_text, 10, 70)

	// Draw tower health
	health_text := fmt.tprintf(
		"Tower Health: %d/%d",
		renderer.world.tower.health,
		renderer.world.tower.max_health,
	)
	draw_text_line(health_text, game.SCREEN_WIDTH - 200, 10)

	// Draw health bar
	draw_health_bar(
		game.SCREEN_WIDTH - 200,
		40,
		180,
		10,
		renderer.world.tower.health,
		renderer.world.tower.max_health,
	)

	// Draw debug info if enabled
	draw_debug_info(renderer, 100)
}

// Draw debug information
draw_debug_info :: proc(renderer: ^Renderer, last_text_line: i32) {
	if !renderer.debug_mode || renderer.world == nil {
		return
	}

	// Draw entity counts
	entities := [2]struct {
		label: string,
		value: int,
	}{
		{"Enemies", len(renderer.world.enemies)},
		{"Projectiles", len(renderer.world.projectiles)},
	}

	for entity, index in entities {
		text := fmt.tprintf("%s: %d", entity.label, entity.value)
		y := last_text_line + i32(index) * LINE_SPACING
		draw_text_line(text, 10, y)
	}

	// Draw the current camera zoom
	zoom_text := fmt.tprintf("Zoom: %.2fx (scroll / R reset)", renderer.camera.zoom)
	zoom_line := last_text_line + i32(len(entities)) * LINE_SPACING
	draw_text_line(zoom_text, 10, zoom_line)

	// Draw the current tower tuning values
	tower := renderer.world.tower
	shots_per_second := f32(0)
	if tower.cooldown > 0 {
		shots_per_second = 1.0 / tower.cooldown
	}

	tuning := [4]string {
		fmt.tprintf("Damage: %d", tower.damage),
		fmt.tprintf("Range: %.1f m", tower.range),
		fmt.tprintf("Cooldown: %.2f s (%.1f shots/s)", tower.cooldown, shots_per_second),
		"F2: tower tuning",
	}

	next_line := zoom_line + LINE_SPACING
	for text, index in tuning {
		draw_text_line(text, 10, next_line + i32(index) * LINE_SPACING)
	}

	// Draw FPS
	rl.DrawFPS(10, next_line + i32(len(tuning)) * LINE_SPACING)
}
