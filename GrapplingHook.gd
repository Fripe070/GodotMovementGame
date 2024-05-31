extends Node3D


@export var apply_force_to: CharacterBody3D
@export var raycast_origin: Node3D = null
@export var render_origin: Node3D = null
@export var excludes: Array[CollisionObject3D]
@export var distance: float = 60.0
@export var force: float = 30.0

var is_attached: bool = false

signal grapple_thrown
signal grapple_attached(info: Dictionary)
signal grapple_detached

var attached_pos: Vector3

func on_attach(info: Dictionary):
    is_attached = true
    attached_pos = info.position

func on_detached(info: Dictionary):
    is_attached = false

func _ready():
    if raycast_origin == null:
        raycast_origin = self
    if render_origin == null:
        render_origin = raycast_origin
    grapple_attached.connect(on_attach)
        

func get_hit(collision_mask: int = 0xFFFFFFFF):
    var exclude_rids = []
    for node in excludes:
        exclude_rids.append(node.get_rid())
    
    var ray_vec = raycast_origin.global_position - raycast_origin.global_transform.basis.z * distance
    var query = PhysicsRayQueryParameters3D.create(
        raycast_origin.global_position, 
        ray_vec, 
        collision_mask,
        exclude_rids,
    )
    var space_state = get_world_3d().direct_space_state
    return space_state.intersect_ray(query)


func _physics_process(delta) -> void:
    if Input.is_action_just_pressed(&"grapple"):
        grapple_thrown.emit()
        is_attached = false
        
        var hit = get_hit()
        if not hit:
            return
        grapple_attached.emit(hit)
        is_attached = true
        
    if Input.is_action_just_released(&"grapple"):
        is_attached = false
        grapple_detached.emit()
    
    apply_constraint(delta)


func apply_constraint(delta: float) -> void:
    if not is_attached:
        return
    var drag_dir = (attached_pos - global_position).normalized()
    
    apply_force_to.velocity += drag_dir * force * delta
    Draw3d.line(render_origin.global_position, attached_pos, Color.ORANGE)


