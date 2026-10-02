#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 FocusPet/教程/ 下的 Markdown 文件合并为一份排版精美的 PDF。"""
import os, re, html, glob
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.colors import HexColor
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph,
                                Spacer, Table, TableStyle, PageBreak,
                                XPreformatted, NextPageTemplate, HRFlowable)
from reportlab.platypus.tableofcontents import TableOfContents

TUTORIAL_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_PDF = os.path.join(TUTORIAL_DIR, "FocusPet零基础开发教程.pdf")

# ---------- 字体 ----------
regular = os.environ.get("DAIMON_CJK_FONT_REGULAR")
bold = os.environ.get("DAIMON_CJK_FONT_BOLD")
if not regular or not bold:
    raise RuntimeError("Daimon managed CJK fonts unavailable")
pdfmetrics.registerFont(TTFont("CJK", regular))
pdfmetrics.registerFont(TTFont("CJK-Bold", bold))
pdfmetrics.registerFontFamily("CJK", normal="CJK", bold="CJK-Bold",
                              italic="CJK", boldItalic="CJK-Bold")

# ---------- 样式 ----------
ss = getSampleStyleSheet()
NAVY = HexColor("#1a2e4a")
BODY_C = HexColor("#333333")

body = ParagraphStyle("Body", parent=ss["Normal"], fontName="CJK",
                      fontSize=10.5, leading=17.5, textColor=BODY_C,
                      spaceAfter=6)
h1 = ParagraphStyle("ChapterTitle", parent=body, fontName="CJK-Bold",
                    fontSize=20, leading=28, textColor=NAVY,
                    spaceBefore=6, spaceAfter=10, alignment=TA_CENTER)
h2 = ParagraphStyle("H2", parent=body, fontName="CJK-Bold", fontSize=14,
                    leading=20, textColor=NAVY, spaceBefore=16, spaceAfter=8)
h3 = ParagraphStyle("H3", parent=body, fontName="CJK-Bold", fontSize=12,
                    leading=18, textColor=HexColor("#2d4a6f"),
                    spaceBefore=12, spaceAfter=6)
quote_st = ParagraphStyle("Quote", parent=body, fontSize=9.5, leading=15,
                          textColor=HexColor("#666666"), leftIndent=14,
                          spaceAfter=6, alignment=0)
bullet_st = ParagraphStyle("Bullet", parent=body, leftIndent=16,
                           bulletIndent=4, spaceAfter=4)
num_st = ParagraphStyle("NumItem", parent=body, leftIndent=20,
                        bulletIndent=2, spaceAfter=4)
code_st = ParagraphStyle("Code", parent=body, fontName="CJK", fontSize=8,
                         leading=11.5, textColor=HexColor("#24292f"),
                         spaceAfter=0, alignment=0)
cell_st = ParagraphStyle("Cell", parent=body, fontSize=9, leading=13.5,
                         spaceAfter=0, alignment=0)
cellb_st = ParagraphStyle("CellB", parent=cell_st, fontName="CJK-Bold")
toc_title = ParagraphStyle("TOCTitle", parent=h1, spaceAfter=18)
toc_lv0 = ParagraphStyle("TOC0", parent=body, fontSize=11.5, leading=24,
                         leftIndent=6)
cover_title = ParagraphStyle("CoverTitle", parent=h1, fontSize=30, leading=42)
cover_sub = ParagraphStyle("CoverSub", parent=body, fontSize=13, leading=22,
                           textColor=HexColor("#555555"), alignment=TA_CENTER)
cover_date = ParagraphStyle("CoverDate", parent=body, fontSize=11,
                            textColor=HexColor("#888888"), alignment=TA_CENTER)

PAGE_W, PAGE_H = A4
M = 2.5 * cm
DOC_W = PAGE_W - 2 * M

# ---------- 文本清洗 ----------
def strip_emoji(s):
    s = s.replace("⇧", "Shift+").replace("⌥", "Opt+").replace("⌘", "Cmd+")
    # 常见 emoji / 杂项符号 / 交通标识，管理字体不含这些字形，直接移除
    s = re.sub(r"[\U0001F000-\U0001FAFF\u2600-\u27BF\u2300-\u23FF\uFE0F\u200D]", "", s)
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"\s+([」』）》”，。！？；：、%])", r"\1", s)
    return s.strip()

