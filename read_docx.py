# 临时脚本：提取 docx 全文（只读，不修改原文档）
import zipfile
from xml.etree import ElementTree as ET

SRC = r"C:\Users\Administrator\WorkBuddy\2026-10-08-10-42-53\output\3f9c6713-67a4-4243-bfad-5d949e281178\stage3\科学化英语应试学习App功能系统说明书.docx"
OUT = r"C:\Users\Administrator\english_agent\doc_text.txt"

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
z = zipfile.ZipFile(SRC)
root = ET.fromstring(z.read("word/document.xml").decode("utf-8"))

lines = []
for p in root.iter(W + "p"):
    texts = [(t.text or "") for t in p.iter(W + "t")]
    line = "".join(texts).strip()
    if line:
        # 简单判断标题层级
        ppr = p.find(W + "pPr")
        style = ""
        if ppr is not None:
            ps = ppr.find(W + "pStyle")
            if ps is not None:
                style = ps.get(W + "val") or ""
        prefix = ""
        if style.lower().startswith("heading") or style.isdigit():
            prefix = "# " if style.lower() in ("heading1", "1") else "## "
        lines.append(prefix + line)

with open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print("lines:", len(lines))
