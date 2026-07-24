## =============================================================================
## nimact/components/widget.nim
## このモジュールは以下の機能を提供する:
##   - Widget型: UIコンポーネントのツリー構造を定義する
##   - ビルダーproc: 各コンポーネントを簡単に生成する関数群
##   - measure: ウィジェットのサイズを計算する (レイアウト用)
##   - render: ウィジェットをバッファに描画する
##
## ウィジェットの種類:
##   - Label:      テキスト表示
##   - VBox:       縦並びレイアウト (子を上から順に配置)
##   - HBox:       横並びレイアウト (子を左から順に配置)
##   - Center:     中央寄せボックス
##   - Header:     画面上部の全幅バー
##   - Footer:     画面下部の全幅バー
##   - Progress:   プログレスバー
##   - Separator:  区切り線
##   - Spacer:     空白スペース
##
## レイアウトの仕組み:
##   1. measure() で各ウィジェットの必要サイズを再帰的に計算
##   2. render() で計算されたサイズと位置に基づいてバッファに描画
##   3. 親ウィジェット (VBox, HBox等) が子の配置位置を計算して渡す
##
## 注意: varargs には do-block notation が使えない (Nimの制約)
##       正しい呼び出し形式: vbox(label("a"), label("b"))
## =============================================================================

import std/unicode  # runeLen でUnicode文字列の幅を計算するために使用
import ../core/buffer

# =============================================================================
# ウィジェットの型定義
# =============================================================================

type
  ## ウィジェットの種類を定義する列挙型
  ## Variant object の discriminant (判別値) として使用する
  WidgetKind* = enum
    wkLabel,      ## テキスト表示
    wkVBox,       ## 縦並びコンテナ
    wkHBox,       ## 横並びコンテナ
    wkCenter,     ## 中央寄せボックス
    wkHeader,     ## ヘッダーバー (全幅)
    wkFooter,     ## フッターバー (全幅)
    wkProgress,   ## プログレスバー
    wkSeparator,  ## 区切り線
    wkSpacer      ## 空白スペース

  ## ウィジェット本体 (Variant Object)
  ##
  ## kind フィールドの値に応じて、保持するフィールドが変わる:
  ##   wkLabel     → labelText, labelStyle
  ##   wkVBox/HBox → children (子ウィジェット列), gap (隙間)
  ##   wkCenter    → centerW, centerH, centerChildren
  ##   wkHeader/F  → barText, barStyle
  ##   wkProgress  → progressValue, progressMax, progressStyle
  ##   wkSeparator → sepStyle
  ##   wkSpacer    → spacerHeight
  Widget* = ref object
    case kind*: WidgetKind
    of wkLabel:
      labelText*: string      ## 表示するテキスト
      labelStyle*: Style      ## テキストの装飾スタイル
    of wkVBox, wkHBox:
      children*: seq[Widget]  ## 子ウィジェットのリスト
      gap*: int               ## 子同士の隙間 (行数/列数)
    of wkCenter:
      centerW*, centerH*: int           ## ボックスの幅と高さ
      centerChildren*: seq[Widget]      ## 中心に配置する子ウィジェット
    of wkHeader, wkFooter:
      barText*: string        ## バーに表示するテキスト
      barStyle*: Style        ## バーの装飾スタイル
    of wkProgress:
      progressValue*: float   ## 現在値
      progressMax*: float     ## 最大値
      progressStyle*: Style   ## バーの装飾スタイル
    of wkSeparator:
      sepStyle*: Style        ## 区切り線の装飾スタイル
    of wkSpacer:
      spacerHeight*: int      ## 空白の高さ (行数)

# =============================================================================
# ビルダー関数: 各コンポーネントを簡単に生成する
# =============================================================================

## テキストラベルを作成する
## text: 表示テキスト
## fg: 前景色 (文字色)、bg: 背景色、bold: 太字
## 使用例: label("Hello", fg = colGreen, bold = true)
proc label*(text: string, fg: Color = defaultColor(),
            bg: Color = defaultColor(), bold: bool = false): Widget =
  Widget(kind: wkLabel, labelText: text, labelStyle: style(fg, bg, bold))

## 縦並びコンテナを作成する (隙間なし)
## 子ウィジェットを上から順に配置する
## 使用例: vbox(label("1行目"), label("2行目"))
proc vbox*(children: varargs[Widget]): Widget =
  Widget(kind: wkVBox, children: @children, gap: 0)

## 縦並びコンテナを作成する (隙間あり)
## gap: 子同士の隙間 (行数)
## 使用例: vbox(1, label("a"), label("b"))  # 1行空ける
proc vbox*(gap: int, children: varargs[Widget]): Widget =
  Widget(kind: wkVBox, children: @children, gap: gap)

