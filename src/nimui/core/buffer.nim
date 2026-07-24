## =============================================================================
## nimui/core/buffer.nim
## TUIフレームワークのバッファ・描画プリミティブを定義するモジュール
##
## このモジュールは以下の機能を提供する:
##   - Color: TrueColor (24bit) の色表現
##   - Style: 文字の装飾情報（前景色・背景色・太字・暗転）
##   - Cell: 1文字分の描画情報（文字 + スタイル）
##   - Buffer: 画面全体を表す2次元セル配列
##   - drawString / drawBox: 低レベル描画関数
##
## 典型的な使い方:
##   let buf = newBuffer(80, 24)
##   buf.drawString(0, 0, "Hello", style(fg = colGreen))
##   buf.drawBox(5, 3, 20, 10, style(fg = colBlue))
## =============================================================================

# =============================================================================
# Color型: TrueColor (24bit RGB) を表現する
# =============================================================================
type
    Color* = object
        r*, g*, b*: uint8       ## RGB各チャンネル (0-255)
        isDefault*: bool        ## trueの場合、ターミナルのデフォルト色を使用

## RGB値からColorを作成する
## 使用例: let c = rgb(255, 128, 0)  # オレンジ
proc rgb*(r, g, b: uint8): Color =
    Color(r: r, g: g, b: b, isDefault: false)

## ターミナルのデフォルト色を返す
## isDefault = true のColorはANSIエスケープシーケンスで出力されない
proc defaultColor*(): Color =
    Color(isDefault: true)

# =============================================================================
# 組み込みカラーパレット (Nord / OneDark / Dracula ベース)
# =============================================================================
const
  # --- ダーク系背景色 ---
  colBgDark*     = Color(r: 30,  g: 34,  b: 42,  isDefault: false) ## メイン背景 (#1e222a)
  colBgCard*     = Color(r: 40,  g: 44,  b: 52,  isDefault: false) ## カード/パネル背景 (#282c34)
  colBgFocus*    = Color(r: 50,  g: 56,  b: 66,  isDefault: false) ## フォーカス時の背景 (#323842)

  # --- アクセントカラー ---
  colBlue*       = Color(r: 97,  g: 175, b: 239, isDefault: false) ## 青 (Nord/OneDark Blue #61afef)
  colPurple*     = Color(r: 198, g: 120, b: 221, isDefault: false) ## 紫 (Dracula Purple #c678dd)
  colGreen*      = Color(r: 152, g: 195, b: 121, isDefault: false) ## 緑 (ソフトグリーン #98c379)
  colYellow*     = Color(r: 229, g: 192, b: 123, isDefault: false) ## 黄 (ウォームイエロー #e5c07b)
  colRed*        = Color(r: 224, g: 108, b: 117, isDefault: false) ## 赤 (ソフトレッド #e06c75)
  colCyan*       = Color(r: 86,  g: 182, b: 194, isDefault: false) ## シアン (#56b6c2)

  # --- テキスト色 ---
  colText*       = Color(r: 220, g: 223, b: 228, isDefault: false) ## メインテキスト (#dcdfe4)
  colTextMuted*  = Color(r: 92,  g: 99,  b: 112, isDefault: false) ## 薄いテキスト (#5c6370)
  colWhite*      = Color(r: 255, g: 255, b: 255, isDefault: false) ## 純白

# =============================================================================
# Style型: 文字の装飾スタイルを定義する
# =============================================================================
type
    Style* = object
        fg*: Color    ## 前景色 (文字色)
        bg*: Color    ## 背景色
        bold*: bool   ## 太字にするかどうか (ANSI SGR: \e[1m)
        dim*: bool    ## 暗く表示するかどうか (ANSI SGR: \e[2m)
        italic*: bool ## 斜体 (ANSI: \e[3m)
        underline*: bool ## 下線 (ANSI: \e[4m)
        reverse*: bool ## 反転 (ANSI: \e[7m)

## Styleを作成するユーティリティ関数
## 全パラメータはオプションで、未指定時はデフォルト値が使われる
## 使用例:
##   style(fg = colGreen, bold = true)
##   style(fg = colRed, bg = colBgCard)
proc style*(fg: Color = defaultColor(), bg: Color = defaultColor(),
            bold: bool = false, dim: bool = false, italic: bool = false, underline: bool = false, reverse: bool = false): Style =
    Style(fg: fg, bg: bg, bold: bold, dim: dim, italic: italic, underline: underline, reverse: reverse)

# =============================================================================
# Cell型: バッファ内の1マスを表す
# =============================================================================
type
    Cell* = object
        ch*: string     ## 表示する1文字 (Unicode対応のためstring型)
        style*: Style   ## その文字の装飾スタイル

    ## Bufferの本体オブジェクト (refではなく値型として定義)
    BufferObj* = object
        width*, height*: int   ## バッファの幅と高さ (ピクセルではなく文字数)
        cells*: seq[Cell]      ## セル配列 (row-major: cells[y * width + x])

    ## Bufferの参照型 (heap確保してポインタ渡しにする)
    Buffer* = ref BufferObj

## 新しいCellを作成する
## ch: 表示文字 (デフォルトはスペース)
## style: 装飾スタイル (デフォルトはデフォルトスタイル)
proc newCell*(ch: string = " ", style: Style = style()): Cell =
    Cell(ch: ch, style: style)

