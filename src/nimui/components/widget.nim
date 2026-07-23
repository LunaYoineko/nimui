import std/unicode
import ../core/buffer

type
  WidgetKind* = enum
    wkLabel, wkVBox, wkHBox, wkCenter, wkHeader, wkFooter, wkProgress, wkSeparator, wkSpacer

  Widget* = ref object
    case kind*: WidgetKind
    of wkLabel:
      labelText*: string
      labelStyle*: Style
    of wkVBox, wkHBox:
      children*: seq[Widget]
      gap*: int
    of wkCenter:
      centerW*, centerH*: int
      centerChildren*: seq[Widget]
    of wkHeader, wkFooter:
      barText*: string
      barStyle*: Style
    of wkProgress:
      progressValue*: float
      progressMax*: float
      progressStyle*: Style
    of wkSeparator:
      sepStyle*: Style
    of wkSpacer:
      spacerHeight*: int

proc label*(text: string, fg: Color = defaultColor(), bg: Color = defaultColor(), bold: bool = false): Widget =
  Widget(kind: wkLabel, labelText: text, labelStyle: style(fg, bg, bold))

proc vbox*(children: varargs[Widget]): Widget =
  Widget(kind: wkVBox, children: @children, gap: 0)

proc vbox*(gap: int, children: varargs[Widget]): Widget =
  Widget(kind: wkVBox, children: @children, gap: gap)

proc hbox*(children: varargs[Widget]): Widget =
  Widget(kind: wkHBox, children: @children, gap: 0)

proc hbox*(gap: int, children: varargs[Widget]): Widget =
  Widget(kind: wkHBox, children: @children, gap: gap)

proc center*(w, h: int, children: varargs[Widget]): Widget =
  Widget(kind: wkCenter, centerW: w, centerH: h, centerChildren: @children)

proc header*(text: string, fg: Color = defaultColor(), bg: Color = defaultColor(), bold: bool = false): Widget =
  Widget(kind: wkHeader, barText: text, barStyle: style(fg, bg, bold))

proc footer*(text: string, fg: Color = defaultColor(), bg: Color = defaultColor(), bold: bool = false): Widget =
  Widget(kind: wkFooter, barText: text, barStyle: style(fg, bg, bold))

proc progress*(value: float, max: float = 1.0, fg: Color = defaultColor(), bg: Color = defaultColor()): Widget =
  Widget(kind: wkProgress, progressValue: value, progressMax: max, progressStyle: style(fg, bg))

proc separator*(fg: Color = defaultColor(), bg: Color = defaultColor()): Widget =
  Widget(kind: wkSeparator, sepStyle: style(fg, bg))

proc spacer*(height: int = 1): Widget =
  Widget(kind: wkSpacer, spacerHeight: height)

proc measure*(w: Widget, availableWidth: int): (int, int) =
  case w.kind
  of wkLabel:
    (w.labelText.runeLen, 1)
  of wkVBox:
    var totalH = 0
    var maxW = 0
    for i, child in w.children:
      let (cw, ch) = child.measure(availableWidth)
      maxW = max(maxW, cw)
      totalH += ch
      if i > 0: totalH += w.gap
    (maxW, totalH)
  of wkHBox:
    var totalW = 0
    var maxH = 0
    for i, child in w.children:
      let (cw, ch) = child.measure(availableWidth)
      if i > 0: totalW += w.gap
      totalW += cw
      maxH = max(maxH, ch)
    (totalW, maxH)
  of wkCenter:
    var totalChildH = 0
    for child in w.centerChildren:
      let (_, ch) = child.measure(w.centerW)
      totalChildH += ch
    (w.centerW, max(w.centerH, totalChildH))
  of wkHeader, wkFooter:
    (availableWidth, 1)
  of wkProgress:
    (availableWidth, 1)
  of wkSeparator:
    (availableWidth, 1)
  of wkSpacer:
    (0, w.spacerHeight)

proc render*(w: Widget, buf: Buffer, x, y, width, height: int) =
  case w.kind
  of wkLabel:
    var cx = x
    for rune in w.labelText:
      if cx >= buf.width: break
      buf.setCell(cx, y, newCell($rune, w.labelStyle))
      cx.inc
  of wkVBox:
    var cy = y
    for child in w.children:
      let (_, ch) = child.measure(width)
      child.render(buf, x, cy, width, ch)
      cy += ch + w.gap
  of wkHBox:
    var cx = x
    for i, child in w.children:
      if i > 0: cx += w.gap
      let (cw, ch) = child.measure(width)
      child.render(buf, cx, y, cw, ch)
      cx += cw
  of wkCenter:
    var totalChildH = 0
    for child in w.centerChildren:
      let (_, ch) = child.measure(w.centerW)
      totalChildH += ch
    let innerH = max(w.centerH, totalChildH)
    let offsetX = (width - w.centerW) div 2
    let offsetY = (height - innerH) div 2
    var cy = 0
    for child in w.centerChildren:
      let (_, ch) = child.measure(w.centerW)
      child.render(buf, x + offsetX, y + offsetY + cy, w.centerW, ch)
      cy += ch
  of wkHeader:
    for cx in 0 ..< width:
      if x + cx < buf.width:
        buf.setCell(x + cx, y, newCell(" ", w.barStyle))
    var cx = x + 2
    for rune in w.barText:
      if cx >= x + width: break
      buf.setCell(cx, y, newCell($rune, w.barStyle))
      cx.inc
  of wkFooter:
    for cx in 0 ..< width:
      if x + cx < buf.width:
        buf.setCell(x + cx, y, newCell(" ", w.barStyle))
    var cx = x + 2
    for rune in w.barText:
      if cx >= x + width: break
      buf.setCell(cx, y, newCell($rune, w.barStyle))
      cx.inc
  of wkProgress:
    let barW = max(0, width - 4)
    let ratio = if w.progressMax > 0: w.progressValue / w.progressMax else: 0.0
    let filled = (ratio * barW.float).int
    for i in 0 ..< barW:
      let ch = if i < filled: "█" else: "░"
      buf.setCell(x + 2 + i, y, newCell(ch, w.progressStyle))
  of wkSeparator:
    for cx in 0 ..< width:
      if x + cx < buf.width:
        buf.setCell(x + cx, y, newCell("─", w.sepStyle))
  of wkSpacer:
    discard
