from PIL import Image, ImageDraw
import numpy as np, math

S = 1024
yy, xx = np.mgrid[0:S, 0:S].astype(float)
r = np.clip(np.sqrt((xx-512)**2 + (yy-512)**2) / 512, 0, 1)
c0 = np.array([178, 255, 165]); c1 = np.array([128, 255, 110])
bg = (c0[None,None,:]*(1-r[:,:,None]) + c1[None,None,:]*r[:,:,None]).astype(np.uint8)
img = Image.fromarray(bg, 'RGB')
d = ImageDraw.Draw(img)
BLK = (0,0,0)

d.rounded_rectangle([272, 430, 752, 710], radius=36, fill=BLK)
d.rectangle([304, 462, 720, 678], fill=(255, 246, 0))
pink = (255, 143, 171)
pts = [(304, 462), (720, 462)]
for x in range(720, 303, -8):
    pts.append((x, 545 + 9*math.sin(x/45)))
d.polygon(pts, fill=pink)
d.rectangle([304, 618, 720, 678], fill=(123, 74, 33))  # 巧克力直角，黑边自然收圆角
# 樱桃放大，坐进黑边里
d.ellipse([472, 368, 552, 448], fill=(235, 60, 50))
d.ellipse([488, 382, 510, 404], fill=(255,255,255))
d.line([512, 372, 526, 338], fill=BLK, width=8)
img.save('/tmp/cake_v3.png')
print('saved')
