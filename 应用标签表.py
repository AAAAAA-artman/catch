# -*- coding: utf-8 -*-
"""
把「句子标签表.tsv」里改好的标签写回 scripts/sentence_data.gd。

用法（在 F:\\godot\\projects\\接住 目录下）：
    "C:\\Users\\16436\\.dsh\\dsh-runtimes\\dsh-primary-runtime\\dependencies\\python\\python.exe" 应用标签表.py

规则：
  · 只根据「句子」文本匹配，不看编号
  · 标签列填 好 / 坏 / 中（也接受 positive / negative / neutral）
  · 说话人 / 长度列如果改了，也会一起写回
  · 找不到的句子会列出来提示（通常是句子文字被改过）
"""
import io
import re
import sys

BASE = r"F:\godot\projects\接住"
TSV = BASE + r"\句子标签表.tsv"
GD = BASE + r"\scripts\sentence_data.gd"

# 五档标签 → (池, tier)
LABEL_TO_TIER = {
    "坏2": ("negative", 1), "坏1": ("negative", 2),
    "中": ("neutral", 3), "中性": ("neutral", 3),
    "好1": ("positive", 4), "好2": ("positive", 5),
    # 兼容旧的三档写法
    "坏": ("negative", 2), "好": ("positive", 4),
}
NAME_TO_PHASE = {
    "第一阶段": "phase1", "第二阶段": "phase2", "第三阶段": "phase3",
    "偷听": "overheard", "终章": "final",
}

# ---------------------------------------------------------------- 读表
rows = []
with io.open(TSV, encoding="utf-8-sig") as f:
    lines = [l.rstrip("\r\n") for l in f if l.strip()]
for ln in lines[1:]:
    parts = ln.split("\t")
    while len(parts) < 6:
        parts.append("")
    rows.append({
        "phase": NAME_TO_PHASE.get(parts[1].strip(), parts[1].strip()),
        "label": parts[2].strip(),
        "text": parts[3].strip(),
        "speaker": parts[4].strip(),
        "len": parts[5].strip(),
    })

# ---------------------------------------------------------------- 读 gd
src = io.open(GD, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in src else "\n"

struct = {}          # phase -> kind -> [entry]
entry_of = {}        # text -> entry（同一个对象，方便原地改）
cur_phase = cur_kind = None
for line in src.split(nl):
    m = re.match(r'\t"(\w+)": \{', line)
    if m:
        cur_phase = m.group(1)
        struct.setdefault(cur_phase, {})
        cur_kind = None
        continue
    m2 = re.match(r'\t\t"(\w+)": \[', line)
    if m2 and cur_phase:
        cur_kind = m2.group(1)
        struct[cur_phase].setdefault(cur_kind, [])
        continue
    m3 = re.search(r'\{"text": "([^"]+)", "pinyin": \[(.*?)\], "speaker": "(\w+)", "len": "(\w+)", "tier": (\d+)\}', line)
    if m3 and cur_phase and cur_kind:
        e = {"text": m3.group(1), "pinyin": m3.group(2),
             "speaker": m3.group(3), "len": m3.group(4),
             "tier": int(m3.group(5))}
        struct[cur_phase][cur_kind].append(e)
        entry_of[e["text"]] = e

# ---------------------------------------------------------------- 应用
missing = []
moved = 0
for r in rows:
    t = r["text"]
    if t not in entry_of:
        missing.append(t)
        continue
    e = entry_of[t]
    # 找它现在在哪个 phase/kind
    cur_loc = None
    for ph, kinds in struct.items():
        for kind, items in kinds.items():
            if e in items:
                cur_loc = (ph, kind)
                break
        if cur_loc:
            break
    if cur_loc is None:
        missing.append(t + " (数据异常)")
        continue
    ph, kind = cur_loc
    # 先更新 speaker / len
    if r["speaker"]:
        e["speaker"] = r["speaker"]
    if r["len"]:
        e["len"] = r["len"]
    # 标签变了：调整 tier，必要时换池
    lab = r["label"]
    if lab in LABEL_TO_TIER:
        new_kind, new_tier = LABEL_TO_TIER[lab]
    else:
        new_kind, new_tier = kind, int(e.get("tier", 3))
    changed = False
    if new_tier != int(e.get("tier", 3)):
        e["tier"] = new_tier
        changed = True
    if new_kind != kind:
        struct[ph][kind].remove(e)
        struct[ph][new_kind].append(e)
        changed = True
    if changed:
        moved += 1

print("标签调整：移动 %d 句" % moved)
if missing:
    print("找不到这些句子（请先核对文字）：")
    for t in missing:
        print("   ", t)
    sys.exit(1)

# ---------------------------------------------------------------- 回写
def fmt(e):
    return '\t\t\t{"text": "%s", "pinyin": [%s], "speaker": "%s", "len": "%s", "tier": %d},' % (
        e["text"], e["pinyin"], e["speaker"], e["len"], e["tier"])


out = ["const POOLS := {"]
for ph in ["phase1", "phase2", "phase3", "overheard", "final"]:
    if ph not in struct:
        continue
    out.append('\t"%s": {' % ph)
    for kind in ["neutral", "positive", "negative"]:
        out.append('\t\t"%s": [' % kind)
        for e in struct[ph].get(kind, []):
            out.append(fmt(e))
        out.append("\t\t],")
    out.append("\t},")
out.append("}")

start = src.index("const POOLS := {")
end = src.index(nl + "}" + nl, start) + len(nl + "}" + nl)
io.open(GD, "w", encoding="utf-8", newline="").write(src[:start] + nl.join(out) + nl + src[end:])
print("已写回 scripts/sentence_data.gd")
print("注意：语音池 voice_data.gd 若也要同步，告诉我一声，我重新生成。")
