@tool
class_name PropStroke
extends Path3D


const EDIT_HEIGHT: float = 32.


@export_tool_button("Respawn", "Callable") var action_respawn = _spawn
@export_tool_button("Make Unique", "Callable") var action_make_unique = _make_unique

@export var item_count: int = 32:
	set(v): item_count = v; if is_node_ready(): _spawn()
@export var fill_tint: Gradient
@export_range(1000, 2000) var seed: int = 1000:
	set(v):	
		seed = v; 
		if is_node_ready(): 
			rng.seed = hash("%d" % seed)
			_spawn()
@export var jitter_rotation_range_x: Vector2:
	set(v):
		jitter_rotation_range_x = Vector2(
			clampf(v.x, -PI, PI),
			clampf(v.y, -PI, PI)
		)
		if is_node_ready(): _spawn()
@export var jitter_rotation_range_y: Vector2 = Vector2(-PI, PI):
	set(v):
		jitter_rotation_range_y = Vector2(
			clampf(v.x, -PI, PI),
			clampf(v.y, -PI, PI)
		)
		if is_node_ready(): _spawn()
@export var jitter_rotation_range_z: Vector2:
	set(v):
		jitter_rotation_range_z = Vector2(
			clampf(v.x, -PI, PI),
			clampf(v.y, -PI, PI)
		)
		if is_node_ready(): _spawn()

@export var density_curve: Curve
@export var jitter_tangent_range: float = 0.:
	set(v): jitter_tangent_range = v; if is_node_ready(): _spawn()
@export var jitter_tangent_curve: Curve
@export var jitter_lateral_range: float = 0.:
	set(v): jitter_lateral_range = v; if is_node_ready(): _spawn()
@export var jitter_lateral_curve: Curve
@export_range(0., 1.) var jitter_scale_range: float = 0.:
	set(v): jitter_scale_range = v; if is_node_ready(): _spawn()
@export var jitter_scale_curve: Curve
@export_flags_3d_physics var snap_layers: int = 0x01 << 3:
	set(v): snap_layers = v; if is_node_ready(): _spawn()
@export_range(-15., 15.) var added_push_down: float = 0.:
	set(v): added_push_down = v; if is_node_ready(): _spawn()
@export_range(-15., 15.) var added_push_normal: float = 0.:
	set(v): added_push_normal = v; if is_node_ready(): _spawn()

@export var flag_wind_affected				: bool = false
@export var flag_align_normal_direction		: bool = false

var mms										: Array[MultiMeshInstance3D]
var mms_bodies								: Array[StaticBody3D]
var mms_collider_templates					: Array[CollisionShape3D]

var mms_collider_templates_static			: Array[CollisionShape3D]
var mms_collider_offsets_static				: Array[Transform3D]

var mms_collider_templates_reactive			: Array[CollisionShape3D]
var mms_collider_offsets_reactive			: Array[Transform3D]

var rng										: RandomNumberGenerator
var body									: StaticBody3D = null
var area									: Area3D = null

var stored_position: Vector3


class Reconfig extends mio.Reconfig:
	var x: PropStroke
	func _init(_x): x = _x
	func _process() -> void: 
		x._spawn()
var reconfig: Reconfig = Reconfig.new(self)


func _ready() -> void:
	rng = RandomNumberGenerator.new()
	mms = []
	mms_bodies = []
	mms_collider_templates = []
	for i in get_children(): 
		if i is MultiMeshInstance3D: mms.push_back(i)
		if i is StaticBody3D: body = i
		if i is Area3D: area = i
	
	
	if Engine.is_editor_hint():	
		if curve:
			if not curve.changed.is_connected(_spawn): curve.changed.connect(_spawn)
		if fill_tint:
			if not fill_tint.changed.is_connected(_spawn): fill_tint.changed.connect(_spawn)
		if density_curve:
			if not density_curve.changed.is_connected(_spawn): density_curve.changed.connect(_spawn)
		if jitter_scale_curve:
			if not jitter_scale_curve.changed.is_connected(_spawn): jitter_scale_curve.changed.connect(_spawn)
		if jitter_lateral_curve:
			if not jitter_lateral_curve.changed.is_connected(_spawn): jitter_lateral_curve.changed.connect(_spawn)
		if jitter_tangent_curve:
			if not jitter_tangent_curve.changed.is_connected(_spawn): jitter_tangent_curve.changed.connect(_spawn)

