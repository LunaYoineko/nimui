import std/tables
import ./input

export input

type
    EventCallback* = proc()

    ArrowKey* = enum
        akUp, akDown, akLeft, akRight

    EventBus* = ref object
        charHandlers*: Table[char, seq[EventCallback]]
        escapeHandlers*: seq[EventCallback]
        enterHandlers*: seq[EventCallback]
        arrowHandlers*: Table[ArrowKey, seq[EventCallback]]

proc newEventBus*(): EventBus =
    EventBus(
        charHandlers: initTable[char, seq[EventCallback]](),
        arrowHandlers: initTable[ArrowKey, seq[EventCallback]]()
    )

proc onChar*(bus: EventBus, ch: char, handler: EventCallback) =
    if ch notin bus.charHandlers:
        bus.charHandlers[ch] = @[]
    bus.charHandlers[ch].add(handler)

proc onEscape*(bus: EventBus, handler: EventCallback) =
    bus.escapeHandlers.add(handler)

proc onEnter*(bus: EventBus, handler: EventCallback) =
    bus.enterHandlers.add(handler)

proc onArrow*(bus: EventBus, arrow: ArrowKey, handler: EventCallback) =
    if arrow notin bus.arrowHandlers:
        bus.arrowHandlers[arrow] = @[]
    bus.arrowHandlers[arrow].add(handler)

proc dispatch*(bus: EventBus, key: KeyEvent) =
    case key.kind
    of nkChar:
        if key.ch in bus.charHandlers:
            for h in bus.charHandlers[key.ch]:
                h()
    of nkEscape:
        for h in bus.escapeHandlers:
            h()
    of nkEnter:
        for h in bus.enterHandlers:
            h()
    of nkUp:
        if akUp in bus.arrowHandlers:
            for h in bus.arrowHandlers[akUp]:
                h()
    of nkDown:
        if akDown in bus.arrowHandlers:
            for h in bus.arrowHandlers[akDown]:
                h()
    of nkLeft:
        if akLeft in bus.arrowHandlers:
            for h in bus.arrowHandlers[akLeft]:
                h()
    of nkRight:
        if akRight in bus.arrowHandlers:
            for h in bus.arrowHandlers[akRight]:
                h()
    else: discard
