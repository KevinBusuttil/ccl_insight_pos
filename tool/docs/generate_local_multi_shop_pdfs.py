#!/usr/bin/env python3
"""Generate the Local Multi-Shop client guide and technical architecture PDFs."""

from __future__ import annotations

import json
import math
from pathlib import Path

from reportlab.lib.colors import Color, HexColor, white
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import Paragraph


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "output" / "pdf"
SCREENSHOTS = ROOT / "docs" / "test-results" / "screenshots" / "local_multi_shop_2026-09-29"
RESULT = ROOT / "docs" / "test-results" / "screenshots" / "local_multi_shop_server_e2e_result.json"
AUDIT = ROOT / "docs" / "test-results" / "screenshots" / "local_multi_shop_server_storage_audit.json"

PAGE_W, PAGE_H = landscape(A4)
TEAL = HexColor("#2B6F77")
TEAL_DARK = HexColor("#163A3E")
TEAL_LIGHT = HexColor("#EAF2F2")
SAGE = HexColor("#86A96F")
SAGE_LIGHT = HexColor("#EDF3E9")
CHARCOAL = HexColor("#263234")
MUTED = HexColor("#66787B")
OFF_WHITE = HexColor("#F6F8F6")
CREAM = HexColor("#F7F1DE")
LINE = HexColor("#CDD7D5")
AMBER = HexColor("#C9872D")
RED = HexColor("#B93D4B")
BLUE = HexColor("#477D9B")

GUIDE_COVER_MARK_X = 42
GUIDE_COVER_MARK_Y = PAGE_H - 176
GUIDE_COVER_MARK_WIDTH = 118
GUIDE_COVER_MARK_HEIGHT = 118
GUIDE_COVER_MARK_RADIUS = 28


def register_fonts() -> tuple[str, str, str]:
    regular = "/System/Library/Fonts/Avenir.ttc"
    next_font = "/System/Library/Fonts/Avenir Next.ttc"
    try:
        pdfmetrics.registerFont(TTFont("Neuradix", regular, subfontIndex=0))
        pdfmetrics.registerFont(TTFont("Neuradix-Bold", next_font, subfontIndex=5))
        pdfmetrics.registerFont(TTFont("Neuradix-Medium", next_font, subfontIndex=3))
        return "Neuradix", "Neuradix-Medium", "Neuradix-Bold"
    except Exception:
        return "Helvetica", "Helvetica", "Helvetica-Bold"


FONT, FONT_MEDIUM, FONT_BOLD = register_fonts()


