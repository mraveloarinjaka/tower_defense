package renderer

import "../game"
import "core:c"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

FONT_SIZE :: 30

text_x_position :: proc(text: cstring, font_size: c.int) -> c.int {
	text_width := rl.MeasureText(text, font_size)
	return c.int((game.SCREEN_WIDTH / 2) - (text_width / 2))
}

text_y_position :: proc(relative_pos: f32, font_size: c.int) -> c.int {
	return c.int(game.SCREEN_HEIGHT * relative_pos) - (font_size / 2)
}

// Draw centered text with optional font size scaling
draw_centered_text :: proc(
	text: string,
	relative_y_position: f32,
	font_size: c.int,
	color: rl.Color,
) {
	to_write := strings.clone_to_cstring(text, context.temp_allocator)
	rl.DrawText(
		to_write,
		text_x_position(to_write, font_size),
		text_y_position(relative_y_position, font_size),
		font_size,
		color,
	)
}

// Draw the menu screen
draw_menu :: proc() {
	draw_centered_text("TOWER DEFENSE", .3, FONT_SIZE, rl.DARKGRAY)
	draw_centered_text("PRESS ENTER TO START", .5, FONT_SIZE * 0.8, rl.GRAY)
}

// Draw game over screen
draw_game_over :: proc(score: int) {
	draw_centered_text("GAME OVER", .3, FONT_SIZE, rl.DARKGRAY)
	score_text := fmt.tprintf("FINAL SCORE: %d", score)
	draw_centered_text(score_text, .5, FONT_SIZE * 0.8, rl.DARKGRAY)
	draw_centered_text("PRESS ENTER TO RESTART", .8, FONT_SIZE * 0.8, rl.GRAY)
}
