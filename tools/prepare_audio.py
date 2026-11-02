#!/usr/bin/env python3
"""Prepara os sons do jogo a partir dos pacotes CC0 baixados do OpenGameArt.

Uso:
    python3 tools/prepare_audio.py <pasta_dos_pacotes_extraidos> <pasta_dos_downloads_soltos>

A pasta de pacotes contém cada .zip/.7z extraído numa subpasta com o nome do
arquivo (ex.: Fantozzi-footsteps/, RPGsounds_Kenney/). A pasta de downloads
contém os arquivos de áudio soltos (Forest_Ambience.mp3, fire-1.ogg...).
Fontes e licenças: ASSET_LICENSES.md (seção Sons) e assets/audio/SOURCES.md.

Cada som é convertido para OGG Vorbis (efeitos em mono, ambiente em estéreo),
com volume normalizado (EBU R128) para que nenhum efeito estoure ou suma, e o
silêncio inicial é removido (o passo soa no quadro do contato do pé).
"""
import os
import subprocess
import sys

PACKS, LOOSE = sys.argv[1], sys.argv[2]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")

# destino -> (origem relativa, alvo de loudness LUFS, estéreo?)
SOUNDS = {}


def add(target, source, lufs=-18.0, stereo=False, extra=None):
    SOUNDS[target] = (source, lufs, stereo, extra)


# Passos (por superfície). L/R alternados quando o pacote os separa.
for i, (side, n) in enumerate([(s, n) for n in (1, 2, 3) for s in ("L", "R")]):
    add(f"footsteps/pedra_{i}.ogg", f"P:Fantozzi-footsteps/Fantozzi-footsteps/ogg/Fantozzi-Stone{side}{n}.ogg", -20)
for i in range(10):
    add(f"footsteps/grama_{i}.ogg", f"P:RPGsounds_Kenney/OGG/footstep0{i}.ogg", -21)
for i, n in enumerate(["02", "04", "05", "07", "08", "10"]):
    add(f"footsteps/gelo_{i}.ogg", f"P:corsica_s-walking_in_snow/Corsica_S-Walking_in_Snow/Corsica_S-Walking_on_snow_covered_gravel_and_ice_{n}.flac", -21)
# Lama: os passos de terra, mais graves e úmidos, são gerados no motor (tom).

# Camadas do passo no chão de floresta: o calcanhar abafado (passo do Kenney
# com passa-baixa: sem o estalo de sola dura) + folhas secas (trecho curto de
# farfalhar, sem graves). O jogo sorteia uma de cada a cada passo.
for i in range(10):
    add(f"footsteps/calcanhar_{i}.ogg", f"P:RPGsounds_Kenney/OGG/footstep0{i}.ogg", -21,
        extra="lowpass=f=1800,highpass=f=60")
for i, n in enumerate(range(1, 21)):
    start = 0.05 + (i % 3) * 0.12
    add(f"footsteps/folhas_{i}.ogg", f"P:qubodup-rustle/rustle/rustle{n:02d}.flac", -23,
        extra=f"atrim=start={start}:duration=0.38,asetpts=PTS-STARTPTS,highpass=f=350,afade=t=out:st=0.22:d=0.16")

# Corpo
for i, n in enumerate([1, 2, 3]):
    add(f"body/aterrissagem_{i}.ogg", f"L:Jump {n}.wav", -17)
for i, n in enumerate(["01", "02", "03", "04", "05", "06"]):
    add(f"body/queda_corpo_{i}.ogg", f"P:sfx_breaking_and_falling/bfh1_falling_{n}.ogg", -18)
for i in range(1, 5):
    add(f"body/roupa_{i - 1}.ogg", f"P:RPGsounds_Kenney/OGG/cloth{i}.ogg", -24)

# Voz (esforço, dor, morte)
for i, n in enumerate(["01", "03", "05"]):
    add(f"voice/esforco_{i}.ogg", f"P:slightscreams/slightscream-{n}.flac", -20)
for i, n in enumerate(["02", "04", "06", "08", "10", "12"]):
    add(f"voice/dor_{i}.ogg", f"P:slightscreams/slightscream-{n}.flac", -18)
for i, n in enumerate(["13", "14", "15"]):
    add(f"voice/morte_{i}.ogg", f"P:slightscreams/slightscream-{n}.flac", -17)

# Combate
for i, n in enumerate([1, 3, 5, 7, 9, 11]):
    add(f"combat/golpe_ar_{i}.ogg", f"P:swishes/swishes/swish-{n}.wav", -20)
for i, n in enumerate(["01", "04", "07", "10", "13", "16"]):
    add(f"combat/soco_corpo_{i}.ogg", f"P:independent_nu_ljudbank-hits_and_punches/hits/hit{n}.mp3.flac", -16)
for i, n in enumerate(["01", "02", "03"]):
    add(f"combat/impacto_madeira_{i}.ogg", f"P:sfx_breaking_and_falling/bfh1_wood_hit_{n}.ogg", -17)
