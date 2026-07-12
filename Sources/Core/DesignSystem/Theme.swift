import SwiftUI

public enum Theme {
    public static var fontTitle: Font { .title2.weight(.semibold) }
    public static var fontHeader: Font { .headline }
    public static var fontBody: Font { .body }
    public static var fontCaption: Font { .caption }
    public static var fontCode: Font { .body.monospaced() }
}
