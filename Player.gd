extends CharacterBody3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export var animation_player: AnimationPlayer

@export_group("Camera")
@export var look_sensitivity: float = 0.005
@export var max_up_angle: float = 90.0
@export var max_down_angle: float = -90.0
@onready var neck := $Neck
@onready var camera := $Neck/Camera

@export_group("Inputs")
@export var forward_importance = 1.0
@export var side_importance = 1.0
@export var auto_jump: bool = false

@export_group("Movement")
@export var jump_velocity: float = 270 / 50
@export var ground_acceleration: float = 250.0
@export var air_acceleration: float = 85.0
@export var friction: float = 6.0
@export var stop_speed: float = 10.0
@export var snap_tp_stationary_speed: float = 1.0
@export var max_ground_speed: float = 10.0
@export var max_air_speed: float = 1.5

@export_group("Quirky Movement")
@export var bhop_frame_window: int = 2

@export_group("Crouching")
@export_range(0, 2) var crouch_seconds: float = 0.2


var timedelta: float
var grounded_timer: int

var wish_jump: bool = false
var third_person: bool = false
var crouching: bool = false


func crouch(crouch_state: bool) -> void:
    if crouching == crouch_state:
        return
    crouching = crouch_state
    var crouch_speed = 1 / crouch_seconds
    # FIXME: midair crouch should drag feet up, not head down
    if crouch_state:
        animation_player.play(&"crouch", -1, crouch_speed)
    else:
        animation_player.play(&"crouch", -1, -crouch_speed, true)
    
func toggle_crouch() -> void:
    crouch(!crouching)



func get_input_dir():
    # Something is wrong with my math... it should be forward - backward?
    var forwards = Input.get_action_strength(&"move_backward") - Input.get_action_strength(&"move_forward")
    var right = Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left")
    
    return (transform.basis * Vector3(
        right * side_importance, 
        0, 
        forwards * forward_importance,
    )).normalized()
    
    
func accelerate(wish_dir: Vector3, max_speed: float, accel: float) -> void:
    var projected_speed = velocity.dot(wish_dir)
    
    var add_speed = max_speed - projected_speed
    if add_speed <= 0:
        return
    
    const surface_friction = 1
    var accel_speed = timedelta * accel * max_speed * surface_friction;
    
    if accel_speed > add_speed:
        accel_speed = add_speed
    velocity += wish_dir * accel_speed


func apply_friction() -> void:
    # https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/gamemovement.cpp#L1612-L1679
    # https://github.com/id-Software/Quake-III-Arena/blob/dbe4ddb10315479fc00086f08e25d968b4b43c49/code/game/bg_pmove.c#L172-L230
    var speed = velocity.length()
    if speed == 0:
        return
    if speed < snap_tp_stationary_speed:
        velocity.x = 0
        velocity.z = 0
        return
    
    var drop: float = 0.0
    if is_on_floor():
        var control: float = stop_speed if stop_speed < speed else speed
        drop += control * friction * timedelta
        
    velocity *= maxf(0, speed - drop) / speed


func tick_movement() -> void:
    var on_ground = is_on_floor()
    var old_velocity = velocity
    
    if on_ground and grounded_timer > bhop_frame_window:
        apply_friction()
        
    var max_speed = max_ground_speed if on_ground else max_air_speed
    var acceleration = ground_acceleration if on_ground else air_acceleration
    
    var input_dir = get_input_dir()
    accelerate(input_dir, max_speed, acceleration)
    velocity.y -= gravity * timedelta
    
    var wish_jump: bool = false
    if auto_jump:
        wish_jump = Input.is_action_pressed(&"jump")
    else:
        wish_jump = Input.is_action_just_pressed(&"jump")
    if wish_jump and on_ground:
        velocity.y = jump_velocity


func _physics_process(delta):
    timedelta = delta
    
    if Input.is_action_just_pressed(&"third_person"):
        third_person = not third_person
    camera.position.z = 5 if third_person else 0
    
    if Input.is_action_just_pressed(&"crouch"):
        toggle_crouch()
    
    if is_on_floor():
        if grounded_timer < 0:
            grounded_timer = 0
        grounded_timer += 1
    else:
        if grounded_timer > 0:
            grounded_timer = 0
        grounded_timer = -1
    
    tick_movement()
    move_and_slide()
    
    #while debug_meshes:
        #debug_meshes.pop_back().queue_free()
    #debug_meshes.append(Draw3d.line(position, position+Vector3(velocity.x, 0, velocity.z), Color.PALE_VIOLET_RED))
    #move_and_slide()
    #debug_meshes.append(Draw3d.line(position, position+Vector3(velocity.x, 0, velocity.z), Color.PURPLE))
    
var debug_meshes: Array[MeshInstance3D]
    
    
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    elif event.is_action_pressed("ui_cancel"):
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * look_sensitivity)
        neck.rotate_x(-event.relative.y * look_sensitivity)
        neck.rotation.x = clamp(neck.rotation.x, deg_to_rad(max_down_angle), deg_to_rad(max_up_angle))