for i, n in enumerate(["01", "02", "04", "05"]):
    add(f"combat/impacto_metal_{i}.ogg", f"P:sfx_breaking_and_falling/bfh1_metal_hit_{n}.ogg", -18)
for i, n in enumerate(["01", "03", "05", "07"]):
    add(f"combat/impacto_generico_{i}.ogg", f"P:sfx_breaking_and_falling/bfh1_hit_{n}.ogg", -18)
add("combat/parede.ogg", "L:thud2.wav", -16)
add("combat/defesa_0.ogg", "P:sfx_breaking_and_falling/bfh1_hit_09.ogg", -17)
add("combat/defesa_1.ogg", "P:sfx_breaking_and_falling/bfh1_hit_11.ogg", -17)

# Objetos físicos (quedas e batidas)
for i, n in enumerate(["01", "02"]):
    add(f"props/madeira_cai_{i}.ogg", f"P:sfx_breaking_and_falling/bfh1_wood_falling_{n}.ogg", -18)
for i, n in enumerate(["01", "02", "03"]):
    add(f"props/metal_cai_{i}.ogg", f"P:sfx_breaking_and_falling/bfh1_metal_falling_{n}.ogg", -19)
for i, n in enumerate(["clink1_0", "clink2", "clink3"]):
    add(f"props/metal_tilinta_{i}.ogg", f"L:{n}.wav", -21)
add("props/metal_oco.ogg", "L:bong1.wav", -20)

# Interação
add("interact/interruptor.ogg", "P:RPGsounds_Kenney/OGG/metalLatch.ogg", -18)
add("interact/clique.ogg", "P:RPGsounds_Kenney/OGG/metalClick.ogg", -20)
add("interact/couro.ogg", "P:RPGsounds_Kenney/OGG/handleSmallLeather.ogg", -20)
add("interact/porta_abre.ogg", "P:RPGsounds_Kenney/OGG/doorOpen_1.ogg", -19)

# Respiração cansada depois de correr, separada em respirações avulsas: o
# jogo toca uma de cada vez, com o intervalo pelo esforço (o arquivo tem 3
# respirações em 3,2 s; em laço seria ofegante demais, ~57 por minuto).
for i, (start, end) in enumerate([(0.0, 1.05), (1.05, 2.2), (2.2, 3.17)]):
    add(f"voice/respiracao_{i}.ogg", "L:breathing tired.wav", -24,
        extra=f"atrim=start={start}:end={end},asetpts=PTS-STARTPTS,afade=t=in:d=0.06,afade=t=out:st={end - start - 0.12:.2f}:d=0.12")

# Mundo
add("world/fogueira.ogg", "L:fire-1.ogg", -20)
# Sem trilha nem passarinhos: o único ambiente é o vento (gerado abaixo),
# com a intensidade controlada pelo sistema de vento do jogo.


def wind(dst, seconds=64):
    """Vento na copa, gerado: ruído (marrom + rosa) largo e constante. A
    intensidade, as rajadas e o "abafado" do vento fraco vêm do jogo (volume,
    tom e filtro passa-baixa do barramento Vento), não do arquivo."""
    graph = (f"anoisesrc=color=brown:duration={seconds}:sample_rate=44100:amplitude=0.55[a];"
             f"anoisesrc=color=pink:duration={seconds}:sample_rate=44100:amplitude=0.18:seed=7[b];"
             f"[a][b]amix=inputs=2,highpass=f=70,lowpass=f=5000,"
             f"aecho=0.6:0.5:60|110:0.25|0.15,loudnorm=I=-22:TP=-3")
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", graph, "-ac", "2",
           "-c:a", "libvorbis", "-q:a", "3", dst]
    subprocess.run(cmd, check=True)


def convert(target, source, lufs, stereo, extra=None):
    kind, rel = source.split(":", 1)
    src = os.path.join(PACKS if kind == "P" else LOOSE, rel)
    dst = os.path.join(OUT, target)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    filters = [f"loudnorm=I={lufs}:TP=-2:LRA=11"]
    if extra:
        filters.insert(0, extra)
    if not target.startswith("ambience/") and not target.startswith("world/"):
        # Corta o silêncio do começo (o som nasce no quadro do evento).
        filters.insert(0, "silenceremove=start_periods=1:start_threshold=-50dB")
    cmd = ["ffmpeg", "-v", "error", "-y", "-i", src, "-af", ",".join(filters),
           "-ar", "44100", "-ac", "2" if stereo else "1", "-c:a", "libvorbis", "-q:a", "4", dst]
    subprocess.run(cmd, check=True)


if __name__ == "__main__":
    for target, (source, lufs, stereo, extra) in SOUNDS.items():
        convert(target, source, lufs, stereo, extra)
    wind(os.path.join(OUT, "ambience", "vento.ogg"))
    print(f"{len(SOUNDS) + 1} sons gerados em {os.path.normpath(OUT)}")
