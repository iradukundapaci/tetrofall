"""Combine the two Gemini feature-graphic concepts into one 1024x500 candidate.

The two renders share a palette, a light direction and a wordmark position, so
they composite cleanly:

  Gemini_..._3evonw...  the base - raked board, real depth, tetrominoes still
                        in the air, one row glowing as it clears at y=531
  Gemini_..._2cq4qy...  donates the payoff - the wood shards bursting off its
                        card edges, luminance-keyed off the dark backdrop and
                        replanted along the clearing row

On top of that: a hotter seam, dust lifting off the break, and the wordmark
moved from x55 to x166 so it clears Play's centre-80% crop.

    python3 tools/store/feature_combine.py     # run from the repo root

Writes gameplay/feature/04_wood_shatter.png (upload) and _master.png (1488x720).
"""
import os, math, random, numpy as np
from PIL import Image, ImageFilter, ImageDraw, ImageChops, ImageEnhance
random.seed(7)

SRC='gameplay/feature/'
A_IMG=SRC+'Gemini_Generated_Image_2cq4qy2cq4qy2cq4.jpeg'
B_IMG=SRC+'Gemini_Generated_Image_3evonw3evonw3evo.jpeg'


def _label(mask):
    """4/8-connected component labels, so each shard can be placed on its own."""
    from collections import deque
    h,w=mask.shape
    lab=np.zeros((h,w),np.int32); seen=np.zeros((h,w),bool); n=0
    for y0,x0 in zip(*np.nonzero(mask)):
        if seen[y0,x0]: continue
        n+=1; q=deque([(y0,x0)]); seen[y0,x0]=True
        while q:
            y,x=q.popleft(); lab[y,x]=n
            for dy in(-1,0,1):
                for dx in(-1,0,1):
                    yy,xx=y+dy,x+dx
                    if 0<=yy<h and 0<=xx<w and mask[yy,xx] and not seen[yy,xx]:
                        seen[yy,xx]=True; q.append((yy,xx))
    return lab,n


def cut_shards():
    """Key the shatter debris out of concept A's dark backdrop, one shard each.

    Only the strips outside the card (x<754 and x>1196) are sampled - there the
    shards are bright wood on a dark blurred wall, so a luminance ramp lifts them
    with no matte work. Boxes are (crop, low, high) with the ramp tuned per side.
    """
    A=Image.open(A_IMG).convert('RGB')
    a=np.asarray(A).astype(np.float32)
    lum=a[...,0]*0.35+a[...,1]*0.45+a[...,2]*0.20
    out=[]
    for (x0,y0,x1,y1),lo,hi in [((596,140,754,480),74,118), ((1196,140,1420,480),60,100)]:
        m=np.clip((lum[y0:y1,x0:x1]-lo)/(hi-lo),0,1)
        mi=Image.fromarray((m*255).astype(np.uint8))
        # close the ramp over the shadowed faces before feathering the edge
        mi=mi.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
        mi=mi.filter(ImageFilter.GaussianBlur(1.0))
        sprite=A.crop((x0,y0,x1,y1)).convert('RGBA'); sprite.putalpha(mi)
        lab,n=_label(np.asarray(sprite.getchannel('A'))>40)
        for i in range(1,n+1):
            ys,xs=np.nonzero(lab==i)
            if len(ys)<180: continue
            by0,by1,bx0,bx1=ys.min(),ys.max()+1,xs.min(),xs.max()+1
            if (bx1-bx0)<10 or (by1-by0)<10: continue
            pa=np.asarray(sprite.crop((bx0,by0,bx1,by1))).copy()
            pa[...,3]=(pa[...,3]*(lab[by0:by1,bx0:bx1]==i)).astype(np.uint8)
            out.append(Image.fromarray(pa))
    out.sort(key=lambda im:-im.size[0]*im.size[1])
    return out

B=Image.open(B_IMG).convert('RGB')
Wd,Ht=B.size
shards=cut_shards()

base=B.convert('RGBA')
SEAM=531

# ---------- 0. move the wordmark inside Play's centre-80% safe area ----------
# Gemini set "TETROFALL" at x55-582; at 1024x500 that starts at x29, outside the
# 10% margin Play crops in some placements. Lift it, clone wood over the hole,
# and set it down at x166 scaled to 0.86.
WM=(20,262,614,456)
_b=np.asarray(B).astype(np.float32)
_l=_b[...,0]*0.35+_b[...,1]*0.45+_b[...,2]*0.20
_sub=_l[WM[1]:WM[3], WM[0]:WM[2]]
_m=np.clip((_sub-86)/54.0,0,1)
_mi=Image.fromarray((_m*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.1))
word=B.crop(WM).convert('RGBA'); word.putalpha(_mi)
word=Image.merge('RGBA',(*ImageEnhance.Brightness(word.convert('RGB')).enhance(1.12).split(),
                         word.getchannel('A')))

