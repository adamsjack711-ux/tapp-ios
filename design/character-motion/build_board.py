"""Rebuild the Tapp design board with reportlab, using the saved simulator previews."""
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, Color
from reportlab.lib.utils import ImageReader
from PIL import Image

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "Board"
OUT.mkdir(exist_ok=True)
W, H = 1920, 1220
c = canvas.Canvas(str(OUT / "tapp-design-board.pdf"), pagesize=(W, H))
c.setTitle("Tapp | Character, color and the Island")
c.setAuthor("Tapp design study")
INK, SAGE, MUTED = "#243B30", "#345B44", "#6E766C"
CREAM, PAPER, SOFT = "#F6F4EC", "#FFFEFA", "#E3EBD6"

def rect(x,y,w,h,color,r=0,stroke=None):
    c.setFillColor(HexColor(color))
    c.setStrokeColor(HexColor(stroke or color))
    c.setLineWidth(1)
    c.roundRect(x,y,w,h,r,fill=1,stroke=int(bool(stroke)))

def text(x,y,s,size=16,color=INK,font="Helvetica",maxwidth=None):
    c.setFont(font,size);c.setFillColor(HexColor(color))
    if maxwidth:
        words=s.split();line="";yy=y
        for word in words:
            test=(line+" "+word).strip()
            if c.stringWidth(test,font,size)>maxwidth and line:
                c.drawString(x,yy,line);yy-=size*1.45;line=word
            else:line=test
        if line:c.drawString(x,yy,line)
        return yy-size*1.45
    c.drawString(x,y,s)
    return y-size*1.45

def image(path,x,y,w,h):
    c.drawImage(ImageReader(str(path)),x,y,width=w,height=h,preserveAspectRatio=True,anchor="c",mask="auto")

def link(x,y,label,url,size=11):
    text(x,y,label,size,SAGE)
    c.linkURL(url,(x,y-3,x+c.stringWidth(label,"Helvetica",size),y+size),relative=0)

sheet=Image.open(ROOT/"Characters.png")
side=sheet.width//3
cells=[ImageReader(sheet.crop((i*side,0,(i+1)*side,sheet.height))) for i in range(3)]
def pet(i,x,y,size,sx=1,sy=1,angle=0,alpha=1):
    c.saveState();c.translate(x+size/2,y+size/2);c.rotate(angle);c.scale(sx,sy);c.setFillAlpha(alpha)
    c.drawImage(cells[i],-size/2,-size/2,size,size,mask="auto")
    c.restoreState()

def phone(path,x,y,w,h,label):
    rect(x-6,y-6,w+12,h+12,"#20231F",30)
    c.saveState()
    p=c.beginPath();p.roundRect(x,y,w,h,25);c.clipPath(p,stroke=0,fill=0)
    image(path,x,y,w,h)
    c.restoreState()
    # The simulator's screen export excludes the hardware cutout; show the device silhouette.
    rect(x+w*.35,y+h-h*.058,w*.30,h*.025,"#050605",h*.0125)
    text(x,y-32,label,14,SAGE,"Helvetica-Bold")

rect(0,0,W,H,CREAM)
text(54,1135,"tapp",68,INK,"Helvetica-Bold")
text(236,1146,"A little personality. A place to come home.",32,INK,"Helvetica-Bold")
text(238,1114,"CHARACTER + COLOR + MOTION DIRECTION  /  20 OCT 2026",13,MUTED)
rect(54,1084,1812,1,"#D6DDCF")

# Column one: visual sources and the selected direction.
x=54
text(x,1044,"01 / Inspiration",22,INK,"Helvetica-Bold")
rect(x,816,390,200,PAPER,22)
image(ROOT/"BoardAssets/heyclicky-mark.png",x+22,922,190,66)
text(x+22,895,"A companion with personality",19,INK,"Helvetica-Bold")
text(x+22,867,"Expressive presence and tiny gestures that make a helper feel like a companion.",14,MUTED,maxwidth=340)
link(x+22,831,"heyclicky.com","https://www.heyclicky.com/")

rect(x,558,390,250,PAPER,22)
image(ROOT/"BoardAssets/performative-ui.png",x+16,666,358,126)
text(x+22,638,"A considered input surface",19,INK,"Helvetica-Bold")
text(x+22,611,"A clear composer, soft containers, and space for the conversation.",14,MUTED,maxwidth=340)
link(x+22,575,"Performative UI / Prompt","https://performative-ui.cncl.co/#/components/prompt")

rect(x,342,390,198,PAPER,22)
rect(x+116,467,158,42,"#080A08",21)
pet(1,x+240,441,42,angle=-10)
text(x+22,420,"The Island as a little home",19,INK,"Helvetica-Bold")
text(x+22,394,"Tapp's concept: emerge when needed, land gently, and tuck away when the moment is over.",14,MUTED,maxwidth=340)
link(x+22,358,"Apple / Live Activities guidance","https://developer.apple.com/design/human-interface-guidelines/live-activities")