func _physics_process(_delta: float) -> void:
	if not Engine.is_editor_hint(): return
	if (stored_position - global_position).length() > 0.02:
		stored_position = global_position
		reconfig.post()


func _spawn() -> void:
	rng.seed = hash("%d" % seed)
	
	rotation = Vector3.ZERO
	
	if not mms.size() > 0: return

	var idx_mm := PackedInt32Array()
	var iter_mm : Array[int] = []
	iter_mm.resize(mms.size())
	idx_mm.resize(item_count)
	mms_bodies.resize(mms.size())
	mms_collider_templates.resize(mms.size())
	for i in item_count: idx_mm[i] = range(mms.size())[rng.randi_range(0, mms.size() - 1)]
	for i in mms.size(): 
		mms[i].multimesh.instance_count = Array(idx_mm).filter( func (x): return x == i).size()
		var check_is_body: Callable = func(x) : return x is StaticBody3D
		var check_is_collider: Callable = func(x) : return x is CollisionShape3D
		if mms[i].get_children().any(check_is_body): 
			mms_bodies[i] = mms[i].get_children().filter(check_is_body).front()
			if mms_bodies[i].get_children().any(check_is_collider):
				mms_collider_templates[i] = mms_bodies[i].get_children().filter(check_is_collider).front()
	
	
	
	var dss := get_world_3d().direct_space_state
	var cast_q := PhysicsRayQueryParameters3D.new()
	cast_q.collide_with_bodies = true
	cast_q.collide_with_areas = false
	cast_q.collision_mask = snap_layers
	
	for i in item_count:
		
		var t := Transform3D.IDENTITY
		var scale_mod: float = (1. + rng.randf_range(-jitter_scale_range, jitter_scale_range)) * jitter_scale_curve.sample(float(i) / float(item_count))
		t = t.scaled_local(Vector3.ONE * scale_mod)
		
		var s: float = float(i) / float(item_count)
		var o: Vector3 = curve.sample_baked(curve.get_baked_length() * density_curve.sample(s))
		var v_tangent = (curve.sample_baked(float(i + 1) / float(item_count + 1) * curve.get_baked_length()) - o).normalized()
		var v_lateral = (v_tangent).cross(Vector3.UP).normalized()
		var jitter: Vector3 = rng.randf_range(-1., 1.) * jitter_tangent_range * jitter_tangent_curve.sample(float(i) / float(item_count)) * v_tangent
		var lateral_value = rng.randf_range(0., 1)
		jitter += (lateral_value * 2. - 1.) * jitter_lateral_range * jitter_lateral_curve.sample(float(i) / float(item_count)) * v_lateral
		
		o += jitter
		
		cast_q.from = global_position + o + Vector3.UP * 128.
		cast_q.to = global_position + o + Vector3.DOWN * 258.
		
		var cast_r: Dictionary = dss.intersect_ray(cast_q)
		
		if not cast_r.is_empty():
			if flag_align_normal_direction:
				t.basis = Basis.looking_at((cast_r["normal"] as Vector3).cross(Vector3.UP))
				t = t.scaled(Vector3.ONE * scale_mod)
			t.origin = cast_r["position"] - global_position
			t.origin -= cast_r["normal"] * added_push_normal * scale_mod
		else:
			t.origin = Vector3(o.x, 0., o.z)
		t.origin.y -= added_push_down * scale_mod
		
		t = t.rotated_local(Vector3.UP, rng.randf_range(jitter_rotation_range_y.x, jitter_rotation_range_y.y))
		t = t.rotated_local(Vector3.RIGHT, rng.randf_range(jitter_rotation_range_x.x, jitter_rotation_range_x.y))
		t = t.rotated_local(Vector3.FORWARD, rng.randf_range(jitter_rotation_range_z.x, jitter_rotation_range_z.y))
	
		mms[idx_mm[i]].multimesh.set_instance_transform(iter_mm[idx_mm[i]], t)
		var sampled_color: Color = fill_tint.sample(clampf(1. - lateral_value, 0., 1.))
		mms[idx_mm[i]].multimesh.set_instance_color(iter_mm[idx_mm[i]], sampled_color)
		mms[idx_mm[i]].multimesh.set_instance_custom_data(iter_mm[idx_mm[i]], Color(randf(), randf(), 0., 0.))
		iter_mm[idx_mm[i]] += 1
	if not Engine.is_editor_hint(): _spawn_colliders()

