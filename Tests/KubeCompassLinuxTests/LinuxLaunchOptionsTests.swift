import XCTest
@testable import KubeCompassLinuxSupport

final class LinuxLaunchOptionsTests: XCTestCase {
    func testRowsAndSmokeArgumentsOverrideEnvironment() {
        let options = LinuxLaunchOptions(
            arguments: ["--smoke", "--rows", "10000"],
            environment: ["KUBECOMPASS_ROWS": "12"]
        )
        XCTAssertEqual(options.rows, 10_000)
        XCTAssertTrue(options.smoke)
        XCTAssertTrue(options.demo)
    }

    func testEnvironmentRowsAndInvalidValuesUseSafeDefaults() {
        XCTAssertEqual(
            LinuxLaunchOptions(arguments: [], environment: ["KUBECOMPASS_ROWS": "42"]).rows,
            42
        )
        XCTAssertEqual(
            LinuxLaunchOptions(arguments: ["--rows", "not-a-number"], environment: [:]).rows,
            2
        )
        XCTAssertEqual(
            LinuxLaunchOptions(arguments: ["--rows", "0"], environment: [:]).rows,
            1
        )
    }

    func testSemanticLabelsAndCatalogAreStable() {
        XCTAssertEqual(LinuxSemanticLabels.table, "resource table")
        XCTAssertEqual(LinuxDemoCatalog.resourceNames(rows: 3), ["pod-0", "pod-1", "pod-2"])
        XCTAssertEqual(LinuxDemoCatalog.status(for: 17), "Pending")
        XCTAssertEqual(LinuxDemoCatalog.labels(for: 4)["fixture"], "true")
    }
}
