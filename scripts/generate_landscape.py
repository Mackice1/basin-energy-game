#!/usr/bin/env python3
"""Original deterministic synthetic desert basin. All generated assets dedicated CC0."""
from pathlib import Path
import json
import numpy as np
from scipy.ndimage import gaussian_filter, zoom
from PIL import Image, ImageDraw

OUT=Path(__file__).resolve().parents[1]/'generated'
OUT.mkdir(parents=True,exist_ok=True)
RNG=np.random.default_rng(240514)
N=1024; STEP=.25
coord=np.arange(N,dtype=np.float32)*STEP-128
X,Z=np.meshgrid(coord,coord)

def noise(shape,scale,seed):
    rng=np.random.default_rng(seed)
    a=rng.normal(size=shape).astype(np.float32)
    a=gaussian_filter(a,scale,mode='wrap')
    return a/(a.std()+1e-8)

def line_distance(points):
    d=np.full(X.shape,1e6,dtype=np.float32)
    for (ax,az),(bx,bz) in zip(points[:-1],points[1:]):
        dx=bx-ax; dz=bz-az
        t=np.clip(((X-ax)*dx+(Z-az)*dz)/(dx*dx+dz*dz),0,1)
        d=np.minimum(d,np.sqrt((X-ax-t*dx)**2+(Z-az-t*dz)**2))
    return d

def hill(cx,cz,wx,wz,angle,h):
    a=np.deg2rad(angle); u=(X-cx)*np.cos(a)+(Z-cz)*np.sin(a); v=-(X-cx)*np.sin(a)+(Z-cz)*np.cos(a)
    return h*np.exp(-((u/wx)**2+(v/wz)**2)*1.45)

# A low broad regional fall toward the enclosed southeastern playa.
base=.40-.0025*(X+35)-.002*(Z+5)
# Compact mountain groups; no continuous perimeter barrier.
mount=(hill(-79,-43,22,16,-27,17.8)+hill(-57,-48,19,14,22,16.3)
       +hill(-43,-32,14,13,-15,9.3)+hill(-18,-54,16,11,18,9.2)
       +hill(6,-48,12,9,-20,5.2))
# Coherent multi-scale rock relief, strongest where slopes expose bedrock.
coarse=noise((N,N),20,8); medium=noise((N,N),7,9); fine=noise((N,N),2.2,10)
mount*=np.clip(1+.055*coarse+.030*medium+.010*fine,.78,1.22)
# Radial drainage trees descend from crest shoulders, with branching headwaters.
channels=np.zeros_like(X)
for cx,cz,r,phase in [(-79,-43,24,.28),(-57,-48,22,.7),(-43,-32,18,.1),(-18,-54,17,.55)]:
    for k in range(7):
        ang=phase+k*2*np.pi/7+.20*np.sin(k*3.71+cx)
        def pt(rad,off=0):
            a=ang+off
            return (cx+rad*np.cos(a),cz+rad*np.sin(a))
        pts=[pt(r*.22,.08),pt(r*.42,-.06),pt(r*.65,.025),pt(r*.95,-.045),pt(r*1.28,.015)]
        dist=line_distance(pts)
        radial=np.sqrt((X-cx)**2+(Z-cz)**2)/r
        width=.55+.60*np.clip(radial,0,1.4)
        incision=np.exp(-(dist/width)**2)*np.clip((radial-.18)/.24,0,1)*np.clip((1.35-radial)/.5,0,1)
        channels=np.maximum(channels,incision)
        # Two tributaries join the middle trunk. Their upper tips are distinct.
        for sign in (-1,1):
            branch=[pt(r*.27,sign*.43),pt(r*.42,sign*.25),pts[2]]
            bd=line_distance(branch)
            channels=np.maximum(channels,.50*np.exp(-(bd/.52)**2)*np.clip((radial-.23)/.25,0,1)*np.clip(1.25-radial,0,1))
mount-=channels*np.minimum(1.05,mount*.14)
mount=np.maximum(mount,0)
# Alluvial aprons are low, broad and feather smoothly into the gravel plain.
fans=np.zeros_like(X)
for cx,cz,wx,wz,h in [(-64,-17,22,19,.65),(-33,-12,18,17,.53),(-5,-29,16,14,.38)]:
    fan=hill(cx,cz,wx,wz,-10,h)
    fan*=1+.035*np.sin((X-cx)*1.15+(Z-cz)*.37)
    fans+=fan