## 横並びコンテナを作成する (隙間なし)
## 子ウィジェットを左から順に配置する
## 使用例: hbox(label("左"), label("右"))
proc hbox*(children: varargs[Widget]): Widget =
  Widget(kind: wkHBox, children: @children, gap: 0)

## 横並びコンテナを作成する (隙間あり)
## gap: 子同士の隙間 (列数)
## 使用例: hbox(2, label("A"), label("B"))  # 2列空ける
proc hbox*(gap: int, children: varargs[Widget]): Widget =
  Widget(kind: wkHBox, children: @children, gap: gap)

## 中央寄せボックスを作成する
## w, h: ボックスの幅と高さ
## 子ウィジェットはこのボックス内で水平・垂直に中央寄せされる
## 使用例: center(40, 10, label("中央に表示"))
proc center*(w, h: int, children: varargs[Widget]): Widget =
  Widget(kind: wkCenter, centerW: w, centerH: h, centerChildren: @children)

## ヘッダーバーを作成する (画面上部の全幅バー)
## テキストは左寄せ + 2文字のパディングで表示される
## 使用例: header("アプリ名", fg = colWhite, bg = colBlue, bold = true)
proc header*(text: string, fg: Color = defaultColor(),
             bg: Color = defaultColor(), bold: bool = false): Widget =
  Widget(kind: wkHeader, barText: text, barStyle: style(fg, bg, bold))

## フッターバーを作成する (画面下部の全幅バー)
## ヘッダーと同様に、テキストは左寄せ + 2文字パディング
## 使用例: footer("Q: Quit", fg = colTextMuted, bg = colBgDark)
proc footer*(text: string, fg: Color = defaultColor(),
             bg: Color = defaultColor(), bold: bool = false): Widget =
  Widget(kind: wkFooter, barText: text, barStyle: style(fg, bg, bold))

## プログレスバーを作成する
## value: 現在値, max: 最大値 (デフォルト1.0 = 100%)
## バー幅は親から渡される width - 4 (左右2文字ずつのパディング) で描画される
## 使用例: progress(0.75)  # 75%表示
proc progress*(value: float, max: float = 1.0,
               fg: Color = defaultColor(), bg: Color = defaultColor()): Widget =
  Widget(kind: wkProgress, progressValue: value, progressMax: max,
         progressStyle: style(fg, bg))

## 区切り線を作成する
## 水平な罫線 (─) を全幅に描画する
## 使用例: separator(fg = colTextMuted)
proc separator*(fg: Color = defaultColor(), bg: Color = defaultColor()): Widget =
  Widget(kind: wkSeparator, sepStyle: style(fg, bg))

## 空白スペースを作成する
## height: 空白の高さ (行数、デフォルト1)
## 使用例: spacer(2)  # 2行分の空白
proc spacer*(height: int = 1): Widget =
  Widget(kind: wkSpacer, spacerHeight: height)

# =============================================================================
# サイズ計算 (measure)
# =============================================================================

## ウィジェットが必要とするサイズ (幅, 高さ) を計算する
##
## availableWidth: 親から渡される利用可能幅
##   各ウィジェットはこの幅内でサイズを計算する
##
## 戻り値: (必要幅, 必要高さ) のタプル
##
## 各ウィジェットの計算ロジック:
##   - Label:     テキストのラーン数 x 1行
##   - VBox:      全子の高さの合計 + 隙間、幅は子の最大幅
##   - HBox:      全子の幅の合計 + 隙間、高さは子の最大高さ
##   - Center:   指定した (centerW, centerH)、子が大きい場合は拡張
##   - Header/Footer: 利用可能幅 x 1行
##   - Progress:  利用可能幅 x 1行
##   - Separator: 利用可能幅 x 1行
##   - Spacer:    0 x 指定した高さ
proc measure*(w: Widget, availableWidth: int): (int, int) =
  case w.kind
  of wkLabel:
    var wCount = 0
    for r in w.labelText.runes:
        wCount += runeWidth(r)
    (wCount, 1)
  of wkVBox:
    # 子を縦に積むので、高さは合計、幅は最大値
    var totalH = 0
    var maxW = 0
    for i, child in w.children:
      let (cw, ch) = child.measure(availableWidth)
      maxW = max(maxW, cw)
      totalH += ch
      if i > 0: totalH += w.gap  # 2子目以降に隙間を追加
    (maxW, totalH)
  of wkHBox:
    # 子を横に並べるので、幅は合計、高さは最大値
    var totalW = 0
    var maxH = 0
    for i, child in w.children:
      let (cw, ch) = child.measure(availableWidth)
      if i > 0: totalW += w.gap  # 2子目以降に隙間を追加
      totalW += cw
      maxH = max(maxH, ch)
    (totalW, maxH)
  of wkCenter:
    # 子の高さを合計して、指定高さと比較して大きい方を返す
    var totalChildH = 0
    for child in w.centerChildren:
      let (_, ch) = child.measure(w.centerW)
      totalChildH += ch
    (w.centerW, max(w.centerH, totalChildH))
  of wkHeader, wkFooter:
    # 全幅を占有し、高さは1行
    (availableWidth, 1)
  of wkProgress:
    (availableWidth, 1)
  of wkSeparator:
    (availableWidth, 1)
  of wkSpacer:
    # 幅は0、高さは指定値
    (0, w.spacerHeight)