## 新しいバッファを作成する
## 指定された幅x高さのセル配列を確保し、全セルをスペースで初期化する
## 使用例: let buf = newBuffer(80, 24)  # 80列 x 24行のバッファ
proc newBuffer*(width, height: int): Buffer =
    let size = width * height
    var cells = newSeq[Cell](size)
    for i in 0 ..< size:
        cells[i] = newCell()
    Buffer(width: width, height: height, cells: cells)

## バッファの指定位置にセルを設定する
## 範囲外の座標は無視される (安全に呼び出せる)
## 座標系: (0, 0) が左上、x が横方向、y が縦方向
proc setCell*(buf: Buffer, x, y: int, cell: Cell) =
    if x >= 0 and x < buf.width and y >= 0 and y < buf.height:
        buf.cells[y * buf.width + x] = cell

        
## 指定位置のCellを取得する(範囲外なら安全に空セルを返す)
proc getCell*(buf: Buffer, x, y: int): Cell =
    if x >= 0 and x < buf.width and y >= 0 and y < buf.height:
        return buf.cells[y * buf.width + x]
    else:
        return newCell()
# =============================================================================
# 低レベル描画関数
# =============================================================================

## バッファに文字列を描画する (低レベルAPI)
## x, y: 描画開始座標
## str: 描画する文字列 (Unicode対応)
## style: 文字の装飾スタイル
## 画面右端を超える文字は切り捨てられる
import unicode

## 簡易的な文字幅判定
proc runeWidth*(r: Rune): int =
    let cp = r.int
    if (cp >= 0x1100 and cp <= 0x115F) or # Hangul Jamo
        (cp >= 0x2E80 and cp <= 0xA4CF) or # CJK Radicals, Kanji, etc.
        (cp >= 0xAC00 and cp <= 0xD7A3) or # Hangul Syllables
        (cp >= 0xF900 and cp <= 0xFAFF) or # CJK Compatibility
        (cp >= 0xFE10 and cp <= 0xFE19) or # Vertical forms
        (cp >= 0xFF01 and cp <= 0xFF60) or # Fullwidth Form
        (cp >= 0xFFE0 and cp <= 0xFFE6) or
        (cp >= 0x1F300 and cp <= 0x1F64F): # Emoji
        return 2
    else:
        return 1

proc drawString*(buf: Buffer, x, y: int, str: string, style: Style = style()) =
    var currX = x
    for rune in str.runes:
        if currX >= buf.width: break
        
        let w = runeWidth(rune)
        buf.setCell(currX, y, newCell($rune, style))
        
        # 幅が2の場合は、隣のセルを空文字で埋めて崩れを防ぐ
        if w == 2 and currX + 1 < buf.width:
            buf.setCell(currX + 1, y, newCell("", style)) # 結合用ダミー
            
        currX += w # 文字幅分進める(1 または 2)

# =============================================================================
# ボーダースタイル: drawBoxで使用する罫線の種類
# =============================================================================
type BorderStyle* = enum
    bsSingle,   ## ┌┐└┘─│ (シングルライン)
    bsDouble,   ## ╔╗╚╝═║ (ダブルライン)
    bsRounded,  ## ╭╮╰╯─│ (角丸) -- デフォルト
    bsBold      ## ┏┓┗┛━┃ (太線)

## バッファにボックス(矩形枠)を描画する (低レベルAPI)
## x, y: ボックスの左上座標
## w, h: ボックスの幅と高さ (枠線を含む)
## style: 枠線と内部の装飾スタイル
## borderType: 罫線の種類
##
## 描画内容:
##   1. 四隅の角文字を配置
##   2. 上下の水平線を描画
##   3. 左右の垂直線を描画
##   4. 内部をスペースで塗りつぶし
proc drawBox*(buf: Buffer, x, y, w, h: int, style: Style = style(),
              borderType: BorderStyle = bsRounded) =
    # ボーダースタイルに応じた文字を選択
    # (tl=左上, tr=右上, bl=左下, br=右下, hz=水平, vt=垂直)
    let (tl, tr, bl, br, hz, vt) = case borderType
    of bsRounded: ("╭", "╮", "╰", "╯", "─", "│")
    of bsDouble:  ("╔", "╗", "╚", "╝", "═", "║")
    of bsBold:    ("┏", "┓", "┗", "┛", "━", "┃")
    else:         ("┌", "┐", "└", "┘", "─", "│")

    # 四隅を描画
    buf.setCell(x, y, newCell(tl, style))                    # 左上
    buf.setCell(x + w - 1, y, newCell(tr, style))            # 右上
    buf.setCell(x, y + h - 1, newCell(bl, style))            # 左下
    buf.setCell(x + w - 1, y + h - 1, newCell(br, style))   # 右下

    # 上辺・下辺の水平線を描画 (角と角の間)
    for cx in (x + 1) ..< (x + w - 1):
        buf.setCell(cx, y, newCell(hz, style))
        buf.setCell(cx, y + h - 1, newCell(hz, style))

    # 左辺・右辺の垂直線を描画 (角と角の間)
    for cy in (y + 1) ..< (y + h - 1):
        buf.setCell(x, cy, newCell(vt, style))
        buf.setCell(x + w - 1, cy, newCell(vt, style))

    # ボックス内部をスペースで塗りつぶし (背景色を反映させるため)
    for cy in (y + 1) ..< (y + h - 1):
        for cx in (x + 1) ..< (x + w - 1):
            buf.setCell(cx, cy, newCell(" ", style))
