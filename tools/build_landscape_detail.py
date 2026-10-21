"""Original procedural color detail only; never changes height/control/biomes.
Same 1024px replacement color map, no extra shader samples or geometry.
"""
from pathlib import Path
import numpy as np
from scipy.ndimage import gaussian_filter
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
rng=np.random.default_rng(1002)
a=np.asarray(Image.open(ROOT/'generated/colormap.png').convert('RGBA')).copy()
z,x=np.mgrid[-128:128:0.25,-128:128:0.25]
def field(sigma):
 n=gaussian_filter(rng.normal(size=x.shape),sigma,mode='wrap'); return n/(np.std(n)+1e-8)
def smooth(lo,hi,v):
 t=np.clip((v-lo)/(hi-lo),0,1);return t*t*(3-2*t)
macro=field(26);meso=field(6);fine=field(1.2)
# Broad, feathered mineral stains; no sharp biome rectangle boundaries.
var=np.clip(0.965+0.022*macro+0.014*meso+0.006*fine,0.86,1.04)
rgb=a[:,:,:3].astype(float)/255
rgb*=var[:,:,None]
fan=smooth(-42,-20,z)*(1-smooth(-11,8,z))
striations=np.sin(x*0.65+z*0.12+field(35)*1.8)
rgb*= (1-0.035*fan*(striations*.5+.5))[:,:,None]
sand=smooth(33,47,x+macro)*(smooth(20,32,z+meso))
ripples=np.sin(x*1.7+z*.7+1.4*np.sin(z*.13))
rgb+=sand[:,:,None]*ripples[:,:,None]*np.array([.013,.011,.006])
salt=1-smooth(10,16,np.hypot(x-32,z-38)+macro*.7)
veins=(1-smooth(.04,.16,np.abs(np.sin(x*.43+meso*.8)*np.sin(z*.36+macro))))
rgb-=salt[:,:,None]*veins[:,:,None]*np.array([.025,.027,.03])
# Warm oxidized gravel/cool stone variation is baked rather than shader-generated.
tint=field(45)
rgb+=tint[:,:,None]*np.array([.009,.002,-.008])
a[:,:,:3]=(np.clip(rgb,0,1)*255).astype(np.uint8)
Image.fromarray(a).save(ROOT/'generated/landscape_detail_colormap.png',optimize=True)
print('Wrote 1024x1024 RGBA landscape color replacement; height/control untouched.')
