proc c_read(fd: cint, buf: pointer, count: csize_t): csize_t {.importc: "read", header: "<unistd.h>".}

const STDIN_FILENO = 0.cint

type
    KeyKind* = enum
        nkChar, nkUp, nkDown, nkRight, nkLeft, nkEscape, nkEnter, nkUnknown, nkNone
        
    KeyEvent* = object
        kind*: KeyKind
        ch*: char
        
proc pollKey*(): KeyEvent =
    ## STDINから1バイト読み取り、キーを判定する(ノンブロッキング)
    var buf: array[3, char]
    let bytesRead = c_read(STDIN_FILENO, buf[0].addr, 1)
    
    if bytesRead <= 0:
        return KeyEvent(kind: nkNone)
        
    case buf[0]
    of '\e': # Escape シーケンス(矢印キーなどの判定)
        let b2 = c_read(STDIN_FILENO, buf[1].addr, 1)
        if b2 <= 0: return KeyEvent(kind: nkEscape)
        
        let b3 = c_read(STDIN_FILENO, buf[2].addr, 1)
        if b3 <= 0: return KeyEvent(kind: nkEscape)
        
        if buf[1] == '[':
            case buf[2]
            of 'A': return KeyEvent(kind: nkUp)
            of 'B': return KeyEvent(kind: nkDown)
            of 'C': return KeyEvent(kind: nkRight)
            of 'D': return KeyEvent(kind: nkLeft)
            else: return KeyEvent(kind: nkUnknown)
        return KeyEvent(kind: nkEscape)
        
    of '\r', '\n':
        return KeyEvent(kind: nkEnter)
    else:
        return KeyEvent(kind: nkChar, ch: buf[0])