#!/usr/bin/env python3
"""Rebuild the corner GLBs from Wall.glb. Requires numpy, scipy and pygltflib.

All dimensions are metres. The source's stone triangles are reused, rather than
approximating the masonry with a texture. Run from the repository root.
"""
import math
from collections import defaultdict
from pathlib import Path
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import ConvexHull
from pygltflib import (GLTF2, Scene, Node, Mesh, Primitive, Attributes, Buffer,
                       BufferView, Accessor)

SOURCE = Path('Models/Wall.glb')
G = GLTF2().load(str(SOURCE))
B = G.binary_blob()

def accessor(idx):
    a = G.accessors[idx]; v = G.bufferViews[a.bufferView]
    dtype = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}[a.componentType]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a.type]
    stride = v.byteStride or n * np.dtype(dtype).itemsize
    return np.ndarray((a.count, n), dtype=dtype, buffer=B,
                      offset=(v.byteOffset or 0) + (a.byteOffset or 0),
                      strides=(stride, np.dtype(dtype).itemsize)).copy()

def area2(p):
    return sum(p[i][0]*p[(i+1)%len(p)][1]-p[(i+1)%len(p)][0]*p[i][1] for i in range(len(p)))

def det(a,b): return a[0]*b[1]-a[1]*b[0]

def triangulate(poly):
    # Ear clipping, also supports the concave outline of the sharp post.
    p = np.array(poly); order = list(range(len(p)))
    if area2(p) < 0: order.reverse()
    out = []
    while len(order) > 3:
        for j in range(len(order)):
            a,b,c = order[j-1], order[j], order[(j+1)%len(order)]
            cross = det(p[b]-p[a],p[c]-p[b])
            if cross <= 1e-10: continue
            def inside(q):
                return all(det(p[v]-p[u], q-p[u]) >= -1e-10 for u,v in [(a,b),(b,c),(c,a)])
            if any(inside(p[k]) for k in order if k not in (a,b,c)): continue
            out.append((a,b,c)); order.pop(j); break
        else: raise ValueError('Invalid polygon: '+str(poly))
    out.append(tuple(order)); return out

class Builder:
    def __init__(self): self.tris = defaultdict(list)
    def tri(self, mat, a,b,c):
        a,b,c = map(lambda v: np.asarray(v,dtype=float), (a,b,c))
        if np.linalg.norm(np.cross(b-a,c-a)) > 2e-7: self.tris[mat].append([a,b,c])
    def quad(self, mat, a,b,c,d):
        self.tri(mat,a,b,c); self.tri(mat,a,c,d)
    def sweep(self, mat, profile, steps, mapping):
        # profile(t) supplies a counter-clockwise y,z polygon.
        profiles = [profile(t) for t in steps]
        if area2(profiles[0]) < 0: profiles = [list(reversed(p)) for p in profiles]
        rings = [[mapping(t,y,z) for y,z in p] for t,p in zip(steps,profiles)]
        for k in range(len(rings)-1):
            r,s = rings[k],rings[k+1]
            for i in range(len(r)):
                j=(i+1)%len(r)
                self.quad(mat,r[i],s[j],s[i],r[j])
        for a,b,c in triangulate(profiles[0]): self.tri(mat,rings[0][c],rings[0][b],rings[0][a])
        for a,b,c in triangulate(profiles[-1]): self.tri(mat,rings[-1][a],rings[-1][b],rings[-1][c])
    def vertical(self, mat, levels, polys):
        # Polygons in x,z are counter-clockwise; their normal is -Y.
        if area2(polys[0]) < 0: polys = [list(reversed(p)) for p in polys]
        rings = [[(x,y,z) for x,z in p] for y,p in zip(levels,polys)]
        for k in range(len(rings)-1):
            r,s=rings[k],rings[k+1]
            for i in range(len(r)):
                j=(i+1)%len(r); self.quad(mat,r[i],s[i],s[j],r[j])
        for a,b,c in triangulate(polys[0]): self.tri(mat,rings[0][a],rings[0][b],rings[0][c])
        for a,b,c in triangulate(polys[-1]): self.tri(mat,rings[-1][c],rings[-1][b],rings[-1][a])
    def save(self, path, name):
        data=bytearray(); views=[]; accs=[]; prims=[]
        def add(arr, typ, component, target, bounds=False):
            while len(data)%4: data.append(0)
            start=len(data); data.extend(arr.tobytes()); views.append(BufferView(buffer=0,byteOffset=start,byteLength=arr.nbytes,target=target))
            kw={}
            if bounds: kw={'min':arr.min(axis=0).astype(float).tolist(),'max':arr.max(axis=0).astype(float).tolist()}
            accs.append(Accessor(bufferView=len(views)-1,componentType=component,count=len(arr),type=typ,**kw)); return len(accs)-1
        for mat, ts in sorted(self.tris.items()):
            t=np.asarray(ts,dtype=np.float32); n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]); n/=np.linalg.norm(n,axis=1)[:,None]
            pos=t.reshape(-1,3); normal=np.repeat(n,3,axis=0); uv=np.zeros((len(pos),2),dtype=np.float32)
            ind=np.arange(len(pos),dtype=np.uint32)
            a=add(pos,'VEC3',5126,34962,True); b=add(normal,'VEC3',5126,34962); c=add(uv,'VEC2',5126,34962); d=add(ind,'SCALAR',5125,34963)
            prims.append(Primitive(attributes=Attributes(POSITION=a,NORMAL=b,TEXCOORD_0=c),indices=d,material=mat,mode=4))
        while len(data)%4: data.append(0)
        gl=GLTF2(asset=G.asset,scene=0,scenes=[Scene(nodes=[0])],nodes=[Node(name=name,mesh=0)],meshes=[Mesh(name=name,primitives=prims)],materials=G.materials, buffers=[Buffer(byteLength=len(data))],bufferViews=views,accessors=accs)
        gl.set_binary_blob(bytes(data)); gl.save_binary(str(path)); print(path, sum(len(t) for t in self.tris.values()),'triangles')

def clip(poly, x, keep_above):
    out=[]; hits=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        ia=(a[0]>=x) if keep_above else (a[0]<=x); ib=(b[0]>=x) if keep_above else (b[0]<=x)
        if ia: out.append(a)
        if ia != ib:
            q=a+(b-a)*((x-a[0])/(b[0]-a[0])); out.append(q); hits.append(q)
    return out,hits

def components(prim):
    p=G.meshes[0].primitives[prim]; v=accessor(p.attributes.POSITION).astype(float); v[:,2]-=0.5541
    f=accessor(p.indices).reshape(-1,3); _, inv=np.unique(np.round(v,5),axis=0,return_inverse=True); t=inv[f]; count=inv.max()+1
    rows=np.hstack([t[:,0],t[:,1],t[:,2]]); cols=np.hstack([t[:,1],t[:,2],t[:,0]])
    _,lab=connected_components(coo_matrix((np.ones(len(rows)),(rows,cols)),shape=(count,count)),directed=False)
    face_lab=lab[t[:,0]]
    return [v[f[face_lab==i]] for i in np.unique(face_lab)]

STONE = {i:components(i) for i in (2,3,4,5)}
def copy_clipped(builder, mat, tris, shift, low, high, mapping, reverse=False, subdivide=False):
    cap=[[],[]]
    for tri in tris:
        poly=[v+np.array([shift,0,0]) for v in tri]
        poly,h=clip(poly,low,True); cap[0].extend(h)
        if not poly: continue
        poly,h=clip(poly,high,False); cap[1].extend(h)
        if len(poly)<3: continue
        pieces = [poly]
        if subdivide:
            # Bend narrow strips instead of long chords that cut through the
            # backing on the inside of the arc.
            pieces = []
            lo=min(q[0] for q in poly); hi=max(q[0] for q in poly)
            for k in range(math.floor(lo/.16), math.ceil(hi/.16)):
                piece,_=clip(poly,k*.16,True)
                if piece: piece,_=clip(piece,(k+1)*.16,False)
                if len(piece)>=3: pieces.append(piece)
        for piece in pieces:
            for i in range(1,len(piece)-1):
                v=[mapping(*p) for p in (piece[0],piece[i],piece[i+1])]
                if reverse: v.reverse()
                builder.tri(mat,*v)
    # Seal cut stones. A convex hull is adequate for the small cut surfaces and
    # avoids cracks where source facets are split into material primitives.
    for side,pts in enumerate(cap):
        if len(pts)<3: continue
        pts=np.unique(np.round(pts,7),axis=0)
        if len(pts)<3: continue
        try: hull=ConvexHull(pts[:,1:3])
        except Exception: continue
        pp=pts[hull.vertices]; center=pp.mean(axis=0)
        # y,z counter-clockwise points in +X.
        for i in range(len(pp)):
            v=[mapping(*q) for q in (center,pp[i],pp[(i+1)%len(pp)])]
            if (side==0) != reverse: v.reverse()
            builder.tri(mat,*v)

