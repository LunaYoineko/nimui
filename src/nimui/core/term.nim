## =============================================================================
## nimui/core/term.nim
## ターミナル制御と差分描画エンジンを提供するモジュール
##
## このモジュールは以下の機能を提供する:
##   - Raw Mode: ターミナルをrawモードに切り替える (キー入力を即座に取得)
##   - 代替画面バッファ: メイン画面を傷つけずにTUIを描画する
##   - ターミナルサイズ取得: ioctlを使った端末サイズの取得
##   - 差分描画: 前フレームと比較して変化した部分だけを描画する (高速化)
##
## C言語の POSIX API を直接バインディングして使用している:
##   - <termios.h>: ターミナル属性の制御
##   - <sys/ioctl.h>: デバイス ioctl (ターミナルサイズ取得)
## =============================================================================

import ./buffer

# =============================================================================
# termios 構造体のCバインディング
# POSIX の termios はターミナルの入出力属性を制御するための構造体
# =============================================================================
type
    ## Cの `struct termios` に対応するNim型
    ## ターミナルのフラグや設定を保持する
    CTermios* {.importc: "struct termios", header: "<termios.h>".} = object
        c_iflag*: uint32    ## 入力フラグ (入力処理の制御)
        c_oflag*: uint32    ## 出力フラグ (出力処理の制御)
        c_cflag*: uint32    ## 制御フラグ (通信プロトコルの制御)
        c_lflag*: uint32    ## ローカルフラグ (エコー・カノニカルモード等の制御)
        c_cc*: array[32, uint8]  ## 制御文字配列 (VMIN, VTIME等の特殊文字設定)

const
    STDIN_FILENO* = 0.cint   ## 標準入力のファイルディスクリプタ (常に0)
    TCSAFLUSH* = 2.cint      ## tcsetattrのフラグ: 変更後、保留中の入力を破棄して適用

# =============================================================================
# termios フラグ定数のCバインディング
# これらのフラグは raw モードの設定で使用する
# =============================================================================
var
    # --- ローカル出力フラグ (c_lflag) ---
    ECHO*   {.importc: "ECHO",   header: "<termios.h>".}: uint32  ## タイプした文字をエコー(表示)する
    ICANON* {.importc: "ICANON", header: "<termios.h>".}: uint32  ## カノニカルモード (行バッファリング)
    IEXTEN* {.importc: "IEXTEN", header: "<termios.h>".}: uint32  ## 拡張入力処理
    ISIG*   {.importc: "ISIG",   header: "<termios.h>".}: uint32  ## シグナル生成 (Ctrl+C, Ctrl+Z)

    # --- 入力フラグ (c_iflag) ---
    BRKINT* {.importc: "BRKINT", header: "<termios.h>".}: uint32  ## BRKシグナル
    ICRNL*  {.importc: "ICRNL",  header: "<termios.h>".}: uint32  ## CR→NL変換
    INPCK*  {.importc: "INPCK",  header: "<termios.h>".}: uint32  ## 奇偶チェック
    ISTRIP* {.importc: "ISTRIP", header: "<termios.h>".}: uint32  ## 上位7ビットをクリア
    IXON*   {.importc: "IXON",   header: "<termios.h>".}: uint32  ## XON/XOFFフローコントロール

    # --- 出力フラグ (c_oflag) ---
    OPOST*  {.importc: "OPOST",  header: "<termios.h>".}: uint32  ## 出力後処理 (NL→CRNL変換等)

    # --- 制御フラグ (c_cflag) ---
    CS8*    {.importc: "CS8",    header: "<termios.h>".}: uint32   ## 8ビット文字サイズ

    # --- 制御文字インデックス ---
    VMIN*   {.importc: "VMIN",  header: "<termios.h>".}: cint    ## ノンブロッキング read の最小バイト数
    VTIME*  {.importc: "VTIME", header: "<termios.h>".}: cint    ## ノンブロッキング read のタイムアウト (10ms単位)

# =============================================================================
# termios 操作関数のCバインディング
# =============================================================================

## ターミナル属性を取得する (C: tcgetattr)
## fd: ファイルディスクリプタ (通常は STDIN_FILENO)
## termios_p: 属性を格納する構造体へのポインタ
proc tcgetattr*(fd: cint, termios_p: ptr CTermios): cint
    {.importc: "tcgetattr", header: "<termios.h>".}

