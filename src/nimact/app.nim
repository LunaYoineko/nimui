## =============================================================================
## nimact/app.nim
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

    # 画面をクリア (最初の一描画)
    clearScreen()

    let (initW, initH) = getTerminalSize()
    app.currentBuffer = newBuffer(initW, initH)
    
    # メインループ
    while app.running:
        # 毎フレームターミナルサイズを取得(リサイズ対応)
        let (w, h) = getTerminalSize()

        # キー入力を取得 (ノンブロッキング)
        let ev = pollKey()
        # イベントをハンドラにディスパッチ
        app.eventBus.dispatch(ev)

        # ユーザー定義の build() を呼び出してウィジェットツリーを構築
        let rootWidget = build()
        # 新しいバッファを作成してウィジェットを描画
        let nextBuffer = newBuffer(w, h)

        # ヘッダー / フッター と ルートvbox の探索
        var targetVBox: Widget = nil
        var dockedHeader: Widget = nil
        var dockedFooter: Widget = nil
        
        # ルート自身がvboxか、あるいはツリー直下を探索して最初に見つかったvbox / 特殊ウィジェットを探す
        if rootWidget.kind == wkVBox:
            targetVBox = rootWidget
        elif rootWidget.kind == wkCenter:
            # centerなどの子要素にvboxがある場合を検索
            for child in rootWidget.centerChildren:
                if child.kind == wkVBox:
                    targetVBox = child
                    break
        
        if targetVBox != nil:
            var contentChildren: seq[Widget] = @[]
            for child in targetVBox.children:
                case child.kind
                of wkHeader: dockedHeader = child
                of wkFooter: dockedFooter = child
                else: contentChildren.add(child)
                
            # 描画位置の決定
            let headerH = if dockedHeader != nil: 1 else: 0
            let footerH = if dockedFooter != nil: 1 else: 0
                
            # 中間コンテンツ領域の描画
            let contentY = headerH
            let contentH = max(0, h - headerH - footerH)
            
            if contentChildren.len > 0:
                let contentVbox = Widget(
                        kind: wkVBox,
                        children: contentChildren,
                        gap: targetVBox.gap,
                        vhboxStyle: targetVBox.vhboxStyle
                )
                contentVbox.render(nextBuffer, 0, contentY, w, contentH)
                
            if dockedHeader != nil:
                dockedHeader.render(nextBuffer, 0, 0, w, 1)
                
            if dockedFooter != nil:
                dockedFooter.render(nextBuffer, 0, h - 1, w, 1)
                
        else:
            # vboxが存在しない場合は画面全体にそのまま描画
            rootWidget.render(nextBuffer, 0, 0, w, h)
                
        # 差分描画 & バッファ更新
        if app.currentBuffer == nil or app.currentBuffer.width != w or app.currentBuffer.height != h:
            app.currentBuffer = newBuffer(w, h)
                
        renderDiff(app.currentBuffer, nextBuffer)
        app.currentBuffer = nextBuffer
            
            
        # 60FPSウェイト
        await sleepAsync(16)