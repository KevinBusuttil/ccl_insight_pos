#!/usr/bin/env python3
"""Validate the generated Local Multi-Shop PDFs and their release claims."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "output" / "pdf"


@dataclass(frozen=True)
class PdfSpec:
    path: Path
    title: str
    page_count: int
    required_text: tuple[str, ...]


SPECS = (
    PdfSpec(
        path=OUTPUT / "Neuradix_POS_Local_Multi_Shop_User_Guide.pdf",
        title="Neuradix POS Local Multi-Shop User Guide",
        page_count=11,
        required_text=(
            "Register the business and first shop",
            "Pair a register into its intended shop",
            "Keep selling while offline",
            "18 sales on each register",
            "If every synchronized device is lost",
        ),
    ),
    PdfSpec(
        path=OUTPUT / "Neuradix_POS_Technical_Architecture.pdf",
        title="Neuradix POS Technical Architecture",
        page_count=12,
        required_text=(
            "Storage boundary",
            "stateless relay",
            "ERPNext",
            "Odoo",
            "Neuradix Atlas Team",
            "RAW SQL STORAGE AUDIT",
            "total device loss is unrecoverable",
        ),
    ),
)


FORBIDDEN_TEXT = (
    "docs20260929@example.test",
    "ops.manager@neuradix.local",
    "sara.camilleri@neuradix.local",
    "lorem ipsum",
    "placeholder contact",
)


def _normalized_text(reader: PdfReader) -> str:
    extracted = "\n".join(page.extract_text() or "" for page in reader.pages)
    return re.sub(r"\s+", " ", extracted).strip()


def validate_pdf(spec: PdfSpec) -> list[str]:
    errors: list[str] = []
    if not spec.path.exists():
        return [f"Missing PDF: {spec.path}"]

    reader = PdfReader(str(spec.path))
    metadata = reader.metadata or {}
    if metadata.get("/Title") != spec.title:
        errors.append(
            f"{spec.path.name}: title is {metadata.get('/Title')!r}, "
            f"expected {spec.title!r}"
        )
    if metadata.get("/Author") != "Neuradix":
        errors.append(f"{spec.path.name}: author metadata must be Neuradix")
    if len(reader.pages) != spec.page_count:
        errors.append(
            f"{spec.path.name}: has {len(reader.pages)} pages, "
            f"expected {spec.page_count}"
        )

    for index, page in enumerate(reader.pages, start=1):
        width = float(page.mediabox.width)
        height = float(page.mediabox.height)
        if width <= height:
            errors.append(f"{spec.path.name}: page {index} is not landscape")
        if abs(width - 841.89) > 1 or abs(height - 595.28) > 1:
            errors.append(
                f"{spec.path.name}: page {index} is not A4 landscape "
                f"({width:.2f}x{height:.2f})"
            )

    text = _normalized_text(reader)
    folded = text.casefold()
    for required in spec.required_text:
        if required.casefold() not in folded:
            errors.append(f"{spec.path.name}: missing required text {required!r}")
    for forbidden in FORBIDDEN_TEXT:
        if forbidden.casefold() in folded:
            errors.append(f"{spec.path.name}: contains forbidden text {forbidden!r}")
    if re.search(r"\bAX\b", text, flags=re.IGNORECASE):
        errors.append(f"{spec.path.name}: contains an out-of-scope AX reference")

    return errors


def validate_all() -> list[str]:
    return [error for spec in SPECS for error in validate_pdf(spec)]


def main() -> int:
    errors = validate_all()
    if errors:
        for error in errors:
            print(f"[pdf-validation] ERROR: {error}")
        return 1
    for spec in SPECS:
        print(
            f"[pdf-validation] PASS: {spec.path.name} "
            f"({spec.page_count} pages, A4 landscape)"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
