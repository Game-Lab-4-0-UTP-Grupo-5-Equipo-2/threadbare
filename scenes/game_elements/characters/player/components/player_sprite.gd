# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends AnimatedSprite2D

@onready var player: Player = owner


func _process(_delta: float) -> void:
	if not player:
		return
	if player.velocity.is_zero_approx():
		return


func look_at_side(side: Enums.LookAtSide) -> void:
	if side == 0:
		return
	flip_h = side < 0