ww,wh=WM[2]-WM[0], WM[3]-WM[1]
# Rebuild the plate behind the mark. The grain here runs almost horizontally, so
# a clean vertical strip stretched sideways keeps every grain line continuous;
# a low-frequency ratio map then puts the vignette falloff back.
_bl=lambda im,r: im.filter(ImageFilter.GaussianBlur(r))
src=B.crop((590, WM[1], 608, WM[3])).resize((ww,wh), Image.BICUBIC)
_top=np.asarray(_bl(B.crop((WM[0],196,WM[2],226)),6).resize((ww,wh),Image.BICUBIC)).astype(np.float32)
_bot=np.asarray(_bl(B.crop((WM[0],470,WM[2],500)),6).resize((ww,wh),Image.BICUBIC)).astype(np.float32)
_t=np.linspace(0,1,wh)[:,None,None]
ref=Image.fromarray(np.clip(_top*(1-_t)+_bot*_t,0,255).astype(np.uint8))
r_ref=np.asarray(_bl(ref,30)).astype(np.float32)+2.0
r_src=np.asarray(_bl(src,30)).astype(np.float32)+2.0
_p=np.asarray(src).astype(np.float32)*(r_ref/r_src)
# the sideways stretch costs the fine grain, so add it back as a high-pass
# lifted from clean plate lower down, tiled with a cross-fade so it has no seam
_dsrc=B.crop((20,466,578,556))
_d=np.asarray(_dsrc).astype(np.float32)-np.asarray(_bl(_dsrc,3)).astype(np.float32)
_d=np.concatenate([_d, _d[::-1]*0.9], axis=0)
_dh=_d.shape[0]
_fade=np.clip(np.minimum(np.arange(_dh), _dh-1-np.arange(_dh))/18.0,0,1)[:,None,None]
_d=_d*_fade
det=np.zeros((wh,ww,3),np.float32)
for y0 in range(0, wh, _dh):
    h=min(_dh, wh-y0); det[y0:y0+h]+= np.pad(_d[:h],((0,0),(0,max(0,ww-_d.shape[1])),(0,0)),mode='edge')[:, :ww]
rng=np.random.default_rng(3)
patch=Image.fromarray(np.clip(_p+det*1.25+rng.normal(0,0.9,_p.shape),0,255).astype(np.uint8))
edge=Image.new('L',(ww,wh),0)
ImageDraw.Draw(edge).rectangle([20,20,ww-21,wh-21],fill=255)
edge=edge.filter(ImageFilter.GaussianBlur(14))
base.paste(patch.convert('RGBA'), (WM[0],WM[1]), edge)

_sc=0.86
word=word.resize((int(ww*_sc), int(wh*_sc)), Image.LANCZOS)
_wx,_wy=166-int(35*_sc), 306-int(63*_sc)
# warm halo so the mark still lifts off the grain after the move
_halo=Image.new('L',(Wd,Ht),0)
_halo.paste(word.getchannel('A').point(lambda v:int(v*0.72)), (_wx,_wy))
_halo=_halo.filter(ImageFilter.GaussianBlur(26))
base=Image.alpha_composite(base, Image.merge('RGBA',
    (*Image.new('RGB',(Wd,Ht),(255,198,116)).split(), _halo.point(lambda v:int(v*0.78)))))
base.alpha_composite(word, (_wx,_wy))

# ---------- 1. hot seam: additive warm streak along the cleared row ----------
glow=Image.new('L',(Wd,Ht),0)
d=ImageDraw.Draw(glow)
for x in range(596,1366):
    t=(x-600)/762.0
    # brightest in the left-of-centre burst zone, falls off to the right
    inten=255*(0.52+0.48*math.exp(-((t-0.34)**2)/0.14))
    d.line([(x,SEAM-3),(x,SEAM+4)],fill=int(inten))
glow=glow.filter(ImageFilter.GaussianBlur(9))
wide=glow.filter(ImageFilter.GaussianBlur(34))
glow=ImageChops.screen(glow, wide.point(lambda v:int(v*0.75)))
warm=Image.new('RGB',(Wd,Ht),(255,196,110))
base=Image.alpha_composite(base, Image.merge('RGBA',(*warm.split(), glow.point(lambda v:min(255,int(v*1.0))))))

# ---------- 2. epicentre blooms ----------
bloom=Image.new('L',(Wd,Ht),0)
bd=ImageDraw.Draw(bloom)
for cx,r,a in [(760,150,235),(1010,120,200),(1230,95,150)]:
    bd.ellipse([cx-r,SEAM-r*0.55,cx+r,SEAM+r*0.55],fill=a)
bloom=bloom.filter(ImageFilter.GaussianBlur(48))
hot=Image.new('RGB',(Wd,Ht),(255,208,132))
base=Image.alpha_composite(base, Image.merge('RGBA',(*hot.split(), bloom.point(lambda v:int(v*0.55)))))

