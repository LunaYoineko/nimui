import std/unittest
import nimui

suite "nimui Widget & Layout Tests":
    
    test "vbox correctly groups header, footer, and content":
        let h = header("Header")
        let f = footer("Footer")
        let l = label("Content")
        
        let root = vbox(h, l, f)
        
        let k = root.kind
        check k == wkVBox
        
        let childCount = root.children.len
        check childCount == 3
        
    test "custom color RGB values":
        let c = rgb(255, 128, 0)
        check c.r == 255
        check c.g == 128
        check c.b == 0
        