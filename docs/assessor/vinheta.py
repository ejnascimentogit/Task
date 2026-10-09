import math, wave, struct
SR = 44100
DUR = 4.2
N = int(SR * DUR)
buf = [0.0] * N

def env_ad(t, a, d):
    if t < 0: return 0.0
    if t < a: return t / a
    return math.exp(-(t - a) / d)

def add_tone(start, length, freq_fn, amp, a=0.005, d=0.3, harm=((1, 1.0),)):
    s0 = int(start * SR); n = int(length * SR); ph = [0.0] * len(harm)
    for i in range(n):
        idx = s0 + i
        if idx >= N: break
        t = i / SR
        f = freq_fn(t)
        e = env_ad(t, a, d)
        v = 0.0
        for k, (mult, w) in enumerate(harm):
            ph[k] += 2 * math.pi * f * mult / SR
            v += w * math.sin(ph[k])
        buf[idx] += amp * e * v

# 1) grave que cresce (pad)
for f, w in ((55, 0.5), (110, 0.35), (164.8, 0.15)):
    s0 = 0; n = int(3.9 * SR); ph = 0.0
    for i in range(n):
        t = i / SR
        swell = min(1.0, t / 1.4) * (1.0 if t < 2.6 else math.exp(-(t - 2.6) / 0.6))
        ph += 2 * math.pi * f * (1 + 0.003 * math.sin(2 * math.pi * 0.5 * t)) / SR
        buf[i] += 0.22 * w * swell * math.sin(ph)

# 2) varredura eletronica subindo
add_tone(0.25, 1.25, lambda t: 180 * (1300 / 180) ** (t / 1.25), 0.16, a=0.6, d=0.25,
         harm=((1, 1.0), (2, 0.25)))

# 3) bipes digitais (arpejo)
notas = [659.25, 987.77, 1318.5, 1661.2]  # E5 B5 E6 G#6
for k, f in enumerate(notas):
    add_tone(1.45 + k * 0.14, 0.5, lambda t, f=f: f, 0.18, a=0.003, d=0.09,
             harm=((1, 1.0), (2, 0.3), (3, 0.12)))

# 4) acorde final "pronto"
for f in (329.63, 493.88, 659.25, 830.61):  # E4 B4 E5 G#5
    add_tone(2.15, 2.0, lambda t, f=f: f * (1 + 0.002 * math.sin(2 * math.pi * 5 * t)), 0.11,
             a=0.04, d=0.7, harm=((1, 1.0), (2, 0.2), (4, 0.05)))
add_tone(2.15, 1.8, lambda t: 2637.0, 0.035, a=0.02, d=0.5)  # brilho

# eco
D = int(0.13 * SR)
for i in range(D, N):
    buf[i] += 0.35 * buf[i - D]

peak = max(abs(x) for x in buf) or 1.0
fade = int(0.15 * SR)
out = wave.open('vinheta-assessor.wav', 'wb')
out.setnchannels(1); out.setsampwidth(2); out.setframerate(SR)
frames = bytearray()
for i, x in enumerate(buf):
    g = 0.9 / peak
    if i > N - fade: g *= (N - i) / fade
    frames += struct.pack('<h', int(max(-1, min(1, x * g)) * 32767))
out.writeframes(bytes(frames)); out.close()
print('ok', DUR, 's')
