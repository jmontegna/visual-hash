#cython: nonecheck=True
#        ^^^ Turns on nonecheck globally

import random

from libc.stdlib cimport rand
from libc.math cimport log, sqrt, cos, sin, atan2
from cython cimport view

import numpy as np
cimport numpy as np
# We now need to fix a datatype for our arrays. I've used the variable
# DTYPE for this, which is assigned to the usual NumPy runtime
# type info object.
DTYPE = np.double
# "ctypedef" assigns a corresponding compile-time type to DTYPE_t. For
# every type in the numpy module there's a corresponding compile-time
# type with a _t-suffix.
ctypedef np.double_t DTYPE_t

cdef struct Point:
    double x, y, R, G, B, A

def MakePoint(x, y):
    cdef Point p = Point(x, y, 0,0,0,0)
    return p

cdef struct ColorTransform:
    double R, G, B, A

cdef ColorTransform MakeColorTransform():
    cdef ColorTransform out
    out.A = 1
    out.R = random.uniform(0,1)
    out.G = random.uniform(0,1)
    out.B = random.uniform(0,1)
    cdef double m = out.R
    if out.G > m:
        m = out.G
    if out.B > m:
        m = out.B
    out.R /= m
    out.G /= m
    out.B /= m
    return out

cdef Point colorTransform(ColorTransform c, Point p):
    p.R = (c.A*c.R + p.A*p.R)/(c.A + p.A)
    p.G = (c.A*c.G + p.A*p.G)/(c.A + p.A)
    p.B = (c.A*c.B + p.A*p.B)/(c.A + p.A)
    p.A = (c.A+p.A)/2
    return p

cdef struct Affine:
    ColorTransform c
    double compressme, theta
    double Mxx, Mxy, Myx, Myy, Ox, Oy

cdef Affine MakeAffine():
    cdef Affine a
    a.c = MakeColorTransform()
    # currently we always initialize pseudorandomly, but
    # eventually we'll want to generate this deterministically.
    a.theta = random.uniform(0, 2*np.pi)
    rot = np.matrix([[cos(a.theta), sin(a.theta)],
                     [-sin(a.theta),cos(a.theta)]])
    a.compressme = random.gauss(0.8, 0.2)
    compress = np.matrix([[a.compressme, 0],
                          [0, a.compressme]])
    mat = compress*rot
    a.Mxx = mat[0,0]
    a.Mxy = mat[0,1]
    a.Myx = mat[1,0]
    a.Myy = mat[1,1]
    cdef double translation_scale = 0.8
    a.Ox = random.gauss(0, translation_scale)
    a.Oy = random.gauss(0, translation_scale)
    return a

cdef Point affineTransform(Affine a, Point p):
    cdef Point out = colorTransform(a.c, p)
    p.x -= a.Ox
    p.y -= a.Oy
    out.x = p.x*a.Mxx + p.y*a.Mxy # + a.Ox
    out.y = p.x*a.Myx + p.y*a.Myy # + a.Oy
    #p.x += a.Ox
    #p.y += a.Oy
    return out

cdef struct Fancy:
    Affine a
    double spiralness, radius, bounciness
    int bumps

cdef Fancy MakeFancy():
    cdef Fancy f
    f.a = MakeAffine()
    f.spiralness = random.gauss(0, 3)
    f.radius = random.gauss(sqrt(2)/2, sqrt(2)/2/2)
    f.bounciness = random.gauss(2, 2)
    f.bumps = random.randint(1, 4)
    return f

cdef Point fancyTransform(Fancy f, Point p):
    cdef Point out = affineTransform(f.a, p)
    cdef Point nex = out
    cdef double r = sqrt(out.x*out.x + out.y*out.y)
    cdef double theta = atan2(out.y, out.x)
    cdef double maxrad = f.radius*(1+f.bounciness*sin(theta*f.bumps))
    nex.x = maxrad*sin(r/maxrad)*sin(theta + f.spiralness*r)
    nex.y = maxrad*sin(r/maxrad)*cos(theta + f.spiralness*r)
    nex.x = sin(nex.x)
    nex.y = sin(nex.y)
    return nex

def fancyFilename(Fancy f):
    return 'image_%.2g_%.2g_%.2g_%d__%.2g_%.2g.png' % (f.radius, f.spiralness, f.bounciness, f.bumps, f.a.compressme, f.a.theta)

cdef struct Symmetry:
    Affine a
    int Nsym

