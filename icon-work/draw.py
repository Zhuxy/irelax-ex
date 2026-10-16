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

# 盘子放大
d.ellipse([222, 687, 802, 743], fill=BLK)
# 蛋糕
d.rounded_rectangle([272, 410, 752, 690], radius=36, fill=BLK)
d.rectangle([304, 442, 720, 658], fill=(255, 246, 0))
pink = (255, 143, 171)
pts = [(304, 442), (720, 442)]
for x in range(720, 303, -8):
    pts.append((x, 525 + 9*math.sin(x/45)))
d.polygon(pts, fill=pink)
d.rectangle([304, 598, 720, 658], fill=(123, 74, 33))
# 樱桃
d.ellipse([472, 348, 552, 428], fill=(235, 60, 50))
d.ellipse([488, 362, 510, 384], fill=(255,255,255))
d.line([512, 352, 526, 318], fill=BLK, width=8)
# 叉子 v2：细长齿 + 梯形收腰
fx = 850
for i in range(4):
    x0 = 809 + i*24
    d.rounded_rectangle([x0, 475, x0+11, 570], radius=5, fill=BLK)
d.polygon([(809,565), (892,565), (861,605), (839,605)], fill=BLK)  # 收腰
d.rounded_rectangle([839, 605, 861, 735], radius=11, fill=BLK)      # 柄
img.save('/tmp/cake_v6.png')
print('saved')