H=base+mount+fans
# Stable construction surface: millimetric-to-centimetric relief only away from uplands.
H+=.015*noise((N,N),12,43)+.006*noise((N,N),3,44)
# Continuous shallow ephemeral stream, a wide faint flood bench and inset thalweg.
channel_x=-28+Z*.2+np.sin(Z*.065)*7
cd=np.abs(X-channel_x)
main_sediment=np.exp(-(cd/3.2)**2)
H-=.66*np.exp(-(cd/1.8)**2)+.18*np.exp(-(cd/4.8)**2)
# Sparse shallow tributaries drain into the main wash, never across the build pad.
tributary=np.zeros_like(X)
for pts in [[(-67,3),(-55,6),(-41,9),(-30,14),(-18.3,20)],
            [(-2,57),(-8,54),(-13,48),(-17.9,43)],
            [(-52,-18),(-46,-15),(-40,-12),(-34.2,-10)]]:
    td=line_distance(pts)
    start,end=pts[0],pts[-1]
    along=np.clip(((X-start[0])*(end[0]-start[0])+(Z-start[1])*(end[1]-start[1]))/((end[0]-start[0])**2+(end[1]-start[1])**2),0,1)
    taper=np.sin(along*np.pi*.5)**1.3
    tributary=np.maximum(tributary,np.exp(-(td/1.15)**2)*taper)
