from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
D=Path(__file__).resolve().parents[1]/'evidence/equipment_v22'
f='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
title=ImageFont.truetype(f,28);label=ImageFont.truetype(f,22);small=ImageFont.truetype(f,19)
for asset,name,desc in [('thermal_store','90/60°C 水储热双筒','金属保温护板、窄识别带、检修人孔与实体供回水接管'),('electric_boiler','电热水锅炉','电热接线盒、顶部供水口、压力表与管托，不设烟囱'),('heat_exchanger','板式换热器','固定前板四角管口、独立回路、薄板束和压紧拉杆'),('wind_foundation','风机基础与出线','真实比例入口、锚栓和地面电缆管沟'),('wind_nacelle','风机机舱','机舱与塔身比例修正、检修盖和通风百叶')]:
 canvas=Image.new('RGB',(1600,790),'#19212b');d=ImageDraw.Draw(canvas)
 d.text((28,14),name+'｜实际 GLB 离屏渲染对比',font=title,fill='#e8edf1')
 d.text((28,56),'这是模型副本审阅图，不代表游戏整合已完成。相同镜头、光照与尺度。',font=small,fill='#acbbc5')
 for index,(stage,caption) in enumerate([('before','V21 原模型'),('after','V22 美化副本')]):
  im=Image.open(D/stage/f'{asset}.png').convert('RGB');im=im.resize((800,640));canvas.paste(im,(index*800,100));d.text((index*800+22,105),caption,font=label,fill='#18242b')
 d.text((28,751),desc,font=label,fill='#c6d8df');canvas.save(D/f'compare_{asset}.png')
 print(D/f'compare_{asset}.png')