text(x,294,"Color, without losing the character",18,INK,"Helvetica-Bold")
swatches=[("Original","#DDE7CB"),("Lavender","#B6A0EA"),("Mint","#78CBA8"),("Coral","#EF9B88"),("Sky","#84BCEB")]
for i,(name,col) in enumerate(swatches):
    px=x+i*77
    rect(px,224,58,48,col,15)
    text(px,205,name,11,MUTED)
text(x,169,"Custom picker included",15,INK,"Helvetica-Bold")
text(x,143,"Preserve the highlights, face and soft volume. Apply the hue to the character and bubble trail.",14,MUTED,maxwidth=380)

# Column two: actual app UI.
x=484
text(x,1044,"02 / In the app",22,INK,"Helvetica-Bold")
text(x,1017,"Actual simulator screens",13,MUTED)
phone(ROOT/"Previews/home.png",x+10,375,260,565,"Home / color controls")
phone(ROOT/"Previews/studio.png",x+305,375,260,565,"Animation studio")
text(x,303,"Three familiar faces",19,INK,"Helvetica-Bold")
for i,name in enumerate(["Orbit","Classic","Comet"]):
    px=x+28+i*183
    rect(px,145,150,136,SOFT if i==0 else PAPER,22)
    pet(i,px+25,181,100)
    text(px+49,163,name,13,INK,"Helvetica-Bold")
text(x,104,"Cream canvas / sage controls / soft 3D companions",14,MUTED)

# Column three: motion.
x=1108
text(x,1044,"03 / Motion with a purpose",22,INK,"Helvetica-Bold")
text(x,1009,"A small expression, then back to stillness.",17,MUTED)
motions=[("Say hello","Wiggle + stretch","1.4 s",0,-10),("Thinking","Tilt + a pause","2.4 s",1,-13),("Listening","Three soft pulses","2.7 s",1,0),("Little win","Hop + confetti","1.8 s",2,8)]
for i,(name,detail,duration,idx,angle) in enumerate(motions):
    px=x+(i%2)*375;py=801-(i//2)*156
    rect(px,py,354,139,PAPER,20)
    pet(idx,px+15,py+29,86,angle=angle)
    text(px+114,py+96,name,19,INK,"Helvetica-Bold")
    text(px+114,py+68,detail,14,MUTED)
    text(px+114,py+35,duration,12,SAGE,"Helvetica-Bold")

text(x,599,"Arrive. Squash. Bounce. Tuck.",25,INK,"Helvetica-Bold")
text(x,568,"A 1.5-second welcome at the end of the return flight.",15,MUTED)
labels=["Approach","Soft landing","Tiny bounce","Tuck inside","At home"]
times=["0.00 s","0.20 s","0.55 s","1.10 s","1.50 s"]
for i in range(5):
    px=x+i*148
    rect(px,343,132,194,PAPER,18)
    rect(px+24,486,84,24,"#070907",12)
    if i==0:pet(0,px+69,410,48,angle=-22)
    if i==1:pet(0,px+48,440,48,sx=1.18,sy=.78)
    if i==2:pet(0,px+48,451,48,sx=.96,sy=1.04)
    if i==3:pet(0,px+55,478,26,alpha=.45)
    if i in [1,2]:
        c.setStrokeColor(HexColor("#B6A0EA"));c.setLineWidth(2)
        c.roundRect(px+20,482,92,32,16,fill=0,stroke=1)
    if i==4:
        rect(px+24,486,84,24,"#070907",12)
        text(px+40,431,"Resting",12,MUTED)
    text(px+12,372,labels[i],12,INK,"Helvetica-Bold")
    text(px+12,354,times[i],11,MUTED)
text(x,315,"Storyboard / character poses are illustrative; timing follows the prototype.",11,MUTED)

rect(x,119,730,158,SOFT,22)
text(x+24,242,"Peek  /  Pop out  /  Tuck in  /  Come home",20,INK,"Helvetica-Bold")
text(x+24,211,"Peek retreats after a curious glance. Pop out stays nearby. Come home",15,INK)
text(x+24,187,"adds a soft impact and a color ripple, then disappears into the Island.",15,INK)
text(x+24,151,"Quiet motion replaces travel and bounce with a brief opacity change.",13,SAGE)

rect(54,68,1812,1,"#D6DDCF")
text(54,39,"TAPP DESIGN STUDY  /  Native simulator prototype + editable source + motion recordings",12,MUTED)
text(1110,39,"Dynamic Island behavior is a simulator concept; physical-device integration is not validated.",11,MUTED)
c.showPage();c.save()
print(OUT/"tapp-design-board.pdf")
