import Cocoa
import FlutterMacOS
import XCTest
@testable import TuneFlow

final class RunnerTests: XCTestCase {
  func testLayoutUsesCompactBelow1440Points() {
    XCTAssertEqual(MacOSMenuBarLayoutMode(screenWidth: 1439), .compact)
    XCTAssertEqual(MacOSMenuBarLayoutMode(screenWidth: 1440), .full)
  }

  func testSnapshotDecodesStableFlutterMap() throws {
    let state = try XCTUnwrap(MacOSMenuBarState(dictionary: [
      "trackId": "42",
      "source": "wy",
      "title": "夜曲",
      "artist": "周杰伦",
      "playing": true,
      "loading": false,
      "canPlayPause": true,
      "canGoPrevious": false,
      "canGoNext": true,
      "favorite": true,
      "favoritePending": false,
      "canToggleFavorite": true,
    ]))

    XCTAssertEqual(state.trackId, "42")
    XCTAssertEqual(state.source, "wy")
    XCTAssertEqual(state.title, "夜曲")
    XCTAssertTrue(state.playing)
    XCTAssertTrue(state.favorite)
  }

  func testSnapshotRejectsMalformedRequiredFields() {
    var dictionary = MacOSMenuBarState.idle.dictionary
    dictionary["playing"] = "yes"

    XCTAssertNil(MacOSMenuBarState(dictionary: dictionary))
  }

  func testLayoutExposesExpectedElements() {
    XCTAssertEqual(
      MacOSMenuBarLayoutMode.full.visibleElements,
      [.app, .title, .previous, .playPause, .next, .favorite]
    )
    XCTAssertEqual(
      MacOSMenuBarLayoutMode.compact.visibleElements,
      [.app, .playPause]
    )
    XCTAssertEqual(MacOSMenuBarLayoutMode.iconOnly.visibleElements, [.app])
  }

  func testControllerForwardsSemanticCommands() {
    let controller = MacOSMenuBarController()
    var commands: [String] = []
    controller.sendCommand = { commands.append($0) }

    controller.performForTesting(.previous)
    controller.performForTesting(.playPause)
    controller.performForTesting(.toggleFavorite)

    XCTAssertEqual(commands, ["previous", "playPause", "toggleFavorite"])
  }

  func testMenuBarTemplateAssetsLoad() throws {
    let names = [
      "MenuBarTuneFlow",
      "MenuBarPrevious",
      "MenuBarPlay",
      "MenuBarPause",
      "MenuBarNext",
      "MenuBarHeart",
      "MenuBarHeartFilled",
    ]

    for name in names {
      XCTAssertNotNil(NSImage(named: name), "Missing asset \(name)")
    }

    let brand = try XCTUnwrap(NSImage(named: "MenuBarTuneFlow"))
    XCTAssertEqual(brand.size, NSSize(width: 18, height: 18))
  }

  func testInlineButtonForwardsRightClickToContextMenu() {
    let button = MacOSMenuBarButton()
    var secondaryClicks = 0
    button.secondaryAction = { secondaryClicks += 1 }

    button.performSecondaryActionForTesting()

    XCTAssertEqual(secondaryClicks, 1)
  }

  func testTransportTemplateAssetsFillTheirOpticalCanvas() throws {
    for name in [
      "MenuBarPrevious",
      "MenuBarPlay",
      "MenuBarPause",
      "MenuBarNext",
    ] {
      let image = try XCTUnwrap(NSImage(named: name))
      let bounds = try XCTUnwrap(visibleBounds(of: image))
      XCTAssertGreaterThanOrEqual(
        bounds.height,
        13,
        "\(name) is optically too small: \(bounds)"
      )
      XCTAssertLessThanOrEqual(
        bounds.height,
        15,
        "\(name) is optically too large: \(bounds)"
      )
    }
  }

  func testStatusItemLengthShrinksWhenTheTitleGetsShorter() {
    let fixedControls: [CGFloat] = [18, 14, 14, 14, 15]
    let long = MacOSMenuBarSizing.contentLength(
      widths: [fixedControls[0], 160] + Array(fixedControls.dropFirst()),
      spacing: 3,
      horizontalInsets: 8
    )
    let short = MacOSMenuBarSizing.contentLength(
      widths: [fixedControls[0], 48] + Array(fixedControls.dropFirst()),
      spacing: 3,
      horizontalInsets: 8
    )

    XCTAssertEqual(long - short, 112)
    XCTAssertLessThan(short, long)
  }

  private func visibleBounds(of image: NSImage) -> NSRect? {
    let scale = 10
    let side = 18 * scale
    guard let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: side,
      pixelsHigh: side,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()

    var minX = side
    var minY = side
    var maxX = -1
    var maxY = -1
    for y in 0..<side {
      for x in 0..<side where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
      }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    return NSRect(
      x: CGFloat(minX) / CGFloat(scale),
      y: CGFloat(minY) / CGFloat(scale),
      width: CGFloat(maxX - minX + 1) / CGFloat(scale),
      height: CGFloat(maxY - minY + 1) / CGFloat(scale)
    )
  }
}
