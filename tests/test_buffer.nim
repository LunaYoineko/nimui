import std/unittest
import std/strutils
import nimact/core/buffer
import nimact/components/widget

suite "nimact Buffer Render Tests":

  test "footer renders at the bottom of the buffer":
    let width = 80
    let height = 24
    let buf = newBuffer(width, height)
    
    let f = footer("Footer Text")
    
    # 最下部 (y = height - 1) にフッターを描画
    f.render(buf, 0, height - 1, width, 1)
    
    var lineText = ""
    for x in 0 ..< width:
        lineText &= buf.getCell(x, height - 1).ch
        
    echo "Rendered Footer Line: '", lineText, "'"

    check "Footer Text" in lineText

  test "drawString handles text rendering correctly":
    let buf = newBuffer(20, 5)
    buf.drawString(2, 1, "Nim", style(fg = colGreen))

    # (x=2, y=1) から順に文字を検証
    check buf.getCell(2, 1).ch == "N"
    check buf.getCell(3, 1).ch == "i"
    check buf.getCell(4, 1).ch == "m"

  test "getCell returns default cell for out-of-bounds coordinates":
    let buf = newBuffer(10, 10)
    # 範囲外アクセスでもクラッシュせずに安全な値が返るか検証
    check buf.getCell(-1, 0).ch == " "
    check buf.getCell(100, 100).ch == " "