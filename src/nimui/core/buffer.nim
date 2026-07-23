type
    Color* = object
        r*, g*, b*: uint8
        isDefault*: bool

proc rgb*(r, g, b: uint8): Color =
    Color(r: r, g: g, b: b, isDefault: false)

proc defaultColor*(): Color =
    Color(isDefault: true)

const
  colBgDark*     = Color(r: 30,  g: 34,  b: 42,  isDefault: false)
  colBgCard*     = Color(r: 40,  g: 44,  b: 52,  isDefault: false)
  colBgFocus*    = Color(r: 50,  g: 56,  b: 66,  isDefault: false)
  colBlue*       = Color(r: 97,  g: 175, b: 239, isDefault: false)
  colPurple*     = Color(r: 198, g: 120, b: 221, isDefault: false)
  colGreen*      = Color(r: 152, g: 195, b: 121, isDefault: false)
  colYellow*     = Color(r: 229, g: 192, b: 123, isDefault: false)
  colRed*        = Color(r: 224, g: 108, b: 117, isDefault: false)
  colCyan*       = Color(r: 86,  g: 182, b: 194, isDefault: false)
  colText*       = Color(r: 220, g: 223, b: 228, isDefault: false)
  colTextMuted*  = Color(r: 92,  g: 99,  b: 112, isDefault: false)
  colWhite*      = Color(r: 255, g: 255, b: 255, isDefault: false)

type
    Style* = object
        fg*: Color
        bg*: Color
        bold*: bool
        dim*: bool

proc style*(fg: Color = defaultColor(), bg: Color = defaultColor(), bold: bool = false, dim: bool = false): Style =
    Style(fg: fg, bg: bg, bold: bold, dim: dim)

type
    Cell* = object
        ch*: string
        style*: Style

    BufferObj* = object
        width*, height*: int
        cells*: seq[Cell]

    Buffer* = ref BufferObj

proc newCell*(ch: string = " ", style: Style = style()): Cell =
    Cell(ch: ch, style: style)

proc newBuffer*(width, height: int): Buffer =
    let size = width * height
    var cells = newSeq[Cell](size)
    for i in 0 ..< size:
        cells[i] = newCell()
    Buffer(width: width, height: height, cells: cells)

proc setCell*(buf: Buffer, x, y: int, cell: Cell) =
    if x >= 0 and x < buf.width and y >= 0 and y < buf.height:
        buf.cells[y * buf.width + x] = cell

proc drawString*(buf: Buffer, x, y: int, str: string, style: Style = style()) =
    var currX = x
    for rune in str:
        if currX >= buf.width: break
        buf.setCell(currX, y, newCell($rune, style))
        currX.inc

type BorderStyle* = enum
    bsSingle, bsDouble, bsRounded, bsBold

proc drawBox*(buf: Buffer, x, y, w, h: int, style: Style = style(), borderType: BorderStyle = bsRounded) =
    let (tl, tr, bl, br, hz, vt) = case borderType
    of bsRounded: ("╭", "╮", "╰", "╯", "─", "│")
    of bsDouble:  ("╔", "╗", "╚", "╝", "═", "║")
    of bsBold:    ("┏", "┓", "┗", "┛", "━", "┃")
    else:         ("┌", "┐", "└", "┘", "─", "│")

    buf.setCell(x, y, newCell(tl, style))
    buf.setCell(x + w - 1, y, newCell(tr, style))
    buf.setCell(x, y + h - 1, newCell(bl, style))
    buf.setCell(x + w - 1, y + h - 1, newCell(br, style))

    for cx in (x + 1) ..< (x + w - 1):
        buf.setCell(cx, y, newCell(hz, style))
        buf.setCell(cx, y + h - 1, newCell(hz, style))

    for cy in (y + 1) ..< (y + h - 1):
        buf.setCell(x, cy, newCell(vt, style))
        buf.setCell(x + w - 1, cy, newCell(vt, style))

    for cy in (y + 1) ..< (y + h - 1):
        for cx in (x + 1) ..< (x + w - 1):
            buf.setCell(cx, cy, newCell(" ", style))