H-=.30*tributary
sediment=np.maximum(main_sediment,tributary*.65)
# Quiet closed saline basin with gently sloping margins.
playa=np.exp(-(((X-32)/19)**2+((Z-38)/13)**2)*1.7)
H-=.50*playa
# Local SE dune patch: taper both whole erg and individual slightly curved ridges.
u=.87*(X-74)+.49*(Z-40); v=-.49*(X-74)+.87*(Z-40)
erg=np.exp(-((u/20)**4+(v/17)**4))
phase=u/5.1+.12*np.sin(v*.10)+.045*np.sin(v*.31)
crest=((1+np.cos(phase*2*np.pi))*.5)**3
ends=np.clip(1-(v/22)**2,0,1)**1.5
H+=erg*ends*(.14+1.05*crest)
# Preserve wholly smooth transitions across the complete square raster.
H=gaussian_filter(H,.7).astype('<f4')
H.tofile(OUT/'height.raw')
# Terrain3D control data: gravel base, smooth material overlays, boundary holes.
rock_weight=np.clip((mount-.65)/5,0,1)
# Broad irregular deposit margins avoid stamped geometric material islands.
warp_x=2.8*noise((N,N),30,901)+1.1*noise((N,N),11,902)
warp_z=2.3*noise((N,N),34,903)+.8*noise((N,N),12,904)
su=.87*(X-74+warp_x)+.49*(Z-40+warp_z)
sv=-.49*(X-74+warp_x)+.87*(Z-40+warp_z)
sand_weight=.85*np.exp(-((su/23)**2+(sv/16)**2)*1.25)
salt_weight=.90*np.exp(-(((X-32+warp_x)/17)**2+((Z-38+warp_z)/11)**2)*1.25)
sand_weight*=1-.045*noise((N,N),8,905)
salt_weight*=1-.055*noise((N,N),9,906)
sand_weight=np.clip(sand_weight,0,.90)
salt_weight=np.clip(salt_weight,0,.94)
weights=np.stack([rock_weight,sand_weight,salt_weight],axis=0)
overlay=np.argmax(weights,axis=0).astype(np.uint32)+1
blend=np.round(np.max(weights,axis=0)*255).astype(np.uint32)
control=(overlay<<22)|(blend<<14)
control[(X < -100)|(X > 100)|(Z < -70)|(Z > 70)]|=np.uint32(4)
control.astype('<u4').tofile(OUT/'control.raw')
variation=np.clip(.96+.018*noise((N,N),24,800)+.006*noise((N,N),4,801),.90,1)
cm=np.empty((N,N,4),dtype=np.uint8)
cm[:,:,:3]=np.uint8(np.clip(variation[:,:,None]*(1-sediment[:,:,None]*np.array([.105,.115,.12]))*255,0,255))
cm[:,:,3]=128
Image.fromarray(cm,'RGBA').save(OUT/'colormap.png')
# Shaded, colored preview: north (-Z) at the top; warm restrained original palette.
dz,dx=np.gradient(H,STEP)
shade=np.clip((-.5*dx-.6*dz+1.15)/np.sqrt(1+dx*dx+dz*dz),.26,1.4)
rock=np.clip(mount/7,0,1)[...,None]
rgb=np.array([176,157,124])*(1-rock)+np.array([125,112,92])*rock
rgb=rgb*(1-salt_weight[...,None]*.56)+np.array([176,172,155])*salt_weight[...,None]*.56
rgb=rgb*(1-sand_weight[...,None]*.55)+np.array([184,166,137])*sand_weight[...,None]*.55
rgb*=1-sediment[...,None]*.10
rgb*=np.clip(shade,.45,1.25)[...,None]
Image.fromarray(np.uint8(np.clip(rgb,0,255))).save(OUT/'height_preview.png')
# Original seamless material patterns. Periodic filtering + periodic coordinates ensure tiling.
S=512
q=np.arange(S,dtype=np.float32)/S
A,B=np.meshgrid(q,q)
for idx,(name,color,strength) in enumerate([('gravel',(171,154,126),1.1),('bedrock',(139,126,106),1.3),('sand',(184,166,137),.65),('salt',(176,172,155),.55)]):
    n1=noise((S,S),14,100+idx); n2=noise((S,S),3,200+idx); n3=noise((S,S),.65,300+idx)
    if name=='gravel':
        micro=.30*n1+.22*n2+.20*n3
        # Rounded gravel grains with sparse brighter quartz flecks.
        grain=np.maximum(noise((S,S),1.4,400)-.8,0)
        micro+=.18*grain
    elif name=='bedrock':
        bands=np.sin(2*np.pi*(9*A+3*B)+.5*n1)
        micro=.37*n1+.18*n2+.08*n3+.17*bands
    elif name=='sand':
        rip=np.cos(2*np.pi*(5*A+17*B)+.28*np.sin(2*np.pi*2*A))
        micro=.17*n1+.055*n2+.045*n3+.20*rip
    else:
        # Subtle closed salt plates from periodic Voronoi cells.
        rng=np.random.default_rng(512); pts=rng.uniform(0,1,(38,2)); nearest=np.full((S,S),9.); second=nearest.copy()
        for px,pz in pts:
            ddx=np.minimum(abs(A-px),1-abs(A-px)); ddz=np.minimum(abs(B-pz),1-abs(B-pz)); d=ddx*ddx+ddz*ddz
            second=np.minimum(second,np.maximum(nearest,d)); nearest=np.minimum(nearest,d)
        cracks=np.exp(-((np.sqrt(second)-np.sqrt(nearest))/.0035)**2)
        micro=.12*n1+.08*n2+.065*n3-.40*cracks
    # Low contrast at distance, readable microrelief close to ground.
    albedo=np.clip(np.array(color)[None,None,:]+micro[...,None]*17,0,255).astype(np.uint8)
    height_alpha=np.uint8(np.clip(128+micro*55,0,255))
    Image.fromarray(np.dstack([albedo,height_alpha]),'RGBA').save(OUT/f'{name}_albedo.png')
    Image.fromarray(np.uint8(np.clip(128+micro*55,0,255)),'L').save(OUT/f'{name}_height.png')
    gx=(np.roll(micro,-1,axis=1)-np.roll(micro,1,axis=1))*.5*strength
    gy=(np.roll(micro,-1,axis=0)-np.roll(micro,1,axis=0))*.5*strength
    normal=np.stack([-gx,-gy,np.ones_like(gx)],axis=-1)
    normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
    normal_rgb=np.uint8(np.clip((normal*.5+.5)*255,0,255))
    Image.fromarray(np.dstack([normal_rgb,np.full((S,S),230,dtype=np.uint8)]),'RGBA').save(OUT/f'{name}_normal.png')

