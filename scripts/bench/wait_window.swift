// Polls the window server until the given PID owns an on-screen window, then prints elapsed ms.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 2, let pid = Int32(args[1]) else {
    FileHandle.standardError.write("usage: wait_window <pid> [timeout_s]\n".data(using: .utf8)!)
    exit(2)
}
let timeout = args.count >= 3 ? Double(args[2]) ?? 20 : 20
let start = Date()
while Date().timeIntervalSince(start) < timeout {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    if list.contains(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && (($0[kCGWindowLayer as String] as? Int) ?? 1) == 0 }) {
        print(Int(Date().timeIntervalSince(start) * 1000))
        exit(0)
    }
    usleep(10_000)
}
print("timeout")
exit(1)
