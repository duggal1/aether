import SwiftUI

public enum AetherMotion {
    public static func hover(_ reduced: Bool) -> Animation? { reduced ? nil : .easeOut(duration: 0.10) }
    public static func focus(_ reduced: Bool) -> Animation? { reduced ? nil : .easeInOut(duration: 0.14) }
    public static func tab(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.18) }
    public static func sidebar(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.23) }
    public static func selection(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.16) }
    public static func press(_ reduced: Bool) -> Animation? { reduced ? nil : .easeOut(duration: 0.08) }
    public static func popover(_ reduced: Bool) -> Animation? { reduced ? nil : .easeInOut(duration: 0.17) }
}
