extends CharacterBody3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export_group("Camera")
@export var look_sensitivity: float = 0.005
@export var max_up_angle: float = 90.0
@export var max_down_angle: float = -90.0
@onready var neck := $Neck
@onready var camera := $Neck/Camera

@export_group("Inputs")
@export var forward_importance = 1.0
@export var side_importance = 1.0
@export var autojump: bool = false

@export_group("Movement")
@export var jump_velocity: float = 270 / 50
@export var normal_acceleration: float = 20.0
@export var air_accelerate: float = 1.0
@export var friction: float = 20.0
@export var stop_speed: float = 10.0



var timedelta

var wish_jump: bool = false

# FIXME: fix acceleration not being applied correctly (maybe)
# FIXME: Fix movement being super slow, and just generally make the code more accurate by scaling by ,ove forward and right variables, als ofigure out what their defaults are


func get_input_dir():
    # Something is wrong with my math... it should be forward - backward?
    var forwards = Input.get_action_strength(&"move_backward") - Input.get_action_strength(&"move_forward")
    var right = Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left")
    
    return (transform.basis * Vector3(
        right * side_importance, 
        0, 
        forwards * forward_importance,
    )).normalized()
    

func apply_friction() -> void:
    # https://github.com/id-Software/Quake-III-Arena/blob/dbe4ddb10315479fc00086f08e25d968b4b43c49/code/game/bg_pmove.c#L172-L230
    # https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/gamemovement.cpp#L1612-L1679
    if is_on_floor():
        velocity.y = 0
        
    var speed = velocity.length()	
    if speed < 1:
        velocity.x = 0
        velocity.z = 0
        return
    
    # FIXME: Rename this
    var drop = 0
    if is_on_floor():
        var control: float = stop_speed if stop_speed < speed else speed
        drop += control * friction * timedelta
    var new_speed = maxf(0, speed - drop)
    new_speed /= speed
    velocity *= new_speed


func accelerate(wish_dir: Vector3, wish_speed: float, accel: float):
    # https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/sp/src/game/shared/gamemovement.cpp#L1822-L1854
    # This gives cause for a lot of movement tech
    var current_speed = velocity.dot(wish_dir)
    
    var add_speed = wish_speed - current_speed
    if add_speed <= 0:
        return
    
    const surface_friction = 1
    var accel_speed = timedelta * accel * wish_speed * surface_friction;
    
    if accel_speed > add_speed:
        accel_speed = add_speed
        
    velocity += wish_dir * accel_speed


func air_move() -> void:
    # https://github.com/id-Software/Quake-III-Arena/blob/dbe4ddb10315479fc00086f08e25d968b4b43c49/code/game/bg_pmove.c#L601-L658
    apply_friction()
    #print("Jump")
    
    
    var move_dir: Vector3 = get_input_dir()
    
    accelerate(move_dir, 10, air_accelerate)
    
    # Is this where surfing takes place?
    # https://github.com/id-Software/Quake-III-Arena/blob/dbe4ddb10315479fc00086f08e25d968b4b43c49/code/game/bg_pmove.c#L639-L645
    
    
func walk_move() -> void:
    # https://github.com/id-Software/Quake-III-Arena/blob/dbe4ddb10315479fc00086f08e25d968b4b43c49/code/game/bg_pmove.c#L692-L809
    if wish_jump and is_on_floor():
        wish_jump = false
        air_move()
        velocity.y = jump_velocity
        return
    
    apply_friction()
    
    # FIXME: Scale by moveright and moveforward
    #var forward = Input.get_action_strength(&"move_forward") - Input.get_action_strength(&"move_backward")
    #var right = Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left")
    
    var move_dir: Vector3 = get_input_dir()
    
    # FIXME: Crouch speed adjust?
    # https://github.com/id-Software/Quake-III-Arena/blob/dbe4ddb10315479fc00086f08e25d968b4b43c49/code/game/bg_pmove.c#L752-L757
    
    # FIXME: More sliding shenanigans
    # https://github.com/id-Software/Quake-III-Arena/blob/dbe4ddb10315479fc00086f08e25d968b4b43c49/code/game/bg_pmove.c#L770-L776
    # Look out for anything mentioning SURF_SLICK?
    
    accelerate(move_dir, 6, normal_acceleration)
    


func _physics_process(delta):
    timedelta = delta
    
    # FIXME: Allows for a bit kinder jumping, I might remove this later.
    if autojump:
        wish_jump = Input.is_action_pressed(&"jump")
    elif Input.is_action_just_pressed(&"jump"):
        wish_jump = true
    elif Input.is_action_just_released(&"jump"):
        wish_jump = false
    
    # https://github.com/id-Software/Quake-III-Arena/blob/dbe4ddb10315479fc00086f08e25d968b4b43c49/code/game/bg_pmove.c#L1988-L1994
    #if is_on_floor():
    if is_on_floor():
        walk_move()
    else:
        air_move()
    
    if not is_on_floor():
        velocity.y -= gravity * delta
        
    # I prob need to implemenet the contents of PM_StepSlideMove
    move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    elif event.is_action_pressed("ui_cancel"):
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * look_sensitivity)
        camera.rotate_x(-event.relative.y * look_sensitivity)
        camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(max_down_angle), deg_to_rad(max_up_angle))