# ---------- 3. shard burst ----------
TONE=(0.93,0.89,0.84)
def place(layer, sh, cx, cy, scale, rot, alpha=255, blur=0.0, shadow=0):
    s=sh.resize((max(2,int(sh.width*scale)), max(2,int(sh.height*scale))), Image.LANCZOS)
    s=s.rotate(rot, resample=Image.BICUBIC, expand=True)
    if blur:
        s.putalpha(s.getchannel('A').filter(ImageFilter.GaussianBlur(blur)))
    if alpha<255:
        a=s.getchannel('A').point(lambda v:int(v*alpha/255)); s.putalpha(a)
    r,g,bl_,al_=s.split()
    s=Image.merge('RGBA',(r.point(lambda v:int(v*TONE[0])), g.point(lambda v:int(v*TONE[1])),
                          bl_.point(lambda v:int(v*TONE[2])), al_))
    if shadow:
        sh_l=al_.point(lambda v:int(v*shadow)).filter(ImageFilter.GaussianBlur(5))
        sl=Image.merge('RGBA',(*Image.new('RGB',s.size,(28,17,9)).split(), sh_l))
        layer.alpha_composite(sl,(int(cx-s.width/2)+4, int(cy-s.height/2)+6))
    layer.alpha_composite(s,(int(cx-s.width/2), int(cy-s.height/2)))

burst=Image.new('RGBA',(Wd,Ht),(0,0,0,0))
plan=[]
def epi(x):
    return max(math.exp(-((x-760)**2)/(2*215**2)),
               0.92*math.exp(-((x-1060)**2)/(2*205**2)),
               0.80*math.exp(-((x-1300)**2)/(2*175**2)))
# dense eruption hugging the cleared row
for i in range(44):
    x=600+random.random()*830
    e=epi(x)
    if random.random()>0.25+0.75*e: continue
    up=(random.random()**2.1)*135*(0.5+0.7*e)
    y=SEAM-up+random.uniform(-8,10)
    sc=(0.62+random.random()*0.62)*(0.9+0.3*e)
    plan.append((random.randrange(len(shards)), x, y, sc, random.uniform(0,360),
                 int(215+40*random.random()), 0.0, 0))
# a thin high arc, small and few
for i in range(9):
    x=630+random.random()*790
    e=epi(x)
    if random.random()>0.35+0.65*e: continue
    y=SEAM-(120+random.random()*95)
    plan.append((random.randrange(len(shards)), x, y, 0.40+random.random()*0.30,
                 random.uniform(0,360), 165, 0.7, 0))
# chips settling on the rows just below the break
for i in range(9):
    x=610+random.random()*800
    plan.append((random.randrange(len(shards)), x, SEAM+random.uniform(8,70),
                 0.55+random.random()*0.45, random.uniform(0,360), 205, 0.0, 150))
# near-camera chips on the front rows, for depth
for cx,cy,sc in [(745,672,1.5),(1155,646,1.35),(960,706,1.65)]:
    plan.append((random.randrange(len(shards)), cx, cy, sc, random.uniform(0,360), 185, 1.6, 120))
for idx,x,y,sc,rot,al,bl,shd in plan:
    place(burst, shards[idx], x, y, sc, rot, al, bl, shd)

# dust haze lifting off the break
haze=Image.new('L',(Wd,Ht),0)
hd=ImageDraw.Draw(haze)
for i in range(150):
    x=random.uniform(600,1400); e=epi(x)
    if random.random()>0.2+0.8*e: continue
    y=SEAM-abs(random.gauss(0,42))
    r=random.uniform(8,30)
    hd.ellipse([x-r,y-r*0.6,x+r,y+r*0.6],fill=int(14+22*e))
haze=haze.filter(ImageFilter.GaussianBlur(34))
base=Image.alpha_composite(base, Image.merge('RGBA',(*Image.new('RGB',(Wd,Ht),(255,214,158)).split(), haze)))
base=Image.alpha_composite(base, burst)

# ---------- 4. warm rim light on the shards + gentle bloom over everything ----------
rgb=base.convert('RGB')
b=np.asarray(rgb).astype(np.float32)
lum=b[...,0]*0.35+b[...,1]*0.45+b[...,2]*0.20
hi=np.clip((lum-172)/70.0,0,1)
hi_img=Image.fromarray((hi*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(16))
bloom2=Image.merge('RGBA',(*Image.new('RGB',(Wd,Ht),(255,206,140)).split(), hi_img.point(lambda v:int(v*0.30))))
rgb=Image.alpha_composite(rgb.convert('RGBA'), bloom2).convert('RGB')

# ---------- 5. grade: a touch more contrast + corner vignette ----------
rgb=ImageEnhance.Contrast(rgb).enhance(1.07)
rgb=ImageEnhance.Color(rgb).enhance(1.06)
vig=Image.new('L',(Wd,Ht),0)
ImageDraw.Draw(vig).ellipse([-Wd*0.30,-Ht*0.42,Wd*1.30,Ht*1.42],fill=255)
vig=vig.filter(ImageFilter.GaussianBlur(150))
dark=Image.new('RGB',(Wd,Ht),(12,8,5))
rgb=Image.composite(rgb, Image.blend(rgb,dark,0.42), vig)

OUT=SRC
rgb.save(OUT+'04_wood_shatter_master.png')
# Play wants exactly 1024x500 (2.048); trim the dead left edge rather than squash
target=2.048
cw=int(round(Ht*target))
rgb.crop((Wd-cw,0,Wd,Ht)).resize((1024,500), Image.LANCZOS).save(OUT+'04_wood_shatter.png')
print('done')