metadata={'license':'CC0-1.0','authorship':'Original procedural generation; no third-party imagery or elevation data.', 'generator':'scripts/generate_landscape.py','seed':240514,'heightfield':{'file':'height.raw','format':'IEEE754 float32 little-endian, row-major','shape':[N,N],'spacing_world_units':STEP,'bounds_world_units':{'x_min':-128,'z_min':-128,'x_max_exclusive':128,'z_max_exclusive':128},'axis':'row increases +Z south; column increases +X east; elevation is +Y','world_meters_per_unit':10,'minimum':float(H.min()),'maximum':float(H.max()),'byte_count':H.nbytes},'materials':{'resolution':[512,512],'tileable':True,'names':['gravel','bedrock','sand','salt'],'normal_convention':'RGB tangent normal, +Y; invert green if a consumer requires -Y','material_ids':{'gravel':0,'bedrock':1,'sand':2,'salt':3},'albedo_alpha':'height','normal_alpha':'roughness 230/255','albedo_color_space':'sRGB','normal_color_space':'linear'},'landforms':{'northwest_mountains':'Compact eroded groups, not perimeter walls; northernmost main peaks Z=-48.','construction_plain':'Central and southern gravel plain has broad regional slope and very low relief.','playa_center':[32,38],'dry_channel':'x=-28+0.2*z+7*sin(0.065*z)','southeast_dunes_center':[74,40]}}
metadata['playable_domain']={'profile':'metric_4km_core_preserved_v1','bounds_world_units':{'x_min':-200,'x_max':200,'z_min':-200,'z_max':200},'dimensions_m':[4000,4000],'original_visible_core_world_units':[200,140],'core_height_samples_unchanged':True,'extension':'Runtime low-poly mesh and analytic core-preserving height; not a regenerated Terrain3D raster.'}
(OUT/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
(OUT/'GENERATION_NOTES.md').write_text('''# Synthetic desert basin generation\n\nAll height and material assets are original procedural works dedicated to the public domain under CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/). No satellite imagery, DEM, stock textures, or image-generation model output is used.\n\nRun `python scripts/generate_landscape.py` from any working directory. Requires Python 3, NumPy, SciPy and Pillow. Seeds are fixed.\n\nThe raster contains 1024 x 1024 little-endian 32-bit float samples at 0.25 world-unit spacing. The first sample is (-128,-128), last (127.75,127.75). World scale is 10 meters per unit. The runtime playable domain is 400 x 400 world units (4 x 4 km); this file remains the unchanged original core raster, not the whole expanded domain. North is negative Z. Read rows as Z and columns as X. Height values are already world-unit elevations; do not normalize to 0..1. Mask terrain beyond the playable rectangle separately.\n\nCompact northwestern uplands are constructed from anisotropic overlapping mountain groups, coherent low-amplitude rock structure, and explicit branching drainage incision. Their broad alluvial aprons fade onto nearly level construction ground. A meandering dry channel follows the requested alignment with an approximately 0.84-unit inset, sparse shallow tributaries and subtly darker gravel sediment. Sand and salt controls have broad irregular domain-warped feathered margins; the salt palette is reduced 20 percent and sand is muted. A shallow salt depression lies at (32,38). A localized southeastern erg has curved ridges whose ends and overall patch taper continuously.\n\nTextures are 512 px, seamless procedural RGBA albedo (height in alpha) plus grayscale height and RGBA tangent normals (roughness 230/255 in alpha). IDs are 0 gravel, 1 bedrock, 2 sand, 3 salt; filenames are {name}_albedo.png, {name}_height.png, {name}_normal.png. control.raw is uint32 little-endian with overlay ID at bit 22, blend at bit 14, base gravel ID 0, and outside-playable-area hole flag 4. colormap.png is subtly varied near-white RGBA, with neutral roughness alpha 128. Tile with repeat enabled. Albedo is sRGB. Normal textures must be imported as normal maps/linear data. Derivatives use periodic finite differences; all noise uses periodic filtering. Colors and contrast are restrained for landscape-scale use.\n\nThis is deliberately designed synthetic scenery, not a geological reconstruction or accurate real-world elevation map.\n''')
print(json.dumps({'output':str(OUT),'min':float(H.min()),'max':float(H.max()),'bytes':H.nbytes}))
