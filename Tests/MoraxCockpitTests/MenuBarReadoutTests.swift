import Foundation
import Testing
@testable import MoraxCockpitKit

struct MenuBarReadoutTests {
    private let gib: Int64 = 1024 * 1024 * 1024

    private func options(
        showIcon: Bool = true,
        showCpu: Bool = true,
        showRam: Bool = false,
        showNetwork: Bool = false,
        showDisk: Bool = false,
        showTemperature: Bool = false,
        showSwapAlert: Bool = false
    ) -> MenuBarReadout.Options {
        MenuBarReadout.Options(
            showIcon: showIcon,
            showCpu: showCpu,
            showRam: showRam,
            showNetwork: showNetwork,
            showDisk: showDisk,
            showTemperature: showTemperature,
            showSwapAlert: showSwapAlert,
            temperatureUnit: .celsius
        )
    }

    @Test("samples that only differ in timestamp, uptime or sub-percent CPU give the same readout")
    func unchangedDisplayedValuesCompareEqual() {
        let first = SystemSnapshot(timestamp: Date(timeIntervalSince1970: 1), cpuUsage: 0.421, uptimeSeconds: 100)
        let second = SystemSnapshot(timestamp: Date(timeIntervalSince1970: 3), cpuUsage: 0.423, uptimeSeconds: 102)

        let before = MenuBarReadout(options: options(), system: first, network: nil)
        let after = MenuBarReadout(options: options(), system: second, network: nil)

        #expect(before == after)
        #expect(before.cpu == "CPU 42%")
    }

    @Test("a change in the displayed CPU percentage changes the readout")
    func displayedChangeCompareDifferent() {
        let first = SystemSnapshot(cpuUsage: 0.42)
        let second = SystemSnapshot(cpuUsage: 0.47)

        #expect(
            MenuBarReadout(options: options(), system: first, network: nil)
                != MenuBarReadout(options: options(), system: second, network: nil)
        )
    }

    @Test("hidden readouts do not need their snapshot")
    func hiddenReadoutsNeedNoSnapshot() {
        let networkOnly = options(showCpu: false, showNetwork: true)
        #expect(networkOnly.needsSystemSnapshot == false)

        let readout = MenuBarReadout(
            options: networkOnly,
            system: nil,
            network: NetworkSnapshot(downloadBytesPerSecond: 2 * 1024 * 1024, uploadBytesPerSecond: 3 * 1024)
        )
        #expect(readout.cpu == nil)
        #expect(readout.network == "↓2.0M ↑3K")
    }

    @Test("the swap alert shows only above 2 GiB of swap")
    func swapAlertThreshold() {
        let alertOptions = options(showCpu: false, showSwapAlert: true)
        let low = SystemSnapshot(swapUsed: 2 * gib)
        let high = SystemSnapshot(swapUsed: 2 * gib + 1)

        #expect(MenuBarReadout(options: alertOptions, system: low, network: nil).showsSwapAlert == false)
        #expect(MenuBarReadout(options: alertOptions, system: high, network: nil).showsSwapAlert)
    }

    @Test("the wrench icon stays visible when every readout is turned off")
    func fallbackIconWhenEverythingHidden() {
        let hidden = options(showIcon: false, showCpu: false)
        #expect(MenuBarReadout(options: hidden, system: nil, network: nil).showsFallbackIcon)
        #expect(MenuBarReadout(options: options(), system: nil, network: nil).showsFallbackIcon == false)
    }

    @Test("disk and temperature readouts match the label format")
    func diskAndTemperatureFormats() {
        let volume = DiskVolumeInfo(name: "SSD", path: "/", totalBytes: 1_000 * gib, freeBytes: 200 * gib, isRemovable: false)
        let snapshot = SystemSnapshot(cpuTemp: 51.6, diskVolumes: [volume])
        let readout = MenuBarReadout(
            options: options(showCpu: false, showDisk: true, showTemperature: true),
            system: snapshot,
            network: nil
        )

        #expect(readout.temperature == "52°C")
        #expect(readout.disk == "SSD \(ByteCountFormatter.string(fromByteCount: 200 * gib, countStyle: .file))")
    }
}
