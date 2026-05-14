import numpy as np

fs = 125e6
M = 7
scale = 2048.0
coeffs = {1:1304/scale, 3:435/scale, 5:261/scale, 7:186/scale}

# 15-tap Type-III Hilbert FIR coefficients
h = np.zeros(15)
for k, c in coeffs.items():
    h[M-k] = +c
    h[M+k] = -c

""" def H_of_f(f_hz):
    w = 2*np.pi*f_hz/fs
    n = np.arange(len(h))
    H = np.sum(h * np.exp(-1j*w*n))   # complex response
    return H """

freqs = np.array([1.5e6, 5e6, 10e6, 25e6, 40e6])
n = np.arange(len(h))
w = 2*np.pi*freqs/fs                    # shape (F,)
E = np.exp(-1j * w[:, None] * n[None, :])  # shape (F, N)
H = E @ h                                # complex vector, shape (F,)
mag = np.abs(H)                          # vector of |H|

for f, m in zip(freqs, mag):
    print(f"{f/1e6:5.1f} MHz  |H|={m:.6f}")

"""     For each test frequency (f):

Build the 15-tap impulse response (h[n]) from your quantized coefficients (scaled by (2048)):
[
c_1=\frac{1304}{2048},\quad
c_3=\frac{435}{2048},\quad
c_5=\frac{261}{2048},\quad
c_7=\frac{186}{2048}
]
with odd symmetry around center tap (M=7).

Evaluate the DTFT at (\omega = 2\pi f/f_s):
[
H(f)=\sum_{n=0}^{14} h[n]e^{-j\omega n}
]

Take magnitude:
[
|H(f)|=\sqrt{\Re(H)^2+\Im(H)^2}
]
which is exactly what numpy abs on the complex (H) returns.

Important detail:

The (e^{+j\omega M}) factor I used was only to remove linear delay for phase reporting.
It does not change magnitude, since (|e^{j\omega M}|=1). So (|H|) is from the raw FIR response itself. """