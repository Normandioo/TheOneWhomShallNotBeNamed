import numpy as np, common as C
def ramp_ext(rgb, cmap="viridis"):
    """viridis t in [0,1]; colors that are viridis(0) scaled by s<1 (fade to black) -> t = s - 1 (in [-1,0))."""
    t, d = C.invert(rgb, cmap)
    v0 = C.lut(cmap)[0]; f = rgb.astype(np.float32)
    s = (f @ v0) / (v0 @ v0); res = np.linalg.norm(f - s[..., None] * v0, axis=-1)
    dark = (d >= 10) & (res < 12) & (s < 1.02)
    t = np.where(dark, np.clip(s, 0, 1) - 1, t)
    return t, (d < 10) | dark
