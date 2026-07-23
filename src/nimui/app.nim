## =============================================================================
## nimui/app.nim
## このモジュールは以下の機能を提供する:
##   - App: アプリケーションの状態を管理するメインオブジェクト
##   - newApp(): Appの生成
##   - onKey(): キーイベントハンドラの登録 (文字キー / 特殊キー)
##   - quit(): アプリケーションの終了
##   - run(): メインループ (非同期)
##
## アプリケーションの流れ:
##   1. newApp() でAppを生成
##   2. onKey() でキーイベントハンドラを登録
##   3. run(build) でメインループを開始
##   4. メインループは毎フレーム以下を繰り返す:
##      a. pollKey() でキー入力を取得
##      b. EventBus.dispatch() でハンドラを呼び出す
##      c. build() を呼び出してウィジェットツリーを構築
##      d. ウィジェットをバッファに描画
##      e. 差分描画でターミナルに反映
##      f. 16ms待機 (約60FPS)
##
## 設計思想:
##   - build() は毎フレーム呼ばれるため、外部変数の変更が自動的に反映される
##   - 差分描画により、変化した部分だけを描画して高速化
##   - async/await で非同期イベントループを実現
## =============================================================================

import std/asyncdispatch
import ./core/term
import ./core/input
import ./core/buffer
import ./core/event
import ./components/widget

export widget, buffer, event  # ライブラリ利用者に再エクスポート

# =============================================================================
# App型定義
# =============================================================================

type
    ## アプリケーションの状態を保持するオブジェクト
    ##
    ## running:      メインループの実行フラグ (falseでループ終了)
    ## currentBuffer: 前フレームのバッファ (差分描画に使用)
    ## eventBus:     キーイベントのディスパッチャ
    App* = ref object
        running: bool
        currentBuffer: Buffer
        eventBus: EventBus

# =============================================================================
# App 生成・制御
# =============================================================================

## 新しいAppを生成する
## 初期状態では running = false, EventBus が初期化された状態
proc newApp*(): App =
    App(running: false, eventBus: newEventBus())

# =============================================================================
# キーイベントハンドラ登録
# =============================================================================

## 文字キーのハンドラを登録する
## ch: 対象の文字 (例: 'q', ' ', 'a')
## handler: キー押下時に呼び出されるコールバック関数
##
## 使用例:
##   app.onKey('q', proc() = app.quit())
##   app.onKey(' ', proc() = inc count)
proc onKey*(app: App, ch: char, handler: proc()) =
    app.eventBus.onChar(ch, handler)

## 特殊キーのハンドラを登録する
## key: KeyKind列挙型の値 (nkEscape, nkEnter, nkUp等)
## handler: キー押下時に呼び出されるコールバック関数
##
## 使用例:
##   app.onKey(nkEscape, proc() = app.quit())
##   app.onKey(nkUp, proc() = moveUp())
proc onKey*(app: App, key: KeyKind, handler: proc()) =
    case key
    of nkEscape: app.eventBus.onEscape(handler)
    of nkEnter: app.eventBus.onEnter(handler)
    of nkUp: app.eventBus.onArrow(akUp, handler)
    of nkDown: app.eventBus.onArrow(akDown, handler)
    of nkLeft: app.eventBus.onArrow(akLeft, handler)
    of nkRight: app.eventBus.onArrow(akRight, handler)
    else: discard  # nkChar等は文字キーとして別プロシージャで処理

## アプリケーションを終了する
## running を false に設定し、メインループの次回チェックで終了する
proc quit*(app: App) =
    app.running = false

# =============================================================================
# メインループ
# =============================================================================

## アプリケーションのメインループを開始する (非同期)
##
## build: 毎フレーム呼ばれるウィジェット構築関数
##   この関数が返すWidgetが画面に描画される
##   外部変数 (カウンタ等) を参照しているため、変更が自動的に反映される
##
## メインループの処理:
##   1. ターミナルをRaw Modeに切り替え (例外時も確実に復元)
##   2. ターミナルサイズを取得してバッファを初期化
##   3. 画面をクリア
##   4. メインループ開始 (running = true の間繰り返す):
##      a. pollKey() でキー入力を1つ取得
##      b. eventBus.dispatch() で登録されたハンドラを呼び出す
##      c. build() を呼び出して最新のウィジェットツリーを構築
##      d. 新しいバッファを作成してウィジェットを描画
##      e. renderDiff() で前フレームと差分比較して描画
##      f. 16ms待機 (约60FPS)
##
## 注意: defer: disableRawMode() により、例外が発生しても確実に
##       ターミナルが復元される (Raw Modeのままターミナルが壊れるのを防止)
proc run*(app: App, build: proc(): Widget) {.async.} =
    # ターミナルをRaw Modeに切り替え
    # defer で例外時も確実に元に戻す
    enableRawMode()
    defer: disableRawMode()

    app.running = true

    # ターミナルサイズを取得してバッファを初期化
    let (w, h) = getTerminalSize()
    app.currentBuffer = newBuffer(w, h)

    # 画面をクリア (最初の一描画)
    clearScreen()

    # メインループ
    while app.running:
        # 1. キー入力を取得 (ノンブロッキング)
        let ev = pollKey()

        # 2. イベントをハンドラにディスパッチ
        app.eventBus.dispatch(ev)

        # 3. ユーザー定義の build() を呼び出してウィジェットツリーを構築
        let widget = build()

        # 4. 新しいバッファを作成してウィジェットを描画
        let nextBuffer = newBuffer(w, h)

        # --- 自動ドッキング ---
        # ルートがvboxの場合、header/footerを自動的に上下に配置する
        # header → 画面最上部 (y=0)
        # footer → 画面最下部 (y=h-1)
        # それ以外の子 → 中間領域に描画
        if widget.kind == wkVBox:
            var dockedHeader: Widget = nil
            var dockedFooter: Widget = nil
            var contentChildren: seq[Widget] = @[]

            # vbox の子を走査して header / footer を分離
            for child in widget.children:
                case child.kind
                of wkHeader: dockedHeader = child
                of wkFooter: dockedFooter = child
                else: contentChildren.add(child)

            # ヘッダーを最上部に描画 (全幅、1行)
            if dockedHeader != nil:
                dockedHeader.render(nextBuffer, 0, 0, w, 1)

            # フッターを最下部に描画 (全幅、1行)
            if dockedFooter != nil:
                dockedFooter.render(nextBuffer, 0, h - 1, w, 1)

            # コンテンツ領域の計算
            let contentY = if dockedHeader != nil: 1 else: 0
            let contentH = (if dockedFooter != nil: h - 1 else: h) - contentY

            # 残りの子をコンテンツとして描画
            if contentChildren.len == 1:
                # 子が1つならそのまま描画
                contentChildren[0].render(nextBuffer, 0, contentY, w, contentH)
            elif contentChildren.len > 1:
                # 複数ならvboxとして描画
                let contentVbox = Widget(kind: wkVBox, children: contentChildren, gap: widget.gap)
                contentVbox.render(nextBuffer, 0, contentY, w, contentH)
        else:
            # ルートがvbox以外なら従来通り全体に描画
            widget.render(nextBuffer, 0, 0, w, h)

        # 5. 差分描画: 前フレーム(currentBuffer)と比較して変化した部分だけ描画
        renderDiff(app.currentBuffer, nextBuffer)

        # 6. 描画済みバッファを保存 (次のフレームの差分比較用)
        app.currentBuffer = nextBuffer

        # 7. 約16ms待機 (60FPS相当)
        await sleepAsync(16)
