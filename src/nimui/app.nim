import std/asyncdispatch
import ./core/term
import ./core/input
import ./core/buffer
import ./core/event
import ./components/widget

export widget, buffer, event

type
    App* = ref object
        running: bool
        currentBuffer: Buffer
        eventBus: EventBus

proc newApp*(): App =
    App(running: false, eventBus: newEventBus())

proc onKey*(app: App, ch: char, handler: proc()) =
    app.eventBus.onChar(ch, handler)

proc onKey*(app: App, key: KeyKind, handler: proc()) =
    case key
    of nkEscape: app.eventBus.onEscape(handler)
    of nkEnter: app.eventBus.onEnter(handler)
    of nkUp: app.eventBus.onArrow(akUp, handler)
    of nkDown: app.eventBus.onArrow(akDown, handler)
    of nkLeft: app.eventBus.onArrow(akLeft, handler)
    of nkRight: app.eventBus.onArrow(akRight, handler)
    else: discard

proc quit*(app: App) =
    app.running = false

proc run*(app: App, build: proc(): Widget) {.async.} =
    enableRawMode()
    defer: disableRawMode()

    app.running = true
    let (w, h) = getTerminalSize()
    app.currentBuffer = newBuffer(w, h)

    clearScreen()

    while app.running:
        let ev = pollKey()
        app.eventBus.dispatch(ev)

        let widget = build()
        let nextBuffer = newBuffer(w, h)

        widget.render(nextBuffer, 0, 0, w, h)

        renderDiff(app.currentBuffer, nextBuffer)
        app.currentBuffer = nextBuffer

        await sleepAsync(16)
