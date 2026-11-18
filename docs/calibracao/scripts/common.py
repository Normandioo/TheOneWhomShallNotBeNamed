import numpy as np
from PIL import Image
from matplotlib import colormaps
D = None
def load(name):
    return np.array(Image.open(f"{D}/{name}"))[..., :3].astype(np.int32)
def lut(cmap, n=1024):
    return (colormaps[cmap](np.linspace(0, 1, n))[:, :3] * 255).astype(np.float32)
def invert(rgb, cmap, n=1024):
    """rgb (...,3) -> (t in 0..1, distance) via nearest LUT entry, computed on unique colors."""
    L = lut(cmap, n); flat = rgb.reshape(-1, 3)
    u, inv = np.unique(flat, axis=0, return_inverse=True)
    d = ((u[:, None, :].astype(np.float32) - L[None]) ** 2).sum(-1)
    i = d.argmin(1); dist = np.sqrt(d[np.arange(len(u)), i])
    return (i / (n - 1))[inv.ravel()].reshape(rgb.shape[:-1]), dist[inv.ravel()].reshape(rgb.shape[:-1])
