import ./buffer

type
    CTermios* {.importc: "struct termios", header: "<termios.h>".} = object
        c_iflag*: uint32
        c_oflag*: uint32
        c_cflag*: uint32
        c_lflag*: uint32
        c_cc*: array[32, uint8]

const
    STDIN_FILENO* = 0.cint
    TCSAFLUSH* = 2.cint

var
    ECHO* {.importc: "ECHO", header: "<termios.h>".}: uint32
    ICANON* {.importc: "ICANON", header: "<termios.h>".}: uint32
    IEXTEN* {.importc: "IEXTEN", header: "<termios.h>".}: uint32
    ISIG* {.importc: "ISIG", header: "<termios.h>".}: uint32
    BRKINT* {.importc: "BRKINT", header: "<termios.h>".}: uint32
    ICRNL* {.importc: "ICRNL", header: "<termios.h>".}: uint32
    INPCK* {.importc: "INPCK", header: "<termios.h>".}: uint32
    ISTRIP* {.importc: "ISTRIP", header: "<termios.h>".}: uint32
    IXON* {.importc: "IXON", header: "<termios.h>".}: uint32
    OPOST* {.importc: "OPOST", header: "<termios.h>".}: uint32
    CS8* {.importc: "CS8", header: "<termios.h>".}: uint32

    VMIN* {.importc: "VMIN", header: "<termios.h>".}: cint
    VTIME* {.importc: "VTIME", header: "<termios.h>".}: cint

proc tcgetattr*(fd: cint, termios_p: ptr CTermios): cint {.importc: "tcgetattr", header: "<termios.h>".}
proc tcsetattr*(fd: cint, optional_actions: cint, termios_p: ptr CTermios): cint {.importc: "tcsetattr", header: "<termios.h>".}

var origTermios: CTermios

proc enableRawMode*() =
    if tcgetattr(STDIN_FILENO, origTermios.addr) < 0:
        return
    var raw = origTermios
    raw.c_lflag = raw.c_lflag and not (ECHO or ICANON or IEXTEN or ISIG)
    raw.c_iflag = raw.c_iflag and not (BRKINT or ICRNL or INPCK or ISTRIP or IXON)
    raw.c_cflag = raw.c_cflag or CS8
    raw.c_oflag = raw.c_oflag and not (OPOST)
    raw.c_cc[VMIN] = 0
    raw.c_cc[VTIME] = 1
    discard tcsetattr(STDIN_FILENO, TCSAFLUSH, raw.addr)
    stdout.write("\e[?1049h\e[?25l")
    stdout.flushFile()

proc disableRawMode*() =
    stdout.write("\e[?25h\e[?1049l")
    stdout.flushFile()
    discard tcsetattr(STDIN_FILENO, TCSAFLUSH, origTermios.addr)

proc clearScreen*() =
    stdout.write("\e[2J")
    stdout.flushFile()

type Winsize {.importc: "struct winsize", header: "<sys/ioctl.h>".} = object
    ws_row, ws_col, ws_xpixel, ws_ypixel: uint16

var TIOCGWINSZ {.importc: "TIOCGWINSZ", header: "<sys/ioctl.h>".}: culong
proc ioctl(fd: cint, request: culong, arg: pointer): cint {.importc: "ioctl", header: "<sys/ioctl.h>".}

proc getTerminalSize*(): (int, int) =
    var ws: Winsize
    if ioctl(STDIN_FILENO, TIOCGWINSZ, ws.addr) == 0 and ws.ws_col > 0:
        return (ws.ws_col.int, ws.ws_row.int)
    return (80, 24)

proc ansiStyle(s: Style): string =
    var res = "\e[0m"
    if s.bold: res.add("\e[1m")
    if s.dim: res.add("\e[2m")
    if not s.fg.isDefault:
        res.add("\e[38;2;" & $s.fg.r & ";" & $s.fg.g & ";" & $s.fg.b & "m")
    if not s.bg.isDefault:
        res.add("\e[48;2;" & $s.bg.r & ";" & $s.bg.g & ";" & $s.bg.b & "m")
    return res

proc renderDiff*(current, next: Buffer) =
    var outBuf = ""
    for y in 0 ..< next.height:
        for x in 0 ..< next.width:
            let idx = y * next.width + x
            let cCell = if idx < current.cells.len: current.cells[idx] else: newCell()
            let nCell = next.cells[idx]
            if cCell != nCell:
                outBuf.add("\e[" & $(y + 1) & ";" & $(x + 1) & "H")
                outBuf.add(ansiStyle(nCell.style))
                outBuf.add(nCell.ch)
    if outBuf.len > 0:
        stdout.write(outBuf)
        stdout.flushFile()
