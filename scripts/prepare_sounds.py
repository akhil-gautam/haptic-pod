#!/usr/bin/env python3
"""Turn the Freesound CC0 previews listed in scripts/sounds.tsv into the app's bundled sounds.

    python3 scripts/prepare_sounds.py <raw-dir> [id ...]

<raw-dir> holds <id>.mp3 for every row (downloaded from the preview_url column; never committed).

For each sound:
  loop[:N[:E]] Pick the steadiest N s window (default 50) with no 1 s stretch more than E dB
              (default 10) above the clip's usual level, then make it loop seamlessly: the 3 s after the window are crossfaded
              (equal power) over its first 3 s, so the end runs straight into the start.
  struck[:N]  A single strike: from its onset to the ring-out, at most N s (default 20), with a
              2 s tail fade.
An optional ffmpeg `filter` (e.g. a compressor to tame campfire pops) runs first.
Each is brought to about -24 LUFS with one static gain (a peak limiter holds true peak under
-1.5 dBTP where needed; for loops this happens before the crossfade, so the ends always match),
then Apple's AAC encoder (128 kbps, 44.1 kHz stereo) into
HapticPod/Resources/Sounds/<id>.m4a. CREDITS.md is written alongside.

Needs ffmpeg and afconvert (macOS).
"""
import csv, json, re, statistics, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "HapticPod" / "Resources" / "Sounds"
SR = 44100
XFADE = 3.0
TARGET_LUFS = -24.0
MAX_TP = -1.5
EVENT_DB = 10.0  # a 1 s chunk this far above the clip's median RMS counts as an event


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True)


def chunk_rms(src, pre=""):
    """RMS level (dB) of every 1 s chunk."""
    r = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(src), "-af",
         (pre + "," if pre else "") + f"aresample={SR},asetnsamples={SR},astats=metadata=1:reset=1,"
         "ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-",
         "-f", "null", "-"], capture_output=True, text=True, check=True)
    vals = [float(v) for v in re.findall(r"RMS_level=(-?[\d.]+|-inf)", r.stdout) if v != "-inf"]
    return vals


def pick_window(rms, length, event_db=EVENT_DB):
    """Start second of the steadiest window with no event; None if every window has one."""
    need = int(length + XFADE) + 1
    med = statistics.median(rms)
    best = None
    for s in range(0, len(rms) - need + 1):
        w = rms[s:s + need]
        if len(w) < need:
            break
        if max(w) > med + event_db:
            continue
        score = statistics.pstdev(w)
        if best is None or score < best[0]:
            best = (score, s)
    return None if best is None else best[1]


def loudness(src):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(src), "-af",
                        "loudnorm=print_format=json", "-f", "null", "-"],
                       capture_output=True, text=True, check=True)
    j = json.loads(re.findall(r"\{[^{}]*\}", r.stderr)[-1])
    return float(j["input_i"]), float(j["input_tp"])


def level_filter(src):
    """Static gain to the loudness target, plus a peak limiter when a few peaks would block it."""
    i, tp = loudness(src)
    gain = TARGET_LUFS - i
    af = f"volume={gain:.2f}dB"
    if tp + gain > MAX_TP:
        # A few sharp peaks (a drip, a pop) would otherwise hold the whole sound down: limit them.
        af += f",alimiter=limit={10 ** (MAX_TP / 20):.3f}:attack=1:release=60:level=false:latency=true"
    return af


def build_loop(src, dst, start, length, pre=""):
    """Every stateful step (filter, level, limiter) runs on the window plus a margin first; the
    crossfade comes last, so nothing can differ between the loop's end and its start."""
    L, X = length, XFADE
    M = min(start, 1)
    seg = dst.with_suffix(".seg.wav")
    run("ffmpeg", "-y", "-hide_banner", "-i", str(src), "-af",
        (pre + "," if pre else "") +
        f"aresample={SR},aformat=sample_fmts=fltp:channel_layouts=stereo,"
        f"atrim={start - M}:{start + L + X + 1},asetpts=PTS-STARTPTS",
        "-c:a", "pcm_f32le", str(seg))
    leveled = dst.with_suffix(".lev.wav")
    run("ffmpeg", "-y", "-hide_banner", "-i", str(seg), "-af", level_filter(seg),
        "-c:a", "pcm_f32le", str(leveled))
    graph = (
        f"[0:a]atrim={M}:{M + L + X},asetpts=PTS-STARTPTS,asplit=3[a][b][c];"
        f"[a]atrim={L}:{L + X},asetpts=PTS-STARTPTS,afade=t=out:d={X}:curve=qsin[tail];"
        f"[b]atrim=0:{X},asetpts=PTS-STARTPTS,afade=t=in:d={X}:curve=qsin[head];"
        f"[tail][head]amix=inputs=2:normalize=0[x];"
        f"[c]atrim={X}:{L},asetpts=PTS-STARTPTS[body];"
        f"[x][body]concat=n=2:v=0:a=1[out]"
    )
    run("ffmpeg", "-y", "-hide_banner", "-i", str(leveled), "-filter_complex", graph,
        "-map", "[out]", "-c:a", "pcm_f32le", str(dst))


