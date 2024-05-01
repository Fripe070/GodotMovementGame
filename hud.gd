extends CanvasLayer


@export var player: CharacterBody3D


func _ready():
    pass

func _process(delta):
    $VelocityLabelX.text = str(player.velocity.x)
    $VelocityLabelY.text = str(player.velocity.y)
    $VelocityLabelZ.text = str(player.velocity.z)
    $VelocityLabelMag.text = str(player.velocity.length())
    
    $FPSLabel.text = "FPS: %s" % int(1/delta)
