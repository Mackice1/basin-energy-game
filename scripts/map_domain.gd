extends RefCounted
## Single metric domain. Legacy core samples and device coordinates never rescale.
const METERS_PER_UNIT: float = 10.0
const WORLD_UNITS_PER_METER: float = 0.1
const HALF_EXTENTS := Vector2(200.0, 200.0)
const WORLD_SIZE := Vector2(400.0, 400.0)
const CORE_HALF_EXTENTS := Vector2(100.0, 70.0)
const BUILD_GRID_WORLD: float = 1.0 # 10 m; independent of terrain tessellation.
const MAJOR_GRID_WORLD: float = 10.0 # 100 m survey interval.
const CORE_SAMPLE_COLLAR: float = 1.0 # preserves every core +/-0.5 slope stencil.
const EXTENSION_BLEND_WORLD: float = 24.0

static func contains(p: Vector2, radius_world: float = 0.0) -> bool:
 return p.is_finite() and is_finite(radius_world) and radius_world >= 0.0 and absf(p.x)+radius_world<=HALF_EXTENTS.x and absf(p.y)+radius_world<=HALF_EXTENTS.y

static func clamp_point(p: Vector2) -> Vector2:
 return Vector2(clampf(p.x,-HALF_EXTENTS.x,HALF_EXTENTS.x),clampf(p.y,-HALF_EXTENTS.y,HALF_EXTENTS.y)) if p.is_finite() else Vector2.ZERO

static func world_to_meters(value: float) -> float:
 return value*METERS_PER_UNIT

static func in_core(p: Vector2, collar: float = 0.0) -> bool:
 return absf(p.x)<=CORE_HALF_EXTENTS.x+collar and absf(p.y)<=CORE_HALF_EXTENTS.y+collar

static func regional_plain(x: float,z: float) -> float:
 # Same original generator's broad regional fall, not flattened/rescaled raster.
 return .40-.0025*(x+35.0)-.002*(z+5.0)

static func extension_height(x: float,z: float, original_sample: Callable) -> float:
 var p:=Vector2(x,z)
 if in_core(p,CORE_SAMPLE_COLLAR):return float(original_sample.call(x,z))
 var sample_extents:=CORE_HALF_EXTENTS+Vector2.ONE*CORE_SAMPLE_COLLAR
 var edge:=Vector2(clampf(x,-sample_extents.x,sample_extents.x),clampf(z,-sample_extents.y,sample_extents.y))
 var delta:=p-edge
 var outward:=maxf(absf(delta.x),absf(delta.y))
 if outward>=EXTENSION_BLEND_WORLD:return regional_plain(x,z)
 var h:float=original_sample.call(edge.x,edge.y)
 var gx:float=(float(original_sample.call(edge.x+.25,edge.y))-float(original_sample.call(edge.x-.25,edge.y)))*2.0
 var gz:float=(float(original_sample.call(edge.x,edge.y+.25))-float(original_sample.call(edge.x,edge.y-.25)))*2.0
 var t:=clampf(outward/EXTENSION_BLEND_WORLD,0.0,1.0)
 var blend:=t*t*(3.0-2.0*t)
 var tangent_fade:=pow(maxf(0.0,1.0-outward/6.0),3.0)
 # Match the original edge tangent locally without magnifying tiny raster
 # noise into long artificial ridges across the new construction plain.
 return lerpf(h+(gx*delta.x+gz*delta.y)*tangent_fade,regional_plain(x,z),blend)
