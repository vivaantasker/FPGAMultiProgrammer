from pathlib import Path
import re

from docx import Document
from docx.oxml.ns import qn
from docx.text.paragraph import Paragraph
from docx.table import Table


ROOT = Path(__file__).resolve().parent
DOCX = ROOT / "multi_image_fpga_verification_manuscript.docx"
OUT = ROOT / "multi_image_fpga_verification_manuscript.tex"


def esc(value):
    value = (value.replace("\\", r"\textbackslash{}")
                  .replace("&", r"\&").replace("%", r"\%")
                  .replace("$", r"\$").replace("#", r"\#")
                  .replace("_", r"\_").replace("{", r"\{")
                  .replace("}", r"\}").replace("~", r"\textasciitilde{}")
                  .replace("^", r"\textasciicircum{}"))
    value = value.replace("→", r"$\rightarrow$").replace("—", "---").replace("–", "--")
    value = re.sub(r"\[(\d+)\](?:,\s*\[(\d+)\])?",
                   lambda m: r"\cite{" + m.group(1) +
                   ("," + m.group(2) if m.group(2) else "") + "}", value)
    return value


def blocks(document):
    for node in document.element.body.iterchildren():
        if node.tag == qn("w:p"):
            yield Paragraph(node, document)
        elif node.tag == qn("w:tbl"):
            yield Table(node, document)


def emit_table(table):
    rows = [[cell.text.strip().replace("\n", " ") for cell in row.cells]
            for row in table.rows]
    if not rows:
        return ""
    if len(rows[0]) == 1 and rows[0][0].startswith("CONTROL"):
        lines = []
        raw = rows[0][0]
        parts = re.findall(
            r"(CONTROL|DATA|FEEDBACK|PACKAGE)\s+(.*?)(?=(?:CONTROL|DATA|FEEDBACK|PACKAGE)\s+|$)",
            raw,
        )
        for label, detail in parts:
            lines.append(r"\textbf{" + label + "} " + esc(detail.strip()) + r"\\")
        return (r"\begin{center}\fbox{\begin{minipage}{0.94\columnwidth}" + "\n"
                + r"\footnotesize\raggedright " + "\n".join(lines)
                + "\n" + r"\end{minipage}}\end{center}" + "\n")

    ncols = len(rows[0])
    if ncols == 3:
        spec = r"@{}>{\raggedright\arraybackslash}p{0.28\columnwidth}"
        spec += r">{\raggedright\arraybackslash}p{0.31\columnwidth}"
        spec += r">{\raggedright\arraybackslash}X@{}"
    else:
        spec = "@{}" + "X" * ncols + "@{}"
    out = [r"\begin{center}", r"\scriptsize", r"\setlength{\tabcolsep}{2.5pt}",
           r"\renewcommand{\arraystretch}{1.08}",
           rf"\begin{{tabularx}}{{\columnwidth}}{{{spec}}}", r"\toprule"]
    out.append(" & ".join(r"\textbf{" + esc(c) + "}" for c in rows[0]) + r" \\")
    out.append(r"\midrule")
    for row in rows[1:]:
        out.append(" & ".join(esc(c) for c in row) + r" \\")
    out.extend([r"\bottomrule", r"\end{tabularx}", r"\end{center}"])
    return "\n".join(out) + "\n"


doc = Document(DOCX)
items = list(blocks(doc))
paragraphs = [b.text.strip() for b in items if isinstance(b, Paragraph) and b.text.strip()]
title = paragraphs[0]
author = paragraphs[1]

header = r"""\documentclass[conference]{IEEEtran}
\usepackage[T1]{fontenc}
\usepackage[utf8]{inputenc}
\usepackage{lmodern}
\usepackage{microtype}
\usepackage{tabularx}
\usepackage{booktabs}
\usepackage{array}
\usepackage{balance}
\usepackage{url}
\begin{document}
"""
body = [r"\title{" + esc(title) + "}",
        r"\author{\IEEEauthorblockN{" + esc(author) + "}}",
        r"\maketitle"]

seen_title = 0
in_abstract = False
in_keywords = False
in_references = False
for item in items:
    if isinstance(item, Table):
        body.append(emit_table(item))
        continue
    text = item.text.strip()
    if not text:
        continue
    if seen_title < 2:
        seen_title += 1
        continue
    if text == "ABSTRACT":
        body.append(r"\begin{abstract}")
        in_abstract = True
        continue
    if in_abstract:
        body.append(esc(text))
        body.append(r"\end{abstract}")
        in_abstract = False
        continue
    if text.startswith("Index Terms—"):
        body.append(r"\begin{IEEEkeywords}" + esc(text.split("—", 1)[1].strip()) + r"\end{IEEEkeywords}")
        continue
    if text == "REFERENCES":
        body.append(r"\balance")
        body.append(r"\begin{thebibliography}{00}")
        in_references = True
        continue
    if in_references:
        match = re.match(r"\[(\d+)\]\s*(.*)", text)
        if match:
            body.append(r"\bibitem{" + match.group(1) + "}" + esc(match.group(2)))
        continue
    if re.match(r"^[IVX]+\.\s", text):
        heading = re.sub(r"^[IVX]+\.\s*", "", text)
        body.append(r"\section{" + esc(heading) + "}")
    elif re.match(r"^[A-Z]\.\s", text):
        heading = re.sub(r"^[A-Z]\.\s*", "", text)
        body.append(r"\subsection{" + esc(heading) + "}")
    elif text.startswith("TABLE ") or text.startswith("Fig. "):
        body.append(r"\noindent\textbf{\footnotesize " + esc(text) + r"}\par\vspace{1pt}")
    else:
        body.append(esc(text))

if in_references:
    body.append(r"\end{thebibliography}")
body.append(r"\end{document}")
OUT.write_text(header + "\n\n".join(body) + "\n", encoding="utf-8")
print(OUT)