class Deck:
    def __init__(self, path: Path, title: str, subject: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        self.canvas = Canvas(str(path), pagesize=(PAGE_W, PAGE_H), pageCompression=1)
        self.canvas.setTitle(title)
        self.canvas.setAuthor("Neuradix")
        self.canvas.setSubject(subject)
        self.canvas.setCreator("Neuradix POS ReportLab documentation generator")
        self.title = title
        self.page_number = 0

    def page(self, section: str, *, background: Color = OFF_WHITE) -> None:
        if self.page_number:
            self.canvas.showPage()
        self.page_number += 1
        self.canvas.setFillColor(background)
        self.canvas.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        self.canvas.setFillColor(TEAL)
        self.canvas.rect(0, PAGE_H - 8, PAGE_W, 8, fill=1, stroke=0)
        if self.page_number > 1:
            self.canvas.setFont(FONT_MEDIUM, 8.5)
            self.canvas.setFillColor(MUTED)
            self.canvas.drawString(38, 20, section.upper())
            self.canvas.drawRightString(PAGE_W - 38, 20, f"{self.page_number:02d}")

    def heading(self, text: str, subtitle: str = "") -> None:
        self.canvas.setFillColor(TEAL_DARK)
        self.canvas.setFont(FONT_BOLD, 27)
        self.canvas.drawString(42, PAGE_H - 58, text)
        if subtitle:
            self.text(subtitle, 42, PAGE_H - 89, PAGE_W - 84, 34, size=11.5, color=MUTED)

    def text(
        self,
        text: str,
        x: float,
        y_top: float,
        width: float,
        max_height: float,
        *,
        size: float = 11,
        color: Color = CHARCOAL,
        leading: float | None = None,
        font: str = FONT,
        align: int = TA_LEFT,
    ) -> float:
        style = ParagraphStyle(
            name="body",
            fontName=font,
            fontSize=size,
            leading=leading or size * 1.35,
            textColor=color,
            alignment=align,
            spaceAfter=0,
        )
        para = Paragraph(text, style)
        _, height = para.wrap(width, max_height)
        if height > max_height + 0.5:
            raise ValueError(f"Text overflow ({height:.1f}>{max_height:.1f}): {text[:80]}")
        para.drawOn(self.canvas, x, y_top - height)
        return height

    def card(
        self,
        x: float,
        y: float,
        width: float,
        height: float,
        *,
        fill: Color = white,
        stroke: Color = LINE,
        radius: float = 14,
    ) -> None:
        self.canvas.setFillColor(fill)
        self.canvas.setStrokeColor(stroke)
        self.canvas.setLineWidth(0.8)
        self.canvas.roundRect(x, y, width, height, radius, fill=1, stroke=1)

    def label(self, text: str, x: float, y: float, *, fill: Color = TEAL_LIGHT) -> float:
        width = pdfmetrics.stringWidth(text, FONT_MEDIUM, 9) + 20
        self.canvas.setFillColor(fill)
        self.canvas.roundRect(x, y, width, 23, 11, fill=1, stroke=0)
        self.canvas.setFont(FONT_MEDIUM, 9)
        self.canvas.setFillColor(TEAL)
        self.canvas.drawString(x + 10, y + 7, text)
        return width

    def bullet_list(
        self,
        items: list[str],
        x: float,
        y_top: float,
        width: float,
        *,
        size: float = 10.5,
        color: Color = CHARCOAL,
        gap: float = 7,
    ) -> float:
        y = y_top
        for item in items:
            self.canvas.setFillColor(SAGE)
            self.canvas.circle(x + 4, y - 6, 3, fill=1, stroke=0)
            height = self.text(item, x + 16, y, width - 16, 80, size=size, color=color)
            y -= height + gap
        return y

    def screenshot(
        self,
        path: Path,
        x: float,
        y: float,
        width: float,
        height: float,
        *,
        label: str = "",
    ) -> None:
        self.card(x, y, width, height, fill=white, stroke=LINE, radius=12)
        inner_x, inner_y = x + 7, y + 7
        inner_w, inner_h = width - 14, height - 14
        if label:
            inner_h -= 22
            self.canvas.setFillColor(MUTED)
            self.canvas.setFont(FONT_MEDIUM, 8)
            self.canvas.drawString(inner_x + 3, y + height - 18, label.upper())
        if not path.exists():
            self.canvas.setFillColor(TEAL_LIGHT)
            self.canvas.roundRect(inner_x, inner_y, inner_w, inner_h, 8, fill=1, stroke=0)
            self.text("Screenshot captured during the certified workflow.", inner_x + 20, inner_y + inner_h / 2 + 8, inner_w - 40, 40, color=MUTED)
            return
        image = ImageReader(str(path))
        image_w, image_h = image.getSize()
        scale = min(inner_w / image_w, inner_h / image_h)
        draw_w, draw_h = image_w * scale, image_h * scale
        draw_x = inner_x + (inner_w - draw_w) / 2
        draw_y = inner_y + (inner_h - draw_h) / 2
        self.canvas.drawImage(image, draw_x, draw_y, draw_w, draw_h, mask="auto")

    def step(
        self,
        number: int,
        title: str,
        detail: str,
        x: float,
        y: float,
        width: float,
        *,
        color: Color = TEAL,
    ) -> None:
        self.canvas.setFillColor(color)
        self.canvas.circle(x + 18, y + 32, 18, fill=1, stroke=0)
        self.canvas.setFillColor(white)
        self.canvas.setFont(FONT_BOLD, 13)
        self.canvas.drawCentredString(x + 18, y + 27, str(number))
        self.canvas.setFillColor(TEAL_DARK)
        self.canvas.setFont(FONT_BOLD, 12)
        self.canvas.drawString(x + 45, y + 42, title)
        self.text(detail, x + 45, y + 30, width - 45, 72, size=9.5, color=MUTED)

    def arrow(self, x1: float, y1: float, x2: float, y2: float, *, color: Color = TEAL) -> None:
        self.canvas.setStrokeColor(color)
        self.canvas.setFillColor(color)
        self.canvas.setLineWidth(2)
        self.canvas.line(x1, y1, x2, y2)
        angle = math.atan2(y2 - y1, x2 - x1)
        length = 8
        for offset in (2.5, -2.5):
            tip_angle = angle + math.pi + offset * 0.12
            self.canvas.line(
                x2,
                y2,
                x2 + length * math.cos(tip_angle),
                y2 + length * math.sin(tip_angle),
            )

    def finish(self) -> None:
        self.canvas.save()


def screenshot(name: str) -> Path:
    return SCREENSHOTS / name


def guide_pdf(result: dict, audit: dict) -> Path:
    path = OUTPUT / "Neuradix_POS_Local_Multi_Shop_User_Guide.pdf"
    deck = Deck(
        path,
        "Neuradix POS Local Multi-Shop User Guide",
        "Certified setup, selling, synchronization, and recovery guide",
    )

    deck.page("Cover", background=CREAM)
    deck.canvas.setFillColor(TEAL)
    deck.canvas.roundRect(
        GUIDE_COVER_MARK_X,
        GUIDE_COVER_MARK_Y,
        GUIDE_COVER_MARK_WIDTH,
        GUIDE_COVER_MARK_HEIGHT,
        GUIDE_COVER_MARK_RADIUS,
        fill=1,
        stroke=0,
    )
    deck.canvas.setFillColor(white)
    deck.canvas.setFont(FONT_BOLD, 46)
    deck.canvas.drawCentredString(101, PAGE_H - 124, "N")
    deck.canvas.setFillColor(TEAL_DARK)
    deck.canvas.setFont(FONT_BOLD, 36)
    deck.canvas.drawString(196, PAGE_H - 142, "Neuradix POS")
    deck.canvas.setFont(FONT_BOLD, 24)
    deck.canvas.setFillColor(TEAL)
    deck.canvas.drawString(196, PAGE_H - 184, "Local Multi-Shop User Guide")
    deck.text(
        "Operate every shop locally. Share customers and finalized sales across trusted registers. Keep shop inventory where it belongs.",
        196,
        PAGE_H - 224,
        520,
        80,
        size=15,
        color=CHARCOAL,
        leading=21,
    )
    x = 196
    for text in ("OFFLINE-FIRST", "SHOP-LOCAL STOCK", "PRIVATE BY DESIGN"):
        x += deck.label(text, x, 166, fill=white) + 10
    deck.text("Certified workflow - 29 September 2026", 196, 105, 420, 24, size=10, color=MUTED)

    deck.page("Model")
    deck.heading("What moves - and what stays local", "The synchronization boundary is deliberately narrow.")
    deck.card(42, 105, 360, 365, fill=SAGE_LIGHT)
    deck.label("SYNCHRONIZES", 66, 425, fill=white)
    deck.canvas.setFillColor(TEAL_DARK)
    deck.canvas.setFont(FONT_BOLD, 21)
    deck.canvas.drawString(66, 382, "Across the whole business")
    deck.bullet_list(
        [
            "Customer profiles and customer updates",
            "Finalized sales and immutable line snapshots",
            "Event acknowledgements and sync diagnostics",
        ],
        66,
        344,
        300,
        size=12,
        gap=14,
    )
    deck.card(430, 105, 370, 365, fill=white)
    deck.label("STAYS LOCAL", 454, 425)
    deck.canvas.setFillColor(TEAL_DARK)
    deck.canvas.setFont(FONT_BOLD, 21)
    deck.canvas.drawString(454, 382, "Inside each shop or register")
    deck.bullet_list(
        [
            "Items, prices, barcodes, images, and stock stay within the assigned shop",
            "Drafts, parked carts, and incomplete sales stay on the current register",
            "Local settings and decrypted keys never enter the relay",
        ],
        454,
        344,
        310,
        size=12,
        gap=12,
    )

    deck.page("Registration")
    deck.heading("1. Register the business and first shop", "No backend seeding or manual API calls are required.")
    deck.step(1, "Choose Local Multi-Shop", "Use Neuradix Cloud, select Free Local, then enable Local Multi-Shop.", 42, 355, 300)
    deck.step(2, "Name the first shop", "Enter a shop name and a unique code alongside the owner details.", 42, 268, 300)
    deck.step(3, "Create and trust", "Registration creates the business, subscription, first shop, and first trusted register atomically.", 42, 181, 300)
    deck.screenshot(screenshot("06_registration_sanitized.png"), 365, 90, 435, 390, label="Business and first-shop fields")

    deck.page("Shop Management")
    deck.heading("2. Create shops from the owner interface", "Inventory remains shop-local; customers and finalized sales remain business-wide.")
    deck.screenshot(screenshot("02_shop_management.png"), 42, 86, 520, 390, label="Owner - Shop Management")
    deck.card(590, 86, 210, 390, fill=white)
    deck.label("OWNER ONLY", 614, 430)
    deck.bullet_list(
        [
            "Open My Profile",
            "Select Add Shop",
            "Use a unique shop code",
            "Review trusted register counts",
            "Revoke lost devices promptly",
        ],
        614,
        380,
        162,
        size=10.5,
        gap=13,
    )

    deck.page("Pairing")
    deck.heading("3. Pair a register into its intended shop", "The new register chooses its shop before it creates a pairing request.")
    deck.screenshot(screenshot("07_register_shop_selection.png"), 42, 105, 295, 355, label="Select the destination shop")
    titles = ["Sign in", "Choose shop", "Approve code", "Join relay"]
    details = [
        "Use the business owner account on the new register.",
        "Select the register's intended physical shop.",
        "A trusted owner register approves the short-lived code.",
        "The new device receives an opaque encrypted key envelope.",
    ]
    for index, (title, detail) in enumerate(zip(titles, details), start=1):
        row = (index - 1) // 2
        column = (index - 1) % 2
        x = 365 + (column * 215)
        y = 305 - (row * 125)
        deck.card(x, y, 195, 110, fill=white)
        deck.step(index, title, detail, x + 12, y + 15, 170, color=TEAL if index < 4 else SAGE)
    deck.card(365, 105, 410, 55, fill=TEAL_LIGHT, stroke=TEAL_LIGHT)
    deck.text(
        "Security rule: never approve an unexpected code. Pair only a register physically controlled by the business, then verify the Shop badge before selling.",
        384,
        144,
        370,
        36,
        size=9.5,
        color=TEAL_DARK,
    )

    deck.page("Inventory And Sales")
    deck.heading("4. Build local inventory and record sales", "Search by name, SKU, or barcode; compatible hardware scanners type into the barcode field.")
    deck.screenshot(screenshot("05_final_convergence_shop_a.png"), 42, 100, 480, 370, label="Shop A inventory and sale composer")
    deck.card(545, 100, 255, 370, fill=white)
    deck.bullet_list(
        [
            "Create items separately in each shop.",
            "Add image, SKU, barcode, price, and stock.",
            "Search or scan, then add the exact match.",
            "Select a shared customer.",
            "Review cart and total, then Record Sale.",
            "Only the finalized sale leaves this register.",
        ],
        570,
        425,
        205,
        size=10.5,
        gap=10,
    )

    deck.page("Offline Work")
    deck.heading("5. Keep selling while offline", "SQLite commits first; synchronization follows when trusted devices overlap online.")
    deck.screenshot(screenshot("10_offline_guidance_shop_a.png"), 42, 102, 500, 360, label="Actionable offline guidance")
    deck.card(565, 102, 235, 360, fill=white)
    deck.label("RECOVERY", 590, 416)
    for index, (title, detail) in enumerate(
        [
            ("Reconnect", "Restore internet on the register."),
            ("Overlap", "Keep at least one trusted peer online at the same time."),
            ("Observe", "Wait for Live Relay and Pending: 0."),
            ("Verify", "Compare shared customers and History."),
        ],
        start=1,
    ):
        deck.step(index, title, detail, 585, 345 - ((index - 1) * 72), 190)

    deck.page("Verification")
    deck.heading("6. Verify convergence without mixing catalogs", "The certified run ended with identical customer/sale history and isolated shop stock.")
    deck.screenshot(screenshot("09_shared_history_shop_a.png"), 42, 112, 450, 350, label="Shared finalized-sale history")
    deck.card(518, 112, 282, 350, fill=SAGE_LIGHT, stroke=SAGE_LIGHT)
    deck.label("CERTIFIED RESULT", 542, 416, fill=white)
    a = result["shop_a"]
    metrics = [
        ("18", "sales on each register"),
        ("6", "customers on each register"),
        ("4", "local items per shop"),
        ("0", "pending events"),
    ]
    y = 363
    for value, label in metrics:
        deck.canvas.setFont(FONT_BOLD, 24)
        deck.canvas.setFillColor(TEAL)
        deck.canvas.drawString(545, y, value)
        deck.canvas.setFont(FONT, 10.5)
        deck.canvas.setFillColor(CHARCOAL)
        deck.canvas.drawString(595, y + 4, label)
        y -= 57
    deck.text(f"Run {result['run_id']} - business {a['business_id']}", 542, 154, 230, 30, size=8.5, color=MUTED)

    deck.page("Reassignment")
    deck.heading("7. Move a register safely", "A shop move changes local inventory scope, so the guard is intentionally strict.")
    deck.card(42, 118, 758, 330, fill=white)
    steps = [
        ("Check", "Pending events = 0"),
        ("Finish", "Cart and parked work are empty"),
        ("Confirm", "Owner selects the new shop"),
        ("Clear", "Old shop inventory cache is removed"),
        ("Remount", "The shell reloads under the new shop"),
    ]
    for index, (title, detail) in enumerate(steps):
        x = 66 + index * 145
        deck.canvas.setFillColor(TEAL if index < 3 else SAGE)
        deck.canvas.circle(x + 42, 330, 34, fill=1, stroke=0)
        deck.canvas.setFillColor(white)
        deck.canvas.setFont(FONT_BOLD, 18)
        deck.canvas.drawCentredString(x + 42, 324, str(index + 1))
        deck.canvas.setFillColor(TEAL_DARK)
        deck.canvas.setFont(FONT_BOLD, 11)
        deck.canvas.drawCentredString(x + 42, 260, title)
        deck.text(detail, x - 8, 238, 100, 70, size=9, color=MUTED, align=1)
        if index < len(steps) - 1:
            deck.arrow(x + 78, 330, x + 126, 330)
    deck.text("Customers and finalized sales remain because they belong to the business, not to a shop catalog.", 96, 168, 650, 38, size=12, color=TEAL_DARK, align=1)

    deck.page("Troubleshooting")
    deck.heading("8. Troubleshooting", "Use the badges and diagnostics before changing configuration.")
    rows = [
        ("Offline / Queued", "Reconnect this register and one trusted peer; retry is automatic."),
        ("Pairing Required", "Select the correct shop and ask a trusted owner register to approve."),
        ("Pending stays above 0", "Leave both apps open and online, then choose Refresh."),
        ("Unexpected inventory", "Stop selling and verify the Shop badge and device assignment."),
        ("Lost device", "Revoke its trust from Shop Management immediately."),
    ]
    y = 430
    for status, action in rows:
        deck.card(55, y - 55, 730, 62, fill=white)
        deck.label(status.upper(), 72, y - 36, fill=TEAL_LIGHT if status != "Lost device" else HexColor("#F8E8E8"))
        deck.text(action, 275, y - 14, 480, 40, size=10.5)
        y -= 72

    deck.page("Recovery", background=CREAM)
    deck.heading("Protect every local replica", "Free Local Multi-Shop intentionally has no permanent cloud copy of operational data.")
    deck.card(42, 130, 500, 300, fill=white)
    deck.label("BEFORE GO-LIVE", 67, 383)
    deck.bullet_list(
        [
            "Pair at least two trusted devices and verify Pending: 0 regularly.",
            "Define who can add shops, pair registers, and revoke lost devices.",
            "Keep device OS backups and physical access controls enabled.",
            "Use HTTPS/WSS production endpoints and monitored relay supervision.",
        ],
        67,
        340,
        445,
        size=11.5,
        gap=12,
    )
    deck.card(568, 130, 232, 300, fill=RED, stroke=RED)
    deck.canvas.setFillColor(white)
    deck.canvas.setFont(FONT_BOLD, 17)
    deck.canvas.drawString(592, 382, "Recovery warning")
    deck.text(
        "If every synchronized device is lost, Neuradix Cloud cannot restore free-tier inventory, customers, or sales. The devices are the operational replicas.",
        592,
        344,
        184,
        170,
        size=12,
        color=white,
        leading=17,
    )
    deck.text("Server storage audit: all operational counts = 0", 592, 179, 184, 35, size=9, color=white)
    deck.finish()
    return path


def tech_pdf(result: dict, audit: dict) -> Path:
    path = OUTPUT / "Neuradix_POS_Technical_Architecture.pdf"
    deck = Deck(
        path,
        "Neuradix POS Technical Architecture",
        "Frontend, metadata backend, cryptography, relay, storage, and certification",
    )

    deck.page("Cover", background=TEAL_DARK)
    deck.canvas.setFillColor(SAGE)
    deck.canvas.circle(690, 440, 115, fill=1, stroke=0)
    deck.canvas.setFillColor(TEAL)
    deck.canvas.circle(690, 440, 78, fill=1, stroke=0)
    deck.canvas.setFillColor(white)
    deck.canvas.setFont(FONT_BOLD, 16)
    deck.canvas.drawCentredString(690, 435, "SYNC")
    deck.canvas.setFillColor(white)
    deck.canvas.setFont(FONT_BOLD, 36)
    deck.canvas.drawString(56, PAGE_H - 145, "Neuradix POS")
    deck.canvas.setFont(FONT_BOLD, 24)
    deck.canvas.setFillColor(SAGE)
    deck.canvas.drawString(56, PAGE_H - 188, "Technical Architecture")
    deck.text(
        "Local Multi-Shop selective replication, metadata boundaries, encryption, relay routing, and verified release gates.",
        56,
        PAGE_H - 232,
        500,
        90,
        size=15,
        color=white,
        leading=21,
    )
    deck.text("Architecture status - 29 September 2026", 56, 105, 400, 24, size=10, color=HexColor("#B7CECF"))

    deck.page("Deployment Modes")
    deck.heading("One client, four persistence models", "Commercial caps remain backend configuration, never frontend constants.")
    modes = [
        ("FREE LOCAL MULTI-SHOP", TEAL_LIGHT, "Metadata only", "Shop-local inventory; peer-synced customers and finalized sales."),
        ("SHARED CLOUD STARTER", SAGE_LIGHT, "Shared doctypes", "Capped products, customers, sales, and sale lines with business isolation."),
        ("SHARED CLOUD PAID", CREAM, "Shared doctypes", "Higher or unrestricted configured limits and cloud history."),
        (
            "DEDICATED BACKEND",
            white,
            "Connector-owned",
            "All business data persists through a connector such as ERPNext. Odoo and Neuradix Atlas Team are planned targets.",
        ),
    ]
    for index, (name, fill, boundary, detail) in enumerate(modes):
        x = 42 + (index % 2) * 390
        y = 292 if index < 2 else 105
        deck.card(x, y, 365, 155, fill=fill)
        deck.label(name, x + 22, y + 108, fill=white)
        deck.canvas.setFont(FONT_BOLD, 14)
        deck.canvas.setFillColor(TEAL_DARK)
        deck.canvas.drawString(x + 22, y + 77, boundary)
        deck.text(detail, x + 22, y + 61, 320, 52, size=10.5, color=MUTED)

    deck.page("Components")
    deck.heading("Runtime components", "Operational plaintext exists only inside trusted clients.")
    components = [
        ("Flutter POS", "SQLite source of truth, UI, event producer/consumer", TEAL),
        ("Frappe metadata", "Identity, plan, shops, devices, public keys, enrollment", BLUE),
        ("Stateless relay", "In-memory routing of signed encrypted frames", SAGE),
        ("Trusted peer", "Scope validation, durable apply, acknowledgement", TEAL),
    ]
    for index, (name, detail, color) in enumerate(components):
        x = 50 + index * 195
        deck.card(x, 225, 165, 175, fill=white)
        deck.canvas.setFillColor(color)
        deck.canvas.circle(x + 82, 350, 27, fill=1, stroke=0)
        deck.canvas.setFont(FONT_BOLD, 12)
        deck.canvas.setFillColor(TEAL_DARK)
        deck.canvas.drawCentredString(x + 82, 304, name)
        deck.text(detail, x + 18, 281, 129, 80, size=9.5, color=MUTED, align=1)
        if index < 3:
            deck.arrow(x + 165, 310, x + 193, 310, color=MUTED)
    deck.text("The relay never receives a plaintext payload and has no durable mailbox.", 120, 170, 600, 45, size=13, color=TEAL_DARK, align=1)

    deck.page("Storage")
    deck.heading("Storage boundary", "Local Multi-Shop separates metadata from operational data.")
    deck.card(42, 100, 355, 365, fill=SAGE_LIGHT)
    deck.label("ON TRUSTED DEVICES", 66, 419, fill=white)
    deck.bullet_list(
        [
            "Shop item master, prices, barcodes, images, and stock",
            "Business customer replicas",
            "Finalized sales and immutable sale-line snapshots",
            "Encrypted outbox/inbox, acknowledgements, and conflicts",
            "Drafts, parked carts, and local settings",
            "Private keys and decrypted business key",
        ],
        66,
        376,
        300,
        size=10.5,
        gap=8,
    )
    deck.card(430, 100, 370, 365, fill=white)
    deck.label("ON NEURADIX INFRASTRUCTURE", 454, 419)
    deck.bullet_list(
        [
            "Identity, membership, and subscription state",
            "Shop and trusted-device metadata",
            "Device public keys and opaque key envelopes",
            "Short-lived relay authorization",
            "Temporary ciphertext in relay memory",
            "No Product, Customer, Sale, or Sale Item rows",
        ],
        454,
        376,
        310,
        size=10.5,
        gap=8,
    )

    deck.page("Event Scope")
    deck.heading("Selective replication contract", "Sale-line snapshots travel for history but never become another shop's inventory.")
    headers = ["ENTITY", "ROUTE", "RECIPIENT", "ACK SET"]
    widths = [180, 180, 230, 170]
    x0, y0 = 42, 428
    x = x0
    for header, width in zip(headers, widths):
        deck.canvas.setFillColor(TEAL)
        deck.canvas.rect(x, y0, width, 34, fill=1, stroke=0)
        deck.canvas.setFillColor(white)
        deck.canvas.setFont(FONT_BOLD, 9)
        deck.canvas.drawString(x + 12, y0 + 12, header)
        x += width
    rows = [
        ("Inventory item", "Same shop", "Online registers assigned to origin shop", "Same-shop active peers"),
        ("Customer", "Business-wide", "All online trusted business registers", "All active business peers"),
        ("Finalized sale", "Business-wide", "All online trusted business registers", "All active business peers"),
        ("Draft / parked", "None", "Current register only", "Not applicable"),
    ]
    y = y0 - 70
    for row_index, row in enumerate(rows):
        x = x0
        fill = white if row_index % 2 == 0 else TEAL_LIGHT
        deck.canvas.setFillColor(fill)
        deck.canvas.rect(x0, y, sum(widths), 68, fill=1, stroke=0)
        for value, width in zip(row, widths):
            deck.text(value, x + 12, y + 50, width - 24, 48, size=9.5, color=CHARCOAL)
            x += width
        y -= 70

    deck.page("Write Flow")
    deck.heading("Transactional write and delivery flow", "Acknowledgement follows durable apply, never mere transmission.")
    steps = [
        ("1", "Local commit", "Business record and outgoing event share one SQLite transaction."),
        ("2", "Protect", "AES-GCM encrypts payload; Ed25519 signs the envelope."),
        ("3", "Authorize", "Token binds business, device, shop, epoch, and protocol."),
        ("4", "Route", "Relay validates origin shop and selects eligible online peers."),
        ("5", "Apply", "Peer verifies, decrypts, validates scope, and commits atomically."),
        ("6", "Acknowledge", "Origin settles only after required peers confirm durable apply."),
    ]
    for index, (number, title, detail) in enumerate(steps):
        col, row = index % 3, index // 3
        x = 48 + col * 260
        y = 300 - row * 165
        deck.card(x, y, 230, 130, fill=white)
        deck.canvas.setFillColor(TEAL if row == 0 else SAGE)
        deck.canvas.circle(x + 32, y + 92, 19, fill=1, stroke=0)
        deck.canvas.setFillColor(white)
        deck.canvas.setFont(FONT_BOLD, 11)
        deck.canvas.drawCentredString(x + 32, y + 88, number)
        deck.canvas.setFillColor(TEAL_DARK)
        deck.canvas.setFont(FONT_BOLD, 12)
        deck.canvas.drawString(x + 60, y + 91, title)
        deck.text(detail, x + 20, y + 69, 190, 65, size=9.5, color=MUTED)

    deck.page("Cryptography")
    deck.heading("Trust and cryptography", "Metadata may identify a device; only a trusted device can decrypt business events.")
    crypt = [
        ("Ed25519", "Signs each event and authenticates its origin device."),
        ("X25519", "Protects the business-key envelope during enrollment."),
        ("AES-GCM", "Encrypts operational payloads and detects tampering."),
        ("HLC", "Orders customer updates without trusting wall clocks alone."),
    ]
    for index, (name, detail) in enumerate(crypt):
        x = 42 + index * 195
        deck.card(x, 235, 170, 190, fill=white)
        deck.canvas.setFillColor([TEAL, BLUE, SAGE, AMBER][index])
        deck.canvas.roundRect(x + 25, 352, 120, 40, 20, fill=1, stroke=0)
        deck.canvas.setFillColor(white)
        deck.canvas.setFont(FONT_BOLD, 13)
        deck.canvas.drawCentredString(x + 85, 367, name)
        deck.text(detail, x + 22, 325, 126, 90, size=10, color=MUTED, align=1)
    deck.card(76, 122, 690, 72, fill=TEAL_LIGHT, stroke=TEAL_LIGHT)
    deck.text("Plaintext business keys and decrypted payloads are never written to Frappe or relay logs.", 98, 168, 646, 40, size=12.5, color=TEAL_DARK, align=1)

    deck.page("Relay And ACK")
    deck.heading("Relay routing and acknowledgement sets", "Recipient scope and required acknowledgements use the same event policy.")
    deck.card(42, 105, 758, 350, fill=white)
    nodes = [
        (120, 320, "Shop A\nRegister", TEAL),
        (420, 320, "Stateless\nrelay", SAGE),
        (720, 390, "Shop A\npeer", TEAL),
        (720, 250, "Shop B\npeer", BLUE),
    ]
    for x, y, label, color in nodes:
        deck.canvas.setFillColor(color)
        deck.canvas.circle(x, y, 45, fill=1, stroke=0)
        deck.text(label.replace("\n", "<br/>"), x - 38, y + 12, 76, 50, size=9.5, color=white, align=1, font=FONT_BOLD)
    deck.arrow(165, 320, 370, 320)
    deck.arrow(465, 334, 675, 382)
    deck.arrow(465, 306, 675, 258, color=BLUE)
    deck.text("Inventory", 252, 342, 90, 20, size=9, color=TEAL)
    deck.text("Customer / sale", 510, 292, 130, 20, size=9, color=BLUE)
    deck.text("Inventory ACK waits only for active Shop A peers. Customer/sale ACK waits for every active business peer.", 120, 174, 600, 48, size=11.5, color=TEAL_DARK, align=1)

    deck.page("Registration APIs")
    deck.heading("Registration and enrollment boundary", "All flows are available to Flutter; no manual backend seeding is required.")
    apis = [
        ("register_business", "Owner, business, membership, subscription, optional device, first shop"),
        ("get_metadata", "Shops, trusted devices, current assignment, pending enrollment, relay URL"),
        ("create_shop", "Owner-only unique shop creation"),
        ("start_enrollment", "Selected shop, device public keys, expiring request"),
        ("approve_enrollment", "Trusted owner wraps business key for the new device"),
        ("complete_enrollment", "Device accepts envelope and becomes trusted"),
        ("issue_relay_token", "Short-lived token including authenticated shop_id"),
    ]
    y = 432
    for index, (name, detail) in enumerate(apis):
        deck.card(48, y - 46, 744, 52, fill=white if index % 2 == 0 else TEAL_LIGHT)
        deck.canvas.setFont(FONT_BOLD, 10.5)
        deck.canvas.setFillColor(TEAL)
        deck.canvas.drawString(66, y - 18, name)
        deck.text(detail, 240, y - 8, 525, 35, size=9.5, color=CHARCOAL)
        y -= 58

    deck.page("Reassignment")
    deck.heading("Safe shop reassignment lifecycle", "Changing shop scope is refused while local work could be stranded.")
    stages = [
        ("Preflight", "Read pending events, cart lines, and parked work."),
        ("Refuse", "Any non-zero guard blocks the operation."),
        ("Assign", "Owner changes device shop metadata."),
        ("Purge", "Clear old shop inventory and shop-scoped events."),
        ("Remount", "Reload shell using businessId:shopId state key."),
    ]
    for index, (name, detail) in enumerate(stages):
        x = 50 + index * 153
        deck.canvas.setFillColor(TEAL if index < 3 else SAGE)
        deck.canvas.roundRect(x, 310, 125, 55, 16, fill=1, stroke=0)
        deck.canvas.setFillColor(white)
        deck.canvas.setFont(FONT_BOLD, 11)
        deck.canvas.drawCentredString(x + 62, 331, name)
        deck.text(detail, x, 280, 125, 85, size=9.2, color=MUTED, align=1)
        if index < 4:
            deck.arrow(x + 126, 337, x + 151, 337)
    deck.card(76, 128, 690, 72, fill=SAGE_LIGHT, stroke=SAGE_LIGHT)
    deck.text("Business-wide customers and finalized sales survive reassignment; the prior shop catalog does not.", 98, 174, 646, 42, size=12, color=TEAL_DARK, align=1)

    deck.page("Certification")
    deck.heading("Server certification result", "Two real Android emulators, deployed metadata API, deployed stateless relay.")
    expected = result["expected"]
    cards = [
        (str(expected["sales_per_register"]), "sales per register"),
        (str(expected["customers_per_register"]), "customers per register"),
        (str(expected["items_per_register"]), "isolated items per shop"),
        (str(expected["pending_per_register"]), "pending at finish"),
    ]
    for index, (value, label) in enumerate(cards):
        x = 42 + index * 195
        deck.card(x, 315, 170, 120, fill=SAGE_LIGHT if index < 3 else TEAL_LIGHT)
        deck.canvas.setFillColor(TEAL)
        deck.canvas.setFont(FONT_BOLD, 30)
        deck.canvas.drawCentredString(x + 85, 370, value)
        deck.text(label, x + 20, 340, 130, 30, size=9.5, color=MUTED, align=1)
    audit_counts = audit["counts"]
    deck.card(42, 120, 758, 150, fill=white)
    deck.label("RAW SQL STORAGE AUDIT", 66, 226)
    x = 68
    for table in ("Neuradix Product", "Neuradix Customer", "Neuradix Sale", "Neuradix Sale Item"):
        deck.canvas.setFillColor(TEAL_DARK)
        deck.canvas.setFont(FONT_BOLD, 17)
        deck.canvas.drawString(x, 181, str(audit_counts[table]))
        deck.text(table, x, 163, 150, 34, size=8.8, color=MUTED)
        x += 180

    deck.page("Release Gates")
    deck.heading("Release gates and operational limits", "The tested scope is green; the production hardening backlog remains explicit.")
    deck.card(42, 104, 360, 360, fill=SAGE_LIGHT)
    deck.label("PASSING GATES", 66, 417, fill=white)
    deck.bullet_list(
        [
            "Backend and connector regressions",
            "Flutter format, analysis, unit, repository, and widget tests",
            "Deterministic two-register matrix",
            "ADB server/emulator matrix",
            "Raw SQL no-operational-storage audit",
            "PDF rendering and content validation",
        ],
        66,
        374,
        300,
        size=10.5,
        gap=9,
    )
    deck.card(430, 104, 370, 360, fill=white)
    deck.label("PRODUCTION HARDENING", 454, 417)
    deck.bullet_list(
        [
            "HTTPS and WSS endpoints",
            "Relay supervision, monitoring, and revocation runbook",
            "QR camera pairing and operator PINs",
            "SQLCipher and managed device backup policy",
            "Snapshot/anti-entropy recovery",
            "Explicit warning: total device loss is unrecoverable",
        ],
        454,
        374,
        310,
        size=10.5,
        gap=9,
    )
    deck.finish()
    return path


def main() -> int:
    result = json.loads(RESULT.read_text())
    audit = json.loads(AUDIT.read_text())
    paths = [guide_pdf(result, audit), tech_pdf(result, audit)]
    for path in paths:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