def build_strike(src, dst, limit, pre=""):
    graph = ((pre + "," if pre else "") +
             f"aresample={SR},aformat=sample_fmts=fltp:channel_layouts=stereo,"
             "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,"
             f"atrim=0:{limit},asetpts=PTS-STARTPTS,areverse,"
             "silenceremove=start_periods=1:start_threshold=-60dB,areverse,"
             "afade=t=in:d=0.005")
    run("ffmpeg", "-y", "-hide_banner", "-i", str(src), "-af", graph, "-c:a", "pcm_f32le", str(dst))
    dur = float(run("ffprobe", "-v", "error", "-show_entries", "format=duration",
                    "-of", "csv=p=0", str(dst)).stdout)
    faded = dst.with_suffix(".f.wav")
    run("ffmpeg", "-y", "-hide_banner", "-i", str(dst), "-af",
        f"afade=t=out:st={max(0, dur - 2):.3f}:d=2", "-c:a", "pcm_f32le", str(faded))
    faded.replace(dst)


def finish(wav, dst, level=True):
    """Encode with Apple's AAC encoder. Strikes are leveled here; loops already were."""
    leveled = wav.with_suffix(".g.wav")
    run("ffmpeg", "-y", "-hide_banner", "-i", str(wav), "-af", level_filter(wav) if level else "anull",
        "-ar", str(SR), "-ac", "2", "-c:a", "pcm_s24le", str(leveled))
    gain, _ = loudness(leveled)
    run("afconvert", "-f", "m4af", "-d", "aac", "-b", "128000", "-q", "127", str(leveled), str(dst))
    return gain


def main():
    raw = Path(sys.argv[1])
    only = set(sys.argv[2:])
    rows = list(csv.DictReader(open(ROOT / "scripts" / "sounds.tsv"), delimiter="\t"))
    OUT.mkdir(parents=True, exist_ok=True)
    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        for row in rows:
            sid, pre = row["id"], row.get("filter") or ""
            kind, n, ev = (row["kind"].split(":") + ["", ""])[:3]
            if only and sid not in only:
                continue
            src = raw / f"{sid}.mp3"
            wav = Path(tmp) / f"{sid}.wav"
            if kind == "loop":
                length = int(n or 50)
                rms = chunk_rms(src, pre)
                start = pick_window(rms, length, float(ev or EVENT_DB))
                if start is None:
                    problems.append(f"{sid}: every {length}s window has an event; use the backup")
                    continue
                build_loop(src, wav, start, length, pre)
                note = f"window {start}s–{start + length}s"
            else:
                build_strike(src, wav, int(n or 20), pre)
                note = "strike"
            lufs = finish(wav, OUT / f"{sid}.m4a", level=(kind != "loop"))
            print(f"{sid:12s} {note:22s} {lufs:6.1f} LUFS")
    credits = ["# Sound credits", "",
               "Every recording here is public domain: Creative Commons 0 (CC0 1.0), confirmed on its",
               "Freesound page. Each was trimmed, made to loop and level-matched by",
               "`scripts/prepare_sounds.py`. Thank you to the recordists.", "",
               "| File | Freesound title | Author | Source | Licence |", "|---|---|---|---|---|"]
    for row in rows:
        url = f"https://freesound.org/people/{row['author']}/sounds/{row['freesound_id']}/"
        credits.append(f"| {row['id']}.m4a | {row['title']} | {row['author']} | {url} | CC0 1.0 |")
    credits += ["", "WHITE / PINK / BROWN NOISE, DEEP DRONE and THETA BEATS are generated in code",
                "(`HapticPod/Sounds/Generators.swift`) and have no source file.", ""]
    (OUT / "CREDITS.md").write_text("\n".join(credits))
    if problems:
        print("\n".join(problems))
        sys.exit(1)


if __name__ == "__main__":
    main()
