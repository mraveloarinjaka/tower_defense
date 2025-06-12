package renderer

import "../game"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// Draw the menu screen
draw_menu :: proc() {
	rl.DrawText(
		"TOWER DEFENSE",
		game.SCREEN_WIDTH / 2 - 100,
		game.SCREEN_HEIGHT / 3,
		30,
		rl.DARKGRAY,
	)
	rl.DrawText(
		"PRESS ENTER TO START",
		game.SCREEN_WIDTH / 2 - 120,
		game.SCREEN_HEIGHT / 2,
		20,
		rl.GRAY,
	)
}

// Draw game over screen
draw_game_over :: proc(score: int) {
	rl.DrawText("GAME OVER", game.SCREEN_WIDTH / 2 - 80, game.SCREEN_HEIGHT / 3, 30, rl.DARKGRAY)
	score_text := fmt.tprintf("FINAL SCORE: %d", score)
	rl.DrawText(
		strings.clone_to_cstring(score_text),
		game.SCREEN_WIDTH / 2 - 100,
		game.SCREEN_HEIGHT / 2,
		20,
		rl.GRAY,
	)
	rl.DrawText(
		"PRESS ENTER TO RESTART",
		game.SCREEN_WIDTH / 2 - 140,
		game.SCREEN_HEIGHT / 2 + 40,
		20,
		rl.GRAY,
	)
}