# =============================================================================
# 描画 (render)
# =============================================================================

## ウィジェットをバッファに描画する
##
## buf: 描画先のバッファ
## x, y: 描画開始座標 (バッファの左上を原点とする)
## width, height: 親から渡された利用可能サイズ
##
## 各ウィジェットの描画ロジック:
##   - Label:     各ラーンを1文字ずつ setCell で配置
##   - VBox:      子を上から順に描画 (高さを measure してから配置)
##   - HBox:      子を左から順に描画 (幅を measure してから配置)
##   - Center:    指定サイズで中央寄せオフセットを計算し、子を配置
##   - Header/F:  全幅を背景色で塗り、テキストを2文字パディングで描画
##   - Progress:  塗り済み部分 (█) と未塗り部分 (░) を描画
##   - Separator: 全幅に ─ を描画
##   - Spacer:    何も描画しない (空間を確保するだけ)
proc render*(w: Widget, buf: Buffer, x, y, width, height: int) =
  case w.kind
  of wkLabel:
    buf.drawString(x, y, w.labelText, w.labelStyle)

  of wkVBox:
    # 子ウィジェットを上から順に配置
    var cy = y
    for child in w.children:
      let (_, ch) = child.measure(width)  # 子の高さを取得
      child.render(buf, x, cy, width, ch)  # 子を描画
      cy += ch + w.gap  # 次の子の配置位置を計算 (高さ + 隙間)

  of wkHBox:
    # 子ウィジェットを左から順に配置
    var cx = x
    for i, child in w.children:
      if i > 0: cx += w.gap  # 2子目以降に隙間を空ける
      let (cw, ch) = child.measure(width)  # 子のサイズを取得
      child.render(buf, cx, y, cw, ch)     # 子を描画
      cx += cw  # 次の子の配置位置を計算

  of wkCenter:
    # 子ウィジェットをボックス内で中央寄せに配置
    # まず子の合計高さを計算
    var totalChildH = 0
    for child in w.centerChildren:
      let (_, ch) = child.measure(w.centerW)
      totalChildH += ch
    # 実際のボックス高さ (指定値と子の合計の大きい方)
    let innerH = max(w.centerH, totalChildH)
    # 水平・垂直のオフセットを計算 (中央寄せ)
    let offsetX = (width - w.centerW) div 2
    let offsetY = (height - innerH) div 2
    # 子を縦に積んで描画
    var cy = 0
    for child in w.centerChildren:
      let (_, ch) = child.measure(w.centerW)
      child.render(buf, x + offsetX, y + offsetY + cy, w.centerW, ch)
      cy += ch

  of wkHeader:
    # 全幅を背景色で塗りつぶす
    for cx in 0 ..< width:
      if x + cx < buf.width:
        buf.setCell(x + cx, y, newCell(" ", w.barStyle))
    buf.drawString(x + 2, y, w.barText, w.barStyle)

  of wkFooter:
    # ヘッダーと同様の描画 (全幅背景 + テキスト)
    for cx in 0 ..< width:
      if x + cx < buf.width:
        buf.setCell(x + cx, y, newCell(" ", w.barStyle))
    buf.drawString(x + 2, y, w.barText, w.barStyle)

  of wkProgress:
    # プログレスバーの描画
    # 左右2文字ずつパディングがあるので、実効幅は width - 4
    let barW = max(0, width - 4)
    # 現在値/最大値 の比率を計算
    let ratio = if w.progressMax > 0: w.progressValue / w.progressMax else: 0.0
    # 塗り済み部分の文字数
    let filled = (ratio * barW.float).int
    # 各位置に █ (塗り済み) または ░ (未塗り) を配置
    for i in 0 ..< barW:
      let ch = if i < filled: "█" else: "░"
      buf.setCell(x + 2 + i, y, newCell(ch, w.progressStyle))

  of wkSeparator:
    # 全幅に ─ (水平線) を描画
    for cx in 0 ..< width:
      if x + cx < buf.width:
        buf.setCell(x + cx, y, newCell("─", w.sepStyle))

  of wkSpacer:
    # 何も描画しない (空間を確保するだけ)
    discard
