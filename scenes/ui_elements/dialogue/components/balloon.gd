# SPDX-FileCopyrightText: 2022-present Nathan Hoad and Dialogue Manager contributors
# SPDX-License-Identifier: MIT
extends CanvasLayer
## A basic dialogue balloon for use with Dialogue Manager.

const PLAYER_RIBBON_TYPE_VARIATION := &"PlayerRibbon"
const NPC_RIBBON_TYPE_VARIATION := &"NPCRibbon"

## The action to use for advancing the dialogue
@export var next_action: StringName = &"ui_accept"

## The action to use to skip typing the dialogue
@export var skip_action: StringName = &"ui_cancel"

## The dialogue resource
var resource: DialogueResource

## Temporary game states
var temporary_game_states: Array = []:
	set(new_value):
		temporary_game_states = new_value
		for state: Variant in new_value:
			if state is Player:
				_player_name = (state as Player).player_name

## See if we are waiting for the player
var is_waiting_for_input: bool = false

## See if we are running a long mutation and should hide the balloon
var will_hide_balloon: bool = false

## A dictionary to store any ephemeral variables
var locals: Dictionary = {}

## The current line
var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			apply_dialogue_line()
		else:
			# The dialogue has finished so close the balloon
			queue_free()
	get:
		return dialogue_line

## A cooldown timer for delaying the balloon hide when encountering a mutation.
var mutation_cooldown: Timer = Timer.new()

var _locale: String = TranslationServer.get_locale()
var _player_name: String = ""

## The base balloon anchor
@onready var balloon: Control = %Balloon

## The panel holding the label showing the name of the currently-speaking character
@onready var character_panel: PanelContainer = %CharacterPanel

## The label showing the name of the currently speaking character
@onready var character_label: Label = %CharacterLabel

## The label showing the currently spoken dialogue
@onready var dialogue_label: DialogueLabel = %DialogueLabel

## The “Next” button container, visible when the current line is complete and there are
## no response choices.
@onready var next_button_container: MarginContainer = %NextButtonContainer

## The “Next” button, to connect signals.
@onready var next_button: Button = %NextButton

## The menu of responses
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu

#@onready var response_example: Button = $Balloon/PanelContainer/VBoxContainer/ResponsesMenu/ResponseExample

@onready var talk_sound_player: AudioStreamPlayer = $TalkSoundPlayer

func _ready() -> void: 
	#%DialogueLabel.add_theme_color_override("font_color", Color.WHITE)
	#$Balloon/PanelContainer/VBoxContainer/ResponsesMenu/ResponseExample.add_theme_color_override("font_color", Color.CYAN)
	balloon.hide()
	Engine.get_singleton("DialogueManager").mutated.connect(_on_mutated)

	# If the responses menu doesn't have a next action set, use this one
	if responses_menu.next_action.is_empty():
		responses_menu.next_action = next_action

	mutation_cooldown.timeout.connect(_on_mutation_cooldown_timeout)
	next_button.pressed.connect(func() -> void: next(dialogue_line.next_id))
	add_child(mutation_cooldown)


func _unhandled_input(_event: InputEvent) -> void:
	# Only the balloon is allowed to handle input while it's showing
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	## Detect a change of locale and update the current dialogue line to show the new language
	if (
		what == NOTIFICATION_TRANSLATION_CHANGED
		and _locale != TranslationServer.get_locale()
		and is_instance_valid(dialogue_label)
	):
		_locale = TranslationServer.get_locale()
		var visible_ratio := dialogue_label.visible_ratio
		self.dialogue_line = await resource.get_next_dialogue_line(dialogue_line.id)
		if visible_ratio < 1:
			dialogue_label.skip_typing()


## Start some dialogue
func start(
	dialogue_resource: DialogueResource, title: String, extra_game_states: Array = []
) -> void:
	temporary_game_states = [self] + extra_game_states
	is_waiting_for_input = false
	resource = dialogue_resource
	self.dialogue_line = await resource.get_next_dialogue_line(title, temporary_game_states)
	talk_sound_player.play()


## Apply any changes to the balloon given a new [DialogueLine].
func apply_dialogue_line() -> void:
	mutation_cooldown.stop()

	is_waiting_for_input = false
	balloon.focus_mode = Control.FOCUS_ALL
	balloon.grab_focus()

	character_panel.visible = not dialogue_line.character.is_empty()
	character_panel.theme_type_variation = (
		PLAYER_RIBBON_TYPE_VARIATION
		if _player_name == dialogue_line.character
		else NPC_RIBBON_TYPE_VARIATION
	)
	character_label.text = tr(dialogue_line.character, "dialogue")

	dialogue_label.hide()
	dialogue_label.dialogue_line = dialogue_line

	responses_menu.hide()
	responses_menu.responses = dialogue_line.responses

	next_button_container.hide()

	# Show our balloon
	balloon.show()
	will_hide_balloon = false

	dialogue_label.show()
	if not dialogue_line.text.is_empty():
		dialogue_label.type_out()
		talk_sound_player.stream_paused = false
		await dialogue_label.finished_typing
		talk_sound_player.stream_paused = true

	# Wait for input
	if dialogue_line.responses.size() > 0:
		balloon.focus_mode = Control.FOCUS_NONE
		responses_menu.show()
	elif dialogue_line.time != "":
		var time := (
			dialogue_line.text.length() * 0.02
			if dialogue_line.time == "auto"
			else dialogue_line.time.to_float()
		)
		await get_tree().create_timer(time).timeout
		next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()
		next_button_container.show()


## Go to the next line
func next(next_id: String) -> void:
	self.dialogue_line = await resource.get_next_dialogue_line(next_id, temporary_game_states)


#region Signals


func _on_mutation_cooldown_timeout() -> void:
	if will_hide_balloon:
		will_hide_balloon = false
		balloon.hide()


func _on_mutated(_mutation: Dictionary) -> void:
	is_waiting_for_input = false
	will_hide_balloon = true
	mutation_cooldown.start(0.1)


func _on_balloon_gui_input(event: InputEvent) -> void:
	# See if we need to skip typing of the dialogue
	if dialogue_label.is_typing:
		var mouse_was_clicked: bool = (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.is_pressed()
		)
		var skip_button_was_pressed: bool = event.is_action_pressed(skip_action)
		if mouse_was_clicked or skip_button_was_pressed:
			get_viewport().set_input_as_handled()
			dialogue_label.skip_typing()
			return

	if not is_waiting_for_input:
		return
	if dialogue_line.responses.size() > 0:
		return

	# When there are no response options the balloon itself is the clickable thing
	get_viewport().set_input_as_handled()

	if (
		event is InputEventMouseButton
		and event.is_pressed()
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		next(dialogue_line.next_id)
	elif event.is_action_pressed(next_action) and get_viewport().gui_get_focus_owner() == balloon:
		next(dialogue_line.next_id)


func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	next(response.next_id)

#endregion
