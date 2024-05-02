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
# We may want the player to fall slightly faster than other objects
@export var gravity_mult: float = 1.0

@export_group("Quirky Movement")
@export var bhop_tick_window: int = 2
@export var coyote_ticks: int = 0.1 * 60

@export_group("Dash")
@export var dash_count: int = 1
@export var dash_speed: float = 20
@export_range(0, 2, 0.01, "or_greater") var dash_penalty_seconds: float = 0.6
@export_range(0, 2, 0.01, "or_greater") var dash_penalty_start_seconds: float = 0.2
@export_exp_easing var dash_penalty_ease: float = 1
@export_range(0, 2) var grounded_dash_speed_mult: float = 1
@export_range(0, 1) var dash_penalty_mult_min: float = 0.25
var dash_penalty_mult_max: float = 1  # Should not be controlled by user, that's other vars' job

@export_group("Crouching")
@export_range(0, 2) var crouch_seconds: float = 0.2


var timedelta: float
var grounded_timer: int
var remaining_dashes: int = dash_count

var is_on_ground: bool = false
var wish_jump: bool = false
var third_person: bool = false
var crouching: bool = false
var coyote: bool = true


func can_jump() -> bool:
    return (
        is_on_ground 
        or (coyote and grounded_timer > -coyote_ticks)
    )
    
func jump():
    velocity.y = max(jump_velocity, velocity.y)
    coyote = false
    
func can_dash() -> bool:
    return remaining_dashes > 0
    
func _calc_dash_mult() -> float:
    if is_on_ground:
        return grounded_dash_speed_mult
        
    var speed_mult: float = 1
    var time_off_ground: float = float(-grounded_timer) / Engine.physics_ticks_per_second
    speed_mult = (time_off_ground - dash_penalty_start_seconds) / dash_penalty_seconds
    speed_mult = ease(speed_mult, dash_penalty_ease)
    speed_mult = clamp(speed_mult, dash_penalty_mult_min, dash_penalty_mult_max)
    return speed_mult
    
func dash():
    var forwards: Vector3 = -camera.global_transform.basis.z.normalized()
    velocity += forwards * (dash_speed * _calc_dash_mult())
    #remaining_dashes -= 1
    
    
    
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


func move_and_slide_surf() -> bool:
    # Custom move_and_slide implementation that allows for surfing
    # https://github.com/EricXu1728/Godot4SourceEngineMovement/blob/0276011420626dbaa91e553bc81a56520db0ad2d/Scripts/playerMovementScripts/player.gd#L79-L126
    var collided: bool = false
    is_on_ground = false

    var checkMotion := velocity * (1/60.0)
    checkMotion.y  -= gravity * gravity_mult * (1/360.0)
    var testcol := move_and_collide(checkMotion, true)

    if testcol and testcol.get_normal().angle_to(up_direction) < floor_max_angle:
        is_on_ground = true

    # Loop performing the move
    var motion := velocity * timedelta
    for step in max_slides:
        var collision := move_and_collide(motion)
        if not collision: # If no collision has occured, we have moved the entire wanted distance
            break
        collided = true

        # Calculate velocity to slide along the surface
        var normal = collision.get_normal()
        motion = collision.get_remainder().slide(normal)
        velocity = velocity.slide(normal)
    return collided

    

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
    if is_on_ground:
        var control: float = stop_speed if stop_speed < speed else speed
        drop += control * friction * timedelta
        
    velocity *= maxf(0, speed - drop) / speed


func tick_movement() -> void:
    # Amalgimation of AirMove and GroundMove functions
    var old_velocity = velocity
    #is_on_ground = is_on_floor()
    
    # https://www.ryanliptak.com/blog/rampsliding-quake-engine-quirk/#what-about-surfing-like-in-counter-strike-surf-maps
    # https://github.com/id-Software/Quake/blob/bf4ac424ce754894ac8f1dae6a3981954bc9852d/QW/client/pmove.c#L587-L590
    if velocity.y > 180:  # FIXME: 180 is an absurd value in this ctx... div by like 50 or smth
        is_on_ground = false
        
    if is_on_ground and grounded_timer > bhop_tick_window:
        apply_friction()
        
    var max_speed = max_ground_speed if is_on_ground else max_air_speed
    var acceleration = ground_acceleration if is_on_ground else air_acceleration
    
    var input_dir = get_input_dir()
    accelerate(input_dir, max_speed, acceleration)
    velocity.y -= gravity * gravity_mult * timedelta
    
    var wish_jump: bool = false
    if auto_jump:
        wish_jump = Input.is_action_pressed(&"jump")
    else:
        wish_jump = Input.is_action_just_pressed(&"jump")
    if wish_jump and can_jump():
        jump()
        
    if Input.is_action_just_pressed(&"dash") and can_dash():
        dash()
    
    # FIXME: Don't steal this, but actually understand and reimplement it from scratch?
    # This might have worked in godot 3...
    # FIXME: Holding W (and S? find source) should not allow surfing
    # FIXME: Weird jittery motion when surfing?
    var prev_onground = is_on_ground
    move_and_slide_surf()
    if prev_onground and not is_on_ground:
        coyote = true


func _physics_process(delta):
    timedelta = delta
    
    if Input.is_action_just_pressed(&"crouch"):
        toggle_crouch()
        
    
    # FIXME: Move into tick movement
    if is_on_ground:
        if grounded_timer < 0:
            grounded_timer = 0
        grounded_timer += 1
    else:
        if grounded_timer > 0:
            grounded_timer = 0
        grounded_timer -= 1
    
    tick_movement()
    
    while debug_meshes:
        debug_meshes.pop_back().queue_free()
    #debug_meshes.append(Draw3d.line(position, position+Vector3(velocity.x, 0, velocity.z), Color.PALE_VIOLET_RED))
    #move_and_slide()
    #debug_meshes.append(Draw3d.line(position, position+Vector3(velocity.x, 0, velocity.z), Color.PURPLE))
    debug_meshes.append(Draw3d.line(position, position+velocity, Color.PURPLE))
    
var debug_meshes: Array[MeshInstance3D]
    

func _process(delta):
    if Input.is_action_just_pressed(&"third_person"):
        third_person = not third_person
    camera.position.z = 5 if third_person else 0

    
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    elif event.is_action_pressed("ui_cancel"):
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * look_sensitivity)
        neck.rotate_x(-event.relative.y * look_sensitivity)
        neck.rotation.x = clamp(neck.rotation.x, deg_to_rad(max_down_angle), deg_to_rad(max_up_angle))
