# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends AnimationPlayer

const BLOW_ANTICIPATION_TIME: float = 0.3

@onready var player: Player = owner
@onready var player_fighting: Node2D = %PlayerFighting
@onready var original_speed_scale: float = speed_scale
@onready var player_sprite: AnimatedSprite2D = %PlayerSprite


func _ready() -> void:
	player.mode_changed.connect(_on_player_mode_changed)


func _process(_delta: float) -> void:
	match player.mode:
		Player.Mode.COZY:
			_process_directional_walk()
		Player.Mode.FIGHTING:
			_process_fighting(_delta)

	# Opcional: dobla la velocidad si corre y está caminando
	var double_speed := player_sprite.animation.ends_with("_walk") and player.is_running()
	speed_scale = original_speed_scale * (2.0 if double_speed else 1.0)

func _process_directional_walk() -> void:
	var input_vector := player.input_vector
	if input_vector != Vector2.ZERO:
		
		#This define actual position of player
		if abs(input_vector.x) > abs(input_vector.y):
			if input_vector.x>0:
				player_sprite.animation="right_walk"
				player.last_direction=Vector2.RIGHT
			else:
				player_sprite.animation="left_walk"
				player.last_direction=Vector2.LEFT
		else:
			if input_vector.y>0:
				player_sprite.animation="front_walk"
				player.last_direction=Vector2.DOWN
			else:
				player_sprite.animation="back_walk"
				player.last_direction=Vector2.UP
		player_sprite.play()
	else:
		match player.last_direction:
			_:
				player_sprite.animation="idle"
		player_sprite.play()


func _process_fighting(_delta: float) -> void:
	if not player_fighting.is_fighting:
		_process_directional_walk()
		return
	player_sprite.animation = "attack_01"
	player_sprite.play()


func _on_player_mode_changed(mode: Player.Mode) -> void:
	match mode:
		Player.Mode.DEFEATED:
			player_sprite.animation = "defeated"
			player_sprite.play()