func _spawn_colliders() -> void:
	if not (body or area): return
	mms_collider_templates_static = []
	mms_collider_offsets_static = []
	
	mms_collider_templates_static.resize(mms.size())
	mms_collider_offsets_static.resize(mms.size())
	mms_collider_templates_reactive.resize(mms.size())
	mms_collider_offsets_reactive.resize(mms.size())

	for i in mms.size():
		var collider_static: CollisionShape3D = null
		var collider_reactive: CollisionShape3D = null
		for j in mms[i].get_children():
			if j is CollisionShape3D: 
				if not "react" in j.name:
					collider_static = j
				else:
					collider_reactive = j
		mms_collider_templates_static[i] = collider_static
		if collider_static: mms_collider_offsets_static[i] = collider_static.transform
		mms_collider_templates_reactive[i] = collider_reactive
		if collider_reactive: mms_collider_offsets_reactive[i] = collider_reactive.transform
	
	if body: for i in body.get_children(): i.queue_free()
	await get_tree().create_timer(0.1).timeout
	
	for i in mms.size():
		if mms_collider_templates_static[i]:
			for j in mms[i].multimesh.instance_count:
				if body:
					var new_collider = CollisionShape3D.new()
					body.add_child(new_collider)
					new_collider.owner = self
					new_collider.shape = mms_collider_templates_static[i].shape
					new_collider.transform = mms[i].multimesh.get_instance_transform(j)
					new_collider.transform *= mms_collider_offsets_static[i]
		if mms_collider_templates_reactive[i]:
			for j in mms[i].multimesh.instance_count:
				if area:
					var new_collider = CollisionShape3D.new()
					area.add_child(new_collider)
					new_collider.owner = self
					new_collider.shape = mms_collider_templates_reactive[i].shape
					new_collider.transform = mms[i].multimesh.get_instance_transform(j)
					new_collider.transform *= mms_collider_offsets_reactive[i]

	
func _make_unique() -> void:
	curve = curve.duplicate()
	
	curve.changed.connect(_spawn)
	if fill_tint: fill_tint = fill_tint.duplicate(true)
	if density_curve: density_curve = density_curve.duplicate(true)
	if jitter_scale_curve: jitter_scale_curve = jitter_scale_curve.duplicate(true)
	if jitter_lateral_curve: jitter_lateral_curve = jitter_lateral_curve.duplicate(true)
	if jitter_tangent_curve: jitter_tangent_curve = jitter_tangent_curve.duplicate(true)
	
	for i in [fill_tint, density_curve, jitter_scale_curve, jitter_lateral_curve, jitter_tangent_curve]:
		if i:
	#		i = (i as Resource).duplicate()
			for j in (i as Resource).changed.get_connections(): (i as Resource).changed.disconnect(j)
			(i as Resource).changed.connect(_spawn)
	
	for i: MultiMeshInstance3D in mms:
		i.multimesh = i.multimesh.duplicate()
