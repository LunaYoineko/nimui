# Nimui

モダンでシンプルな Nim TUI フレームワーク。コンポーネントベースで宣言的に UI を構築できます。

## 特徴

- **宣言的な API** — コンポーネントを組み立てるだけで UI を構築
- **自動レイアウト** — `vbox`, `hbox`, `center` で座標計算不要
- **差分描画** — 変化した部分だけ描画し、60FPS で滑らかな描画
- **TrueColor** — 24bit カラー対応
- **Unicode 対応** — 日本語や絵文字も正しく表示
- **非同期イベントループ** — `async/await` ベース

## インストール

```bash
nimble install nimui
```

## クイックスタート

```nim
import std/asyncdispatch
import nimui

var count = 0

let app = newApp()

proc build(): Widget =
  vbox(
    header("My App", fg = colWhite, bg = colBlue, bold = true),
    center(40, 10,
      label("Counter: " & $count, fg = colGreen, bold = true),
      progress(count.float, max = 20.0, fg = colBlue)
    ),
    footer("SPACE: +1 | Q: Quit", fg = colTextMuted, bg = colBgDark)
  )

app.onKey(' ', proc() = inc count)
app.onKey('q', proc() = app.quit())

waitFor app.run(build)
```

## コンポーネント

### label — テキスト表示

```nim
label("Hello, World!")
label("Bold text", fg = colGreen, bold = true)
label("Colored", fg = colRed, bg = colBgCard)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `text` | `string` | 表示テキスト |
| `fg` | `Color` | 前景色（デフォルト: ターミナルのデフォルト） |
| `bg` | `Color` | 背景色 |
| `bold` | `bool` | 太字にするか |

### vbox — 縦並びレイアウト

```nim
vbox(
  label("1st"),
  label("2nd"),
  label("3rd")
)
```

隙間を空ける場合:

```nim
vbox(1,
  label("1st"),
  label("2nd"),
  label("3rd")
)
```

### hbox — 横並びレイアウト

```nim
hbox(
  label("Left"),
  label("Center"),
  label("Right")
)
```

隙間を空ける場合:

```nim
hbox(2,
  label("A"),
  label("B"),
  label("C")
)
```

### center — 中央寄せボックス

指定したサイズの領域を中央に配置し、子ウィジェットをその中で表示します。

```nim
center(40, 10,
  label("This is centered"),
  label("Inside a 40x10 box")
)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `w` | `int` | ボックスの幅 |
| `h` | `int` | ボックスの高さ |

### header — ヘッダーバー

画面上部に全幅のバーを表示します。

```nim
header("My App", fg = colWhite, bg = colBlue, bold = true)
```

### footer — フッターバー

画面下部に全幅のバーを表示します。

```nim
footer("Q: Quit | SPACE: Action", fg = colTextMuted, bg = colBgDark)
```

### progress — プログレスバー

```nim
progress(0.75)              # 75%（デフォルト max = 1.0）
progress(50.0, max = 100.0) # 50%
progress(5.0, max = 10.0, fg = colCyan)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `value` | `float` | 現在値 |
| `max` | `float` | 最大値（デフォルト: 1.0） |
| `fg` | `float` | 塗りつぶし部分の色 |

### separator — 区切り線

```nim
separator(fg = colTextMuted)
```

### spacer — 空白スペース

```nim
spacer(2) # 2行分の空白
```

## キーイベント

### 文字キー

```nim
app.onKey(' ', proc() = doSomething())
app.onKey('q', proc() = app.quit())
```

### 特殊キー

```nim
app.onKey(nkUp,    proc() = moveUp())
app.onKey(nkDown,  proc() = moveDown())
app.onKey(nkLeft,  proc() = moveLeft())
app.onKey(nkRight, proc() = moveRight())
app.onKey(nkEscape, proc() = app.quit())
app.onKey(nkEnter,  proc() = submit())
```

利用可能な `KeyKind`:

| 値 | キー |
|---|---|
| `nkUp` | ↑ |
| `nkDown` | ↓ |
| `nkLeft` | ← |
| `nkRight` | → |
| `nkEscape` | Esc |
| `nkEnter` | Enter |

## カラーパレット

組み込みのカラーコンストラント:

| 定数 | RGB | 用途例 |
|---|---|---|
| `colBlue` | `(97, 175, 239)` | アクセント |
| `colPurple` | `(198, 120, 221)` | タイトル |
| `colGreen` | `(152, 195, 121)` | 成功 |
| `colYellow` | `(229, 192, 123)` | 警告 |
| `colRed` | `(224, 108, 117)` | エラー |
| `colCyan` | `(86, 182, 194)` | 情報 |
| `colText` | `(220, 223, 228)` | メインテキスト |
| `colTextMuted` | `(92, 99, 112)` | 薄いテキスト |
| `colWhite` | `(255, 255, 255)` | 白 |
| `colBgDark` | `(30, 34, 42)` | ダーク背景 |
| `colBgCard` | `(40, 44, 52)` | カード背景 |
| `colBgFocus` | `(50, 56, 66)` | フォーカス背景 |

カスタムカラー:

```nim
let myColor = rgb(255, 128, 0) # オレンジ
label("Custom color", fg = myColor)
```

## スタイル

```nim
style(fg = colGreen, bg = colBgCard, bold = true, dim = true)
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `fg` | `Color` | 前景色 |
| `bg` | `Color` | 背景色 |
| `bold` | `bool` | 太字 |
| `dim` | `bool` | 暗く表示 |

## 便利な関数

### drawString — 低レベルテキスト描画

```nim
buf.drawString(10, 5, "Hello", style(fg = colGreen))
```

### drawBox — 低レベルボックス描画

```nim
buf.drawBox(5, 3, 30, 10, style(fg = colBlue), bsRounded)
```

ボーダースタイル:

| 定数 | ボーダー |
|---|---|
| `bsSingle` | `┌┐└┘─│` |
| `bsDouble` | `╔╗╚╝═║` |
| `bsRounded` | `╭╮╰╯─│` |
| `bsBold` | `┏┓┗┛━┃` |

## 完全な例: カウンターアプリ

```nim
import std/asyncdispatch
import nimui

var count = 0

let app = newApp()

proc build(): Widget =
  vbox(
    header("🚀 Nimui v0.1.0", fg = colWhite, bg = colBlue, bold = true),
    center(40, 10,
      label(" [ Counter Widget ] ", fg = colPurple, bold = true),
      label(""),
      label("Press SPACE to increment counter.", fg = colText),
      label(""),
      label("Current Count: " & $count, fg = colGreen, bold = true),
      label(""),
      progress(count.float, max = 20.0, fg = colBlue)
    ),
    footer(" Q: Quit | SPACE: Increment ", fg = colTextMuted, bg = colBgDark)
  )

app.onKey(' ', proc() = inc count)
app.onKey('q', proc() = app.quit())
app.onKey('Q', proc() = app.quit())

waitFor app.run(build)
```

## ライセンス

MIT