def inline(s):
    s = html.escape(strip_emoji(s), quote=False)
    s = re.sub(r"`([^`]+)`",
               r'<font face="CJK" backColor="#eff1f3" color="#b33a3a">\1</font>', s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    def link(m):
        text, url = m.group(1), m.group(2)
        if url.startswith("http"):
            return f'<a href="{url}" color="#1a5fa8">{text}</a>'
        if url.startswith("!"):
            return text
        return text  # 本地 md 相对链接：只留文字
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, s)
    s = re.sub(r"!\[([^\]]*)\]\([^)]+\)", lambda m: m.group(1) or "[图片]", s)
    return s

def disp_len(s):
    return sum(2 if ord(c) > 0x2E7F else 1 for c in s)

def make_table(rows):
    parsed = []
    for r in rows:
        cells = [c.strip() for c in r.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-{2,}:?", c or "---") for c in cells):
            continue  # 分隔行
        parsed.append(cells)
    if not parsed:
        return Spacer(1, 1)
    ncol = max(len(r) for r in parsed)
    parsed = [r + [""] * (ncol - len(r)) for r in parsed]
    weights = [max(disp_len(r[c]) for r in parsed) for c in range(ncol)]
    total = sum(weights)
    widths = [max(1.4 * cm, DOC_W * w / total) for w in weights]
    scale = DOC_W / sum(widths)
    widths = [w * scale for w in widths]
    data = []
    for ri, r in enumerate(parsed):
        st = cellb_st if ri == 0 else cell_st
        data.append([Paragraph(inline(c), st) for c in r])
    t = Table(data, colWidths=widths, repeatRows=1)
    t.setStyle(TableStyle([
        ("LINEABOVE", (0, 0), (-1, 0), 1.2, HexColor("#333333")),
        ("LINEBELOW", (0, 0), (-1, 0), 0.6, HexColor("#333333")),
        ("LINEBELOW", (0, -1), (-1, -1), 1.2, HexColor("#333333")),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]))
    return t

def make_code(code_text):
    # ASCII 图表等宽行按可用宽度自动缩字号，避免溢出
    maxw = DOC_W - 20
    fs = 8.0
    lines = code_text.split("\n")
    while fs > 5.5 and any(pdfmetrics.stringWidth(l, "CJK", fs) > maxw
                           for l in lines):
        fs -= 0.25
    st = ParagraphStyle(f"Code{fs:.2f}", parent=code_st, fontSize=fs,
                        leading=fs * 1.5)
    pf = XPreformatted(html.escape(code_text, quote=False), st)
    t = Table([[pf]], colWidths=[DOC_W])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), HexColor("#f6f8fa")),
        ("LINEBEFORE", (0, 0), (0, -1), 2.2, HexColor("#c9d4e0")),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]))
    return [t, Spacer(1, 8)]

def parse_markdown(text, story, chap_idx):
    lines = text.split("\n")
    i, para = 0, []
    def flush():
        if para:
            story.append(Paragraph(inline(" ".join(para)), body))
            para.clear()
    while i < len(lines):
        line = lines[i].rstrip()
        s = line.strip()
        if s.startswith("```"):
            flush(); i += 1; code = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code.append(strip_emoji(lines[i])); i += 1
            i += 1
            story.extend(make_code("\n".join(code)))
            continue
        if line.lstrip().startswith("|"):
            flush(); rows = []
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                rows.append(lines[i]); i += 1
            story.append(make_table(rows))
            story.append(Spacer(1, 8))
            continue
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            flush()
            level, title = len(m.group(1)), m.group(2)
            if level == 1:
                key = f"chap{chap_idx}"
                p = Paragraph(f'<a name="{key}"/>' + inline(title), h1)
                p._toc_key = key
                story.append(p)
                story.append(HRFlowable(width="100%", thickness=1.2,
                                        color=NAVY, spaceAfter=14))
            elif level == 2:
                story.append(Paragraph(inline(title), h2))
            else:
                story.append(Paragraph(inline(title), h3))
            i += 1
            continue
        if line.startswith(">"):
            flush(); buf = []
            while i < len(lines) and lines[i].lstrip().startswith(">"):
                buf.append(lines[i].lstrip()[1:].strip()); i += 1
            story.append(Paragraph("<br/>".join(inline(x) for x in buf), quote_st))
            continue
        m = re.match(r"^(\s*)[-*]\s+(.*)$", line)
        if m:
            flush()
            indent = len(m.group(1))
            st = ParagraphStyle(f"bu{indent}", parent=bullet_st,
                                leftIndent=16 + indent * 8)
            story.append(Paragraph(inline(m.group(2)), st, bulletText="•"))
            i += 1
            continue
        m = re.match(r"^(\s*)(\d+)[.、]\s+(.*)$", line)
        if m:
            flush()
            story.append(Paragraph(inline(m.group(3)), num_st,
                                   bulletText=m.group(2) + "."))
            i += 1
            continue
        if s in ("---", "***", "___"):
            flush()
            story.append(HRFlowable(width="100%", thickness=0.6,
                                    color=HexColor("#cccccc"),
                                    spaceBefore=6, spaceAfter=10))
            i += 1
            continue
        if not s:
            flush(); i += 1
            continue
        para.append(s)
        i += 1
    flush()

# ---------- 文档模板 ----------
class TutorialDoc(BaseDocTemplate):
    def afterFlowable(self, flowable):
        if isinstance(flowable, Paragraph) and flowable.style.name == "ChapterTitle":
            key = getattr(flowable, "_toc_key", None)
            if key:
                self.canv.bookmarkPage(key)
                self.notify("TOCEntry",
                            (0, flowable.getPlainText(), self.page, key))

def cover_page(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(NAVY)
    canvas.setLineWidth(2)
    canvas.line(M, PAGE_H - 3.2 * cm, PAGE_W - M, PAGE_H - 3.2 * cm)
    canvas.setLineWidth(0.8)
    canvas.line(M, 3.2 * cm, PAGE_W - M, 3.2 * cm)
    canvas.restoreState()

def body_page(canvas, doc):
    canvas.saveState()
    canvas.setFont("CJK", 8.5)
    canvas.setFillColor(HexColor("#888888"))
    canvas.drawString(M, PAGE_H - 1.6 * cm, "FocusPet 零基础开发教程")
    canvas.drawRightString(PAGE_W - M, PAGE_H - 1.6 * cm, "零基础 Swift macOS 实战")
    canvas.setStrokeColor(HexColor("#dddddd"))
    canvas.setLineWidth(0.5)
    canvas.line(M, PAGE_H - 1.85 * cm, PAGE_W - M, PAGE_H - 1.85 * cm)
    canvas.line(M, 1.7 * cm, PAGE_W - M, 1.7 * cm)
    canvas.setFont("CJK", 9)
    canvas.drawCentredString(PAGE_W / 2, 1.25 * cm, f"— {doc.page} —")
    canvas.restoreState()

def build():
    doc = TutorialDoc(OUT_PDF, pagesize=A4,
                      topMargin=2.4 * cm, bottomMargin=2.4 * cm,
                      leftMargin=M, rightMargin=M,
                      title="FocusPet 零基础开发教程",
                      author="Kimi Work",
                      subject="从零开始用 Swift 构建桌面宠物番茄钟")
    cover_frame = Frame(M, 2 * cm, DOC_W, PAGE_H - 4 * cm, id="cover")
    body_frame = Frame(M, 2.2 * cm, DOC_W, PAGE_H - 4.6 * cm, id="body")
    doc.addPageTemplates([
        PageTemplate(id="Cover", frames=[cover_frame], onPage=cover_page),
        PageTemplate(id="Body", frames=[body_frame], onPage=body_page),
    ])

    story = []
    # 封面
    story.append(Spacer(1, 4.8 * cm))
    story.append(Paragraph("FocusPet 零基础开发教程", cover_title))
    story.append(Spacer(1, 0.7 * cm))
    story.append(Paragraph("从零开始，用 Swift 构建一只陪你专注的桌面宠物",
                           cover_sub))
    story.append(Spacer(1, 0.35 * cm))
    story.append(Paragraph("15 篇正文 · 约 4000 行真实源码 · 每行代码都可对照",
                           cover_sub))
    story.append(Spacer(1, 7.5 * cm))
    story.append(Paragraph("2026 年 9 月", cover_date))
    story.append(NextPageTemplate("Body"))
    story.append(PageBreak())

    # 目录
    story.append(Paragraph("目  录", toc_title))
    toc = TableOfContents()
    toc.levelStyles = [toc_lv0]
    toc.dotsMinLevel = 0
    story.append(toc)

    # 正文：00–14 按文件名排序，README 总索引在最后
    files = sorted(glob.glob(os.path.join(TUTORIAL_DIR, "*.md")))
    files = [f for f in files if os.path.basename(f) != "README.md"] + \
            [os.path.join(TUTORIAL_DIR, "README.md")]
    for idx, path in enumerate(files):
        story.append(PageBreak())
        with open(path, encoding="utf-8") as f:
            parse_markdown(f.read(), story, idx)

    # 标题与后续段落保持同页
    for fl in story:
        if isinstance(fl, Paragraph) and fl.style.name in ("H2", "H3"):
            fl.keepWithNext = True

    doc.multiBuild(story)
    print(f"OK: {OUT_PDF}")

if __name__ == "__main__":
    build()