## ターミナル属性を設定する (C: tcsetattr)
## fd: ファイルディスクリプタ
## optional_actions: 変更の適用タイミング (TCSAFLUSH = 保留入力破棄後に適用)
## termios_p: 設定する構造体へのポインタ
proc tcsetattr*(fd: cint, optional_actions: cint, termios_p: ptr CTermios): cint
    {.importc: "tcsetattr", header: "<termios.h>".}

# =============================================================================
# Raw Mode 制御
# =============================================================================

## 元のターミナル設定を保存する変数
## disableRawMode で元に戻すために使用する
var origTermios: CTermios

## ターミナルをRaw Modeに切り替える
##
## Raw Modeとは:
##   - エコー無効: タイプした文字が画面に表示されない
##   - カノニカルモード無効: 行バッファリングが無効になり、1文字ずつ即座に入力される
##   - シグナル無効: Ctrl+C, Ctrl+Z がプログラムに届かなくなる
##   - 出力後処理無効: NL→CRNL変換などが無効になる
##
## 処理の流れ:
##   1. 現在のターミナル設定を保存
##   2. 各フラグをオフにして raw モードに設定
##   3. ノンブロッキング読み込み設定 (VMIN=0, VTIME=1)
##   4. 代替画面バッファに切り替え (\e[?1049h)
##   5. カーソルを非表示にする (\e[?25l)
proc enableRawMode*() =
    # 現在のターミナル設定を取得して保存
    if tcgetattr(STDIN_FILENO, origTermios.addr) < 0:
        return  # 取得失敗時は何もしない
    var raw = origTermios

    # ローカルフラグ: エコー・カノニカル・拡張入力・シグナルをオフ
    raw.c_lflag = raw.c_lflag and not (ECHO or ICANON or IEXTEN or ISIG)
    # 入力フラグ: BRKINT・CRNL・奇偶チェック・上位ビットクリア・XON/XOFF をオフ
    raw.c_iflag = raw.c_iflag and not (BRKINT or ICRNL or INPCK or ISTRIP or IXON)
    # 制御フラグ: 8ビット文字サイズを有効化
    raw.c_cflag = raw.c_cflag or CS8
    # 出力フラグ: 出力後処理をオフ
    raw.c_oflag = raw.c_oflag and not (OPOST)

    # ノンブロッキング読み込み設定:
    #   VMIN = 0: read が返す最小バイト数 (0 = データがなくても即座にリターン)
    #   VTIME = 1: タイムアウト (1 = 100ms。データがある場合の最大待ち時間)
    raw.c_cc[VMIN] = 0
    raw.c_cc[VTIME] = 1

    # 設定を適用 (保留中の入力データは破棄)
    discard tcsetattr(STDIN_FILENO, TCSAFLUSH, raw.addr)

    # 代替画面バッファに切り替え (\e[?1049h) してカーソルを非表示 (\e[?25l)
    # 代替バッファを使うことで、元のターミナル画面を傷つけずに描画できる
    stdout.write("\e[?1049h\e[?25l")
    stdout.flushFile()

## ターミナルを元のNormal Modeに戻す
##
## 処理の流れ:
##   1. カーソルを表示する (\e[?25h)
##   2. 通常画面バッファに戻る (\e[?1049l)
##   3. 保存しておいた元の設定を復元
##
## defer: disableRawMode() と組み合わせて使うことで、
## 例外が発生しても確実にターミナルを復元できる
proc disableRawMode*() =
    # カーソル表示 & 通常画面バッファへ復帰
    stdout.write("\e[?25h\e[?1049l")
    stdout.flushFile()
    # 元のターミナル設定を復元
    discard tcsetattr(STDIN_FILENO, TCSAFLUSH, origTermios.addr)

## 画面全体をクリアする
## ANSIエスケープシーケンス \e[2J を使用して画面をクリアする
proc clearScreen*() =
    stdout.write("\e[2J")
    stdout.flushFile()

# =============================================================================
# ターミナルサイズ取得 (ioctl 使用)
# =============================================================================