cdef Symmetry MakeSymmetry():
    cdef Symmetry s
    s.a = MakeAffine()
    cdef double theta = random.uniform(0, 2*np.pi)
    s.a.Ox /= 3
    s.a.Oy /= 3
    cdef double nnn = random.expovariate(1.0/4)
    s.Nsym = 1 + <int>nnn
    if s.Nsym == 1 and random.randint(0,1) == 0:
        print 'Mirror plane'
        s.Nsym = 2
        theta = random.uniform(0, 2*np.pi)
        vx = sin(theta)
        vy = cos(theta)
        s.a.Mxx = vx
        s.a.Myy = -vx
        s.a.Mxy = vy
        s.a.Myx = vy
    else:
        print 'Rotation:', s.Nsym, 'from', nnn
        s.a.Mxx = cos(2*np.pi/s.Nsym)
        s.a.Myy = s.a.Mxx
        s.a.Mxy = sin(2*np.pi/s.Nsym)
        s.a.Myx = -s.a.Mxy
    print np.array([[s.a.Mxx, s.a.Mxy],
                    [s.a.Myx, s.a.Myy]])
    print 'origin', s.a.Ox, s.a.Oy
    return s

cdef Point symmetryTransform(Symmetry s, Point p):
    cdef double px = p.x
    cdef double py = p.y
    px -= s.a.Ox
    py -= s.a.Oy
    p.x = px*s.a.Mxx + py*s.a.Mxy
    p.y = px*s.a.Myx + py*s.a.Myy
    p.x += s.a.Ox
    p.y += s.a.Oy
    return p

cdef int Ntransform = 4
cdef struct CMultiple:
    Fancy t[10]
    Symmetry s
    int N
    int Ntot

cdef CMultiple MakeMultiple():
    cdef CMultiple m
    m.s = MakeSymmetry()
    m.N = Ntransform - m.s.Nsym
    if m.N < 4:
        m.N = 4
    cdef int i
    for i in range(m.N):
        m.t[i] = MakeFancy()
    m.Ntot = m.N*m.s.Nsym
    return m

cdef Point multipleTransform(CMultiple m, Point p):
    cdef int i = rand() % m.Ntot
    if i < m.N:
        return fancyTransform(m.t[i], p)
    return symmetryTransform(m.s, p)

cdef class Multiple:
    cdef CMultiple m
    def __cinit__(self):
        self.m = MakeMultiple()
    cpdef Point transform(self, Point p):
        return multipleTransform(self.m, p)
    def TakeApart(self):
        transforms = [('image.png', self)]
        for i in range(self.m.N):
            foo = Multiple()
            foo.m.N = 1
            foo.m.Ntot = 1
            foo.m.t[0] = self.m.t[i]
            transforms.append((fancyFilename(foo.m.t[0]), foo))
        return transforms

cdef place_point(np.ndarray[DTYPE_t, ndim=3] h, Point p):
    cdef int ix = <int>((p.x+1)/2*h.shape[1])
    cdef int iy = <int>((p.y+1)/2*h.shape[2])
    h[0, ix % h.shape[1], iy % h.shape[2]] += p.A
    h[1, ix % h.shape[1], iy % h.shape[2]] += p.R
    h[2, ix % h.shape[1], iy % h.shape[2]] += p.G
    h[3, ix % h.shape[1], iy % h.shape[2]] += p.B

cpdef np.ndarray[DTYPE_t, ndim=3] Simulate(Multiple t, Point p,
                                           int nx, int ny):
    cdef np.ndarray[DTYPE_t, ndim=3] h = np.zeros([4, nx,ny], dtype=DTYPE)
    if t.m.Ntot == 0:
        print 'weird business'
        return h
    for i in xrange(400*nx*ny):
        place_point(h, p)
        p = multipleTransform(t.m, p)
    return h

cpdef np.ndarray[DTYPE_t, ndim=3] get_colors(np.ndarray[DTYPE_t, ndim=3] h):
    cdef np.ndarray[DTYPE_t, ndim=3] img = np.zeros([3, h.shape[1], h.shape[2]], dtype=DTYPE)
    cdef DTYPE_t maxa = 0
    cdef DTYPE_t mean_nonzero_a = 0
    cdef int num_nonzero = 0
    cdef DTYPE_t mina = 1e300
    for i in xrange(h.shape[1]):
        for j in xrange(h.shape[2]):
            if h[0,i,j] > maxa:
                maxa = h[0,i,j]
            if h[0,i,j] > 0 and h[0,i,j] < mina:
                mina = h[0,i,j]
            if h[0,i,j] > 0:
                mean_nonzero_a += h[0,i,j]
                num_nonzero += 1
    mean_nonzero_a /= num_nonzero
    cdef double factor = maxa/(mean_nonzero_a*mean_nonzero_a)
    cdef double norm = 1.0/log(factor*maxa)
    cdef double a
    for i in xrange(h.shape[1]):
        for j in xrange(h.shape[2]):
            if h[0,i,j] > 0:
                a = norm*log(factor*h[0,i,j]);
                img[0,i,j] = h[1,i,j]/h[0,i,j]*a
                img[1,i,j] = h[2,i,j]/h[0,i,j]*a
                img[2,i,j] = h[3,i,j]/h[0,i,j]*a
    return img
