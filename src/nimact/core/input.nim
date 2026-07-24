## =============================================================================
## nimact/core/input.nim
## ターミナルからのキー入力を読み取るモジュール
##
## このモジュールは以下の機能を提供する:
##   - ノンブロッキングキー読み込み: タイムアウト付きでstdinから1バイト読み取り
##   - エスケープシーケンス解析: 矢印キー・Escape等の特殊キーを判定
##   - KeyEvent型: 入力されたキーの種類と文字情報を格納する型
##
## 入力処理の流れ:
##   1. pollKey() を呼び出して1バイト読み込む
##  2. 读み込んだバイトが '\e' (Escape) の場合、追加で2バイト読み込んで
##     エスケープシーケンスを解析 (矢印キー等)
##  3. KeyEvent を返して、呼び出し元で処理
##
## エスケープシーケンスの形式:
##   矢印キー: \e[A (上), \e[B (下), \e[C (右), \e[D (左)
##   Escapeキー: \e (単体で押された場合)
## =============================================================================

## Cの read() 関数をバインディング
## fd: ファイルディスクリプタ
## buf: 読み込み先のバッファ
## count: 読み込むバイト数
## 戻り値: 実際に読み込まれたバイト数 (0=EOF, 負=エラー)
proc c_read(fd: cint, buf: pointer, count: csize_t): csize_t
    {.importc: "read", header: "<unistd.h>".}

const STDIN_FILENO = 0.cint  ## 標準入力のファイルディスクリプタ

# =============================================================================
# キー入力の型定義
# =============================================================================

type
    ## キーの種類を表す列挙型
    KeyKind* = enum
        nkChar,     ## 通常の文字キー (a-z, 0-9, スペース等)
        nkUp,       ## 矢印キー ↑
        nkDown,     ## 矢印キー ↓
        nkRight,    ## 矢印キー →
        nkLeft,     ## 矢印キー ←
        nkEscape,   ## Escapeキー
        nkEnter,    ## Enterキー (\r または \n)
        nkUnknown,  ## 不明なエスケープシーケンス
        nkNone,     ## 入力なし (タイムアウト等)

    ## キー入力イベントを表すオブジェクト
    KeyEvent* = object
        kind*: KeyKind  ## キーの種類
        ch*: char       ## nkChar の場合の入力文字 (それ以外は未定義)

# =============================================================================
# キー入力読み込み
# =============================================================================

## STDINから1バイト読み取り、キーを判定する (ノンブロッキング)
##
## ノンブロッキングとは:
##   入力データがない場合でもブロック(待機)せず、即座に nkNone を返す
##  これにより、メインループが毎フレーム入力を確認しながら描画を続行できる
##
## Escape シーケンスの解析:
##   1. 最初の1バイトを読み込む
##   2. それが '\e' (0x1B) なら追加で2バイト読み込む
##   3. '[', 'A' の並びなら矢印キー↑と判定
##   4. それ以外は単なるEscapeキー押下とする
##
## キーマッピング:
##   \e[A → nkUp    \e[B → nkDown
##   \e[C → nkRight \e[D → nkLeft
##   \r, \n → nkEnter
##   その他 → nkChar (ch に文字を格納)
proc pollKey*(): KeyEvent =
    var buf: array[3, char]  # エスケープシーケンス用のバッファ (最大3バイト)

    # 最初の1バイトを読み込む
    let bytesRead = c_read(STDIN_FILENO, buf[0].addr, 1)

    # 読み込みバイト数が0以下なら入力なし
    if bytesRead <= 0:
        return KeyEvent(kind: nkNone)

    case buf[0]
    of '\e':  # Escape シーケンスの開始
        # 2バイト目を読み込む (タイムアウトで取得できない場合もある)
        let b2 = c_read(STDIN_FILENO, buf[1].addr, 1)
        if b2 <= 0: return KeyEvent(kind: nkEscape)

        # 3バイト目を読み込む
        let b3 = c_read(STDIN_FILENO, buf[2].addr, 1)
        if b3 <= 0: return KeyEvent(kind: nkEscape)

        # \e[A の形式なら矢印キーと判定
        if buf[1] == '[':
            case buf[2]
            of 'A': return KeyEvent(kind: nkUp)      # \e[A = ↑
            of 'B': return KeyEvent(kind: nkDown)    # \e[B = ↓
            of 'C': return KeyEvent(kind: nkRight)   # \e[C = →
            of 'D': return KeyEvent(kind: nkLeft)    # \e[D = ←
            else: return KeyEvent(kind: nkUnknown)   # 不明なシーケンス
        return KeyEvent(kind: nkEscape)  # \e 単体 = Escape キー

    of '\r', '\n':  # Enter キー (CR または LF)
        return KeyEvent(kind: nkEnter)

    else:  # 通常の文字キー
        return KeyEvent(kind: nkChar, ch: buf[0])
