import ctypes as c, json, sys, time, subprocess, os
x=c.CDLL('libX11.so.6'); t=c.CDLL('libXtst.so.6')
x.XOpenDisplay.argtypes=[c.c_char_p];x.XOpenDisplay.restype=c.c_void_p
d=x.XOpenDisplay(os.environ['DISPLAY'].encode());assert d
x.XFlush.argtypes=[c.c_void_p];x.XKeysymToKeycode.argtypes=[c.c_void_p,c.c_ulong];x.XKeysymToKeycode.restype=c.c_uint
x.XStringToKeysym.argtypes=[c.c_char_p];x.XStringToKeysym.restype=c.c_ulong
t.XTestFakeMotionEvent.argtypes=[c.c_void_p,c.c_int,c.c_int,c.c_int,c.c_ulong]
t.XTestFakeButtonEvent.argtypes=[c.c_void_p,c.c_uint,c.c_int,c.c_ulong]
t.XTestFakeKeyEvent.argtypes=[c.c_void_p,c.c_uint,c.c_int,c.c_ulong]
def move(p): t.XTestFakeMotionEvent(d,-1,int(p[0]),int(p[1]),0);x.XFlush(d)
def button(b,v):t.XTestFakeButtonEvent(d,b,v,0);x.XFlush(d)
def key(k,v):t.XTestFakeKeyEvent(d,x.XKeysymToKeycode(d,x.XStringToKeysym(k.encode())),v,0);x.XFlush(d)
print('NATIVE_DRIVER_READY',flush=True)
for line in sys.stdin:
 try:
  a=json.loads(line);op=a['op']
  if op=='move':move(a['p'])
  elif op=='click':
   move(a['p']);time.sleep(.2)
   for _ in range(a.get('n',1)):button(a.get('button',1),1);time.sleep(.08);button(a.get('button',1),0);time.sleep(.10)
  elif op=='down':move(a['p']);button(a.get('button',1),1)
  elif op=='up':move(a['p']);button(a.get('button',1),0)
  elif op=='drag':
   pts=a['path'];move(pts[0]);button(a.get('button',1),1);time.sleep(.3)
   for p in pts[1:]:move(p);time.sleep(a.get('step',.3))
   if not a.get('hold',False):button(a.get('button',1),0)
  elif op=='key':
   keys=a['key'].split('+')
   for k in keys:key(k,1)
   time.sleep(.1)
   for k in reversed(keys):key(k,0)
  elif op=='shot':
   subprocess.run(['import','-window','root',a['path']],check=True)
  elif op=='record':
   rec=subprocess.Popen(['ffmpeg','-y','-loglevel','error','-f','x11grab','-video_size','1440x900','-framerate','10','-i',os.environ['DISPLAY']+'+0,0','-c:v','libx264','-preset','ultrafast','-crf','24','-pix_fmt','yuv420p',a['path']],stdin=subprocess.PIPE)
  elif op=='stop_record':rec.communicate(b'q',timeout=20)
  elif op=='wait':time.sleep(a.get('s',1))
  elif op=='quit':break
  print('DONE',a,flush=True)
 except Exception as e:print('ERROR',str(e),flush=True)