def const(poly): return lambda t: poly
BACK=[(0,-1),(0,-.8),(6,-.8),(6,-1)]
BASE=[(0,-.8),(0,0),(.4,-.4),(.4,-.8)]
TOP=[(5.6,-.8),(5.6,-.4),(6,0),(6,-.8)]
MORTAR=[(.2,-.75),(.2,-.5),(5.8,-.5),(5.8,-.75)]
def half(t):
    h=1/3; outer=.2*(1-t)
    return [(0,-.8),(0,outer),(3,outer-h),(6,outer),(6,-.8)]
def arc(t,y,z):
    r=6.4+z; return (r*math.sin(t),y,-6.4+r*math.cos(t))
def straight(t,y,z): return (t,y,z)
def mirror(x,y,z): return (6.4+z,y,x-6.4)
def post(h): return [(5.6,-.8),(6.4-h,-.8),(6.4-h,-.4),(6.6-h,-.2),(6.6-h,.2-h),(6.2,.2-h),(6,-h),(5.6,-h)]

def sharp():
    b=Builder()
    b.vertical(0,[0,6],[[(0,-1),(5.4,-1),(5.4,-6.4),(5.6,-6.4),(5.6,-.8),(0,-.8)]]*2)
    b.sweep(7,lambda x:half(x/.2),[0,.2],straight)
    start=len(b.tris[0]); b.sweep(0,lambda x:half(x/.2),[0,.2],lambda x,y,z: mirror(x,y,z))
    b.tris[0][start:]=[t[::-1] for t in b.tris[0][start:]]
    b.vertical(0,[0,3,6],[post(0),post(1/3),post(0)])
    for mat,profile in [(1,BASE),(1,TOP),(6,MORTAR)]:
        end = 5.6 if mat == 1 else 6.0
        b.sweep(mat,const(profile),[.2,end],straight)
        start=len(b.tris[mat]); b.sweep(mat,const(profile),[.2,end],lambda x,y,z:mirror(x,y,z))
        b.tris[mat][start:]=[t[::-1] for t in b.tris[mat][start:]]
    for mat, groups in STONE.items():
        for tris in groups:
            copy_clipped(b,mat,tris,0,.2,6,straight)
            copy_clipped(b,mat,tris,0,.2,6,mirror,True)
    b.save('Models/Wall_corner_90.glb','WallCorner90')

def smooth():
    b=Builder(); end=math.pi/2; p=.2/6.4; endwall=end-p; length=(endwall-p)*6.4
    b.sweep(0,const(BACK),np.linspace(0,end,49),arc)
    b.sweep(7,lambda t:half(t/p),[0,p/2,p],arc)
    b.sweep(0,lambda t:half((end-t)/p),[endwall,(endwall+end)/2,end],arc)
    for mat,profile in [(1,BASE),(1,TOP),(6,MORTAR)]:
        # Do not place a coplanar back face on the curved timber backing.
        profile=[(y,max(z,-.79)) for y,z in profile]
        b.sweep(mat,const(profile),np.linspace(p,endwall,45),arc)
    def bend(x,y,z): return arc(p+x/6.4,y,max(z,-.75))
    # Reuse the 6 m stone course with a half-metre overlap into end posts.
    for mat,groups in STONE.items():
        for tris in groups:
            if mat != 2 and np.ptp(tris[:,:,2]) < .05: continue
            for shift in (0,6):
                copy_clipped(b,mat,tris,shift,.2, length+.2,lambda x,y,z:bend(x-.2,y,z),subdivide=True)
    b.save('Models/Wall_corner_smooth.glb','WallCornerSmooth')

if __name__=='__main__': sharp(); smooth()
