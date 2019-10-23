extends KinematicBody2D
class_name Player

export (int) var speed = 200
export (float) var rotation_speed = 1.5
export (String) var playerName: String
export (float) var max_stamina = 100.0
export (float) var stamina_depletion_rate = 100.0
export (float) var stamina_regen_rate = 25.0
export (float) var sprint_speed = 400.0

onready var camera := $Camera as Camera2D
onready var footStepAudio := $FootStepAudio as AudioStreamPlayer2D
onready var playerNameLabel := $PlayerNameLabel as Label
onready var staminaBar := $StaminaBar as ProgressBar
onready var playerCollisionShape := $Collision as CollisionShape2D

onready var playersNode = get_tree().get_root().get_node("base/players")

var velocity := Vector2()

var stamina: float

var frozen := false
var frozenColor := Color(0, 0, 1, 1)

# This is a car this player is driving
var car: Car

func _ready():
	set_process_input(true)
	
	stamina = max_stamina
	staminaBar.max_value = max_stamina
	playerNameLabel.text = playerName

puppet func setNetworkPosition(pos: Vector2):
	self.position = pos
	
puppet func setNetworkVelocity(vel: Vector2):
	self.velocity = vel
	
puppet func setNetworkRotation(rot: float):
	self.rotation = rot

puppet func setNetworkStamina(stam: float):
	self.stamina = stam
	
func unfreeze():
	self.frozen = false
	self.modulate = Color(1, 1, 1, 1)
	
func freeze():
	self.frozen = true
	self.velocity = Vector2(0, 0)
	self.modulate = frozenColor

func _input(event):
	if not is_network_master():
		return
	
	if(event.is_action_pressed("use")):
		if self.car == null:
			var new_car = find_car_inrange()
			if new_car != null:
				if new_car.get_in_car(self):
					call_deferred("on_car_enter", new_car)
					#on_car_enter(new_car)
				else:
					print('Car was full')
		else:
			call_deferred("on_car_exit")
			#on_car_exit()

func find_car_inrange() -> Car:
	var nearest_car: Car = null
	
	var cars = get_tree().get_nodes_in_group(Car.GROUP)
	for car in cars:
		car as Car
		var area = car.enterArea as Area2D
		if area.overlaps_body(self):
			nearest_car = car
			break
	return nearest_car

# warning-ignore:unused_argument
func _process(delta: float):
	staminaBar.value = stamina

# Returns the ammount to rotate by
func get_input(delta: float) -> float:
	var new_rotation := 0.0
	
	if not is_network_master():
		return new_rotation
	
	if self.frozen:
		return new_rotation
	
	var curSpeed: float
	if is_sprinting():
		curSpeed = sprint_speed
	else:
		curSpeed = speed
	
	var rotation_dir: float
	self.velocity = Vector2()
	if Input.is_action_pressed('ui_right'):
		rotation_dir = 1.0
	if Input.is_action_pressed('ui_left'):
		rotation_dir = -1.0
	if Input.is_action_pressed('ui_down'):
		self.velocity = Vector2(-curSpeed, 0).rotated(self.rotation)
	if Input.is_action_pressed('ui_up'):
		self.velocity = Vector2(curSpeed, 0).rotated(self.rotation)
	
	new_rotation = rotation_dir * self.rotation_speed * delta
	return new_rotation

func is_sprinting():
	return Input.is_action_pressed('sprint') and stamina > 0.0

func process_stamina(delta: float):
	if is_sprinting():
		stamina -= (stamina_depletion_rate * delta)
	elif not Input.is_action_pressed('sprint') and not is_moving():
		stamina += (stamina_regen_rate * delta)
	stamina = clamp(stamina, 0.0, max_stamina)

func _physics_process(delta: float):
	# If we're in a car, do nothing
	if is_network_master() && self.car == null:
		var new_rotation = get_input(delta)
		process_stamina(delta)
		self.velocity = move_and_slide(self.velocity)
		rotate(new_rotation)
	
		rpc_unreliable("setNetworkPosition", self.position)
		rpc_unreliable("setNetworkVelocity", self.velocity)
		rpc_unreliable("setNetworkRotation", self.rotation)
		rpc_unreliable("setNetworkStamina", self.stamina)
	
	# Make movement noises if moving
	if is_moving() && car == null:
		if not footStepAudio.playing:
			footStepAudio.playing = true
	else:
		if footStepAudio.playing:
			footStepAudio.playing = false

func is_moving() -> bool:
	return velocity.length() > 0.0

func set_current_player():
	camera.current = true

func on_car_enter(newCar):
	print('Enter Car')
	self.car = newCar
	# Refil stamina instantly
	self.stamina = max_stamina
	
	playerCollisionShape.disabled = true
	
	self.get_parent().remove_child(self) # error here  
	self.car.add_child(self)
	
	self.position = Vector2.ZERO
	self.rotation = 0

func on_car_exit():
	print('Exit Car')
	
	self.get_parent().remove_child(self) # error here
	playersNode.add_child(self)
	
	self.global_position = car.global_position
	self.rotation = car.rotation
	
	playerCollisionShape.disabled = false
	
	var oldCar = self.car
	self.car = null
	
	oldCar.get_out_of_car(self)