## Cの `struct winsize` に対応するNim型
## ターミナルのサイズ情報を保持する
type Winsize {.importc: "struct winsize", header: "<sys/ioctl.h>".} = object
    ws_row, ws_col: uint16      ## 行数・列数 (文字単位)
    ws_xpixel, ws_ypixel: uint16  ## ピクセル単位のサイズ (通常は使わない)

## ioctl のリクエストコード (ターミナルサイズ取得用)
var TIOCGWINSZ {.importc: "TIOCGWINSZ", header: "<sys/ioctl.h>".}: culong

## ioctl 関数のCバインディング
## デバイスにコマンドを送信する汎用関数
proc ioctl(fd: cint, request: culong, arg: pointer): cint
    {.importc: "ioctl", header: "<sys/ioctl.h>".}

## ターミナルのサイズを取得する
## 戻り値: (列数, 行数) のタプル
## ioctl が失敗した場合はデフォルト値 (80, 24) を返す
proc getTerminalSize*(): (int, int) =
    var ws: Winsize
    if ioctl(STDIN_FILENO, TIOCGWINSZ, ws.addr) == 0 and ws.ws_col > 0:
        return (ws.ws_col.int, ws.ws_row.int)
    return (80, 24)  # フォールバック: 古いVT100の標準サイズ

# =============================================================================
# ANSIエスケープシーケンス生成
# =============================================================================

## Style構造体をANSIエスケープシーケンス文字列に変換する
##
## 生成されるシーケンス:
##   \e[0m      — すべてのスタイルをリセット
##   \e[1m      — 太字 (Bold)
##   \e[2m      — 暗く表示 (Dim)
##   \e[38;2;R;G;Bm — 前景色をTrueColorで指定
##   \e[48;2;R;G;Bm — 背景色をTrueColorで指定
##
## 注意: 毎回リセット(\e[0m)を先頭に付与しているため、
##       前のセルのスタイルが残らない
proc ansiStyle(s: Style): string =
    var res = "\e[0m"             # まず全スタイルをリセット
    if s.bold: res.add("\e[1m")   # 太字
    if s.dim: res.add("\e[2m")    # 暗く表示
    # TrueColor前景色 (38;2;R;G;B フォーマット)
    if not s.fg.isDefault:
        res.add("\e[38;2;" & $s.fg.r & ";" & $s.fg.g & ";" & $s.fg.b & "m")
    # TrueColor背景色 (48;2;R;G;B フォーマット)
    if not s.bg.isDefault:
        res.add("\e[48;2;" & $s.bg.r & ";" & $s.bg.g & ";" & $s.bg.b & "m")
    return res

# =============================================================================
# 差分描画エンジン
# =============================================================================

## 2つのバッファを比較し、変化したセルだけをターミナルに描画する
##
## 差分描画のメリット:
##   - 全画面再描画に比べて大幅に高速
##   - ターミナルへの出力量が最小限になる
##   - フリッカ(画面の点滅)が起きにくい
##
## アルゴリズム:
##  1. 2次元配列を1次元として走査 (y * width + x)
##  2. 各セルについて、current と next を比較
##  3. 異なる場合のみカーソル移動 + セル描画のシーケンスを出力バッファに追加
##  4. 最後にまとめて stdout に書き出す (I/O回数を最小化)
proc renderDiff*(current, next: Buffer) =
    var outBuf = ""  # 出力バッファ (ANSIシーケンスを蓄積)

    for y in 0 ..< next.height:
        for x in 0 ..< next.width:
            let idx = y * next.width + x

            # 現在のセル (バッファオーバーフロー時はデフォルトセルを使用)
            let cCell = if idx < current.cells.len: current.cells[idx] else: newCell()
            # 次のフレームのセル
            let nCell = next.cells[idx]

            # セルに変化があった場合のみ描画
            if cCell != nCell:
                # カーソル移動: \e[y;xH (1-indexed座標)
                outBuf.add("\e[" & $(y + 1) & ";" & $(x + 1) & "H")
                # スタイルシーケンスを出力
                outBuf.add(ansiStyle(nCell.style))
                # 実際の文字を出力
                outBuf.add(nCell.ch)

    # 変化があった場合のみflush (無駺なI/Oを防ぐ)
    if outBuf.len > 0:
        stdout.write(outBuf)
        stdout.flushFile()
