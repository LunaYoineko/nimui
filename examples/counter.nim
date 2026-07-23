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
