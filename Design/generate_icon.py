import math, sys
G={'I':(30,[[(0,-30),(0,30)]]),
   'V':(46,[[(-20,-30),(0,30),(20,-30)]]),
   'X':(46,[[(-20,-30),(20,30)],[(20,-30),(-20,30)]])}
def numeral(s):
    w=sum(G[c][0] for c in s); x=-w/2; out=[]
    for c in s:
        cw,paths=G[c]; cx=x+cw/2
        for p in paths: out.append([(cx+a,b) for a,b in p]); 
        x+=cw
    return out
def pl(p): return "M"+" L".join(f"{a:.1f} {b:.1f}" for a,b in p)
def make(P):
    cx=cy=512; s=[]
    s.append('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">')
    s.append('<defs><filter id="sh" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.3"/></filter>'
             '<clipPath id="disc"><circle cx="512" cy="512" r="318"/></clipPath></defs>')
    s.append(f'<rect x="100" y="100" width="824" height="824" rx="185" fill="{P["bg"]}" filter="url(#sh)"/>')
    s.append(f'<circle cx="512" cy="512" r="352" fill="{P["rim"]}"/>')
    s.append(f'<circle cx="512" cy="512" r="330" fill="{P["disc"]}"/>')
    s.append(f'<circle cx="512" cy="512" r="318" fill="none" stroke="{P["ink"]}" stroke-width="6"/>')
    # pás s číslicemi
    s.append(f'<circle cx="512" cy="512" r="222" fill="none" stroke="{P["ink"]}" stroke-width="6"/>')
    for i in range(12):
        a=math.radians(i*30); major=i%3==0
        r1=222; r2=318
        s.append(f'<line x1="{cx+r1*math.sin(a):.1f}" y1="{cy-r1*math.cos(a):.1f}" x2="{cx+r2*math.sin(a):.1f}" y2="{cy-r2*math.cos(a):.1f}" stroke="{P["ink"]}" stroke-width="{12 if major else 7}" opacity="{1 if major else 0.7}"/>')
    for i,t in [(0,'XII'),(3,'III'),(6,'VI'),(9,'IX')]:
        r=270
        x=cx+r*math.sin(math.radians(i*30)); y=cy-r*math.cos(math.radians(i*30))
        d=" ".join(pl(p) for p in numeral(t))
        s.append(f'<rect x="{x-62:.1f}" y="{y-44:.1f}" width="124" height="88" fill="{P["disc"]}"/>')
        s.append(f'<path d="{d}" transform="translate({x:.1f} {y:.1f}) scale(0.9)" fill="none" stroke="{P["ink"]}" stroke-width="15" stroke-linecap="square" stroke-linejoin="miter"/>')
    # stín
    ang=math.radians(118)
    dx,dy=math.sin(ang),-math.cos(ang); nx,ny=-dy,dx
    L=400; w0=34
    p=[(cx+nx*w0,cy+ny*w0),(cx-nx*w0,cy-ny*w0),(cx+dx*L,cy+dy*L)]
    s.append(f'<g clip-path="url(#disc)"><path d="M{p[0][0]:.1f} {p[0][1]:.1f} L{p[1][0]:.1f} {p[1][1]:.1f} L{p[2][0]:.1f} {p[2][1]:.1f}Z" fill="{P["shadow"]}" opacity="0.65"/></g>')
    # gnómon – kamenná deska s osvětlenou hranou
    ox,oy=-dx,-dy
    g=[(cx+nx*34,cy+ny*34),(cx-nx*34,cy-ny*34),(cx-nx*30+ox*95,cy-ny*30+oy*95),(cx+nx*30+ox*95,cy+ny*30+oy*95)]
    s.append("<path d='M"+" L".join(f"{a:.1f} {b:.1f}" for a,b in g)+f"Z' fill='{P['gnomon']}'/>")
    s.append('</svg>'); return "\n".join(s)
V={
 'a-kamen':dict(bg='#cbbd9d',rim='#9c8d6c',disc='#e6dcc3',ink='#5a4d37',shadow='#2f281c',gnomon='#3b3224'),
 'b-mramor':dict(bg='#17181b',rim='#b8924a',disc='#25272c',ink='#d1ab62',shadow='#000000',gnomon='#d1ab62'),
 'c-terakota':dict(bg='#a64e32',rim='#6e2f1d',disc='#ecdcbf',ink='#3b2a20',shadow='#2a1710',gnomon='#3b2a20'),
}
for k,P in V.items(): open(f'v/{k}.svg','w').write(make(P))
