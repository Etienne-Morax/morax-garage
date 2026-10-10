import Foundation

public enum NettopParseError: Error, LocalizedError, Equatable {
    case missingRequiredColumns(String)
    case malformedRow(String)
    
    public var errorDescription: String? {
        switch self {
        case .missingRequiredColumns(let msg):
            return "Nettop CSV header missing required columns: \(msg)"
        case .malformedRow(let msg):
            return "Nettop CSV malformed row: \(msg)"
        }
    }
}

public struct NettopProcessSample: Sendable, Equatable {
    public let processLabel: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    
    public var cleanApplicationName: String {
        Self.cleanName(from: processLabel)
    }
    
    public init(processLabel: String, bytesIn: UInt64, bytesOut: UInt64) {
        self.processLabel = processLabel
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
    
    public static func cleanName(from label: String) -> String {
        guard let lastDotIndex = label.lastIndex(of: ".") else {
            return label
        }
        let afterDot = label[label.index(after: lastDotIndex)...]
        if !afterDot.isEmpty && afterDot.allSatisfy({ $0.isNumber }) {
            return String(label[..<lastDotIndex])
        }
        return label
    }
}

public struct NettopCSVHeader: Sendable, Equatable {
    public let processColumnIndex: Int
    public let bytesInColumnIndex: Int
    public let bytesOutColumnIndex: Int
    public let timeColumnIndex: Int
    
    public init(
        processColumnIndex: Int,
        bytesInColumnIndex: Int,
        bytesOutColumnIndex: Int,
        timeColumnIndex: Int
    ) {
        self.processColumnIndex = processColumnIndex
        self.bytesInColumnIndex = bytesInColumnIndex
        self.bytesOutColumnIndex = bytesOutColumnIndex
        self.timeColumnIndex = timeColumnIndex
    }
    
    public static func parse(_ line: String) throws -> NettopCSVHeader {
        let columns = line.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        
        guard let bytesInIndex = columns.firstIndex(of: "bytes_in"),
              let bytesOutIndex = columns.firstIndex(of: "bytes_out") else {
            throw NettopParseError.missingRequiredColumns("Missing bytes_in and/or bytes_out in header: \(line)")
        }
        
        let timeIndex = columns.firstIndex(of: "time") ?? 0
        
        var processIndex = 1
        if let explicitProcessIndex = columns.firstIndex(where: { $0 == "process" || $0 == "proc" || $0 == "name" }) {
            processIndex = explicitProcessIndex
        } else if columns.first == "" || (columns.count > 0 && columns[0].isEmpty && bytesInIndex > 0) {
            processIndex = 0
        } else if columns.count > 1 && columns[1].isEmpty {
            processIndex = 1
        }
        
        return NettopCSVHeader(
            processColumnIndex: processIndex,
            bytesInColumnIndex: bytesInIndex,
            bytesOutColumnIndex: bytesOutIndex,
            timeColumnIndex: timeIndex
        )
    }
    
    public func parseSample(from line: String) throws -> NettopProcessSample? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let columns = trimmed.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        
        let requiredMaxIndex = max(processColumnIndex, max(bytesInColumnIndex, bytesOutColumnIndex))
        guard columns.count > requiredMaxIndex else {
            return nil
        }
        
        let label = columns[processColumnIndex]
        guard !label.isEmpty, label.lowercased() != "time", label.lowercased() != "bytes_in" else {
            return nil
        }
        
        guard let bytesIn = UInt64(columns[bytesInColumnIndex]),
              let bytesOut = UInt64(columns[bytesOutColumnIndex]) else {
            return nil
        }
        
        return NettopProcessSample(
            processLabel: label,
            bytesIn: bytesIn,
            bytesOut: bytesOut
        )
    }
}

public enum NettopApplicationAggregator {
    public static func aggregateByApplication(samples: [NettopProcessSample]) -> [String: NettopProcessSample] {
        var dict: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
        
        for sample in samples {
            let appName = sample.cleanApplicationName
            let existing = dict[appName] ?? (bytesIn: 0, bytesOut: 0)
            dict[appName] = (
                bytesIn: existing.bytesIn + sample.bytesIn,
                bytesOut: existing.bytesOut + sample.bytesOut
            )
        }
        
        return dict.mapValues {
            NettopProcessSample(processLabel: "", bytesIn: $0.bytesIn, bytesOut: $0.bytesOut)
        }
    }
    
    public static func topApplications(from samples: [NettopProcessSample], limit: Int = 3) -> [NetworkApplicationUsage] {
        let grouped = aggregateByApplication(samples: samples)
        
        let usages = grouped.map { name, sample in
            NetworkApplicationUsage(
                name: name,
                downloadBytesPerSecond: Double(sample.bytesIn),
                uploadBytesPerSecond: Double(sample.bytesOut)
            )
        }
        
        return usages
            .sorted { $0.totalBytesPerSecond > $1.totalBytesPerSecond }
            .prefix(limit)
            .map { $0 }
    }
    
    public static func calculateRates(
        previousTotals: [String: NettopProcessSample],
        currentTotals: [String: NettopProcessSample],
        elapsed: TimeInterval,
        limit: Int = 3
    ) -> [NetworkApplicationUsage] {
        guard elapsed > 0 else { return [] }
        
        var usages: [NetworkApplicationUsage] = []
        
        for (appName, currentSample) in currentTotals {
            let prevSample = previousTotals[appName]
            let prevIn = prevSample?.bytesIn
            let prevOut = prevSample?.bytesOut
            
            let downloadRate = NetworkRateCalculator.rate(previous: prevIn, current: currentSample.bytesIn, elapsed: elapsed)
            let uploadRate = NetworkRateCalculator.rate(previous: prevOut, current: currentSample.bytesOut, elapsed: elapsed)
            
            if downloadRate > 0 || uploadRate > 0 {
                usages.append(NetworkApplicationUsage(
                    name: appName,
                    downloadBytesPerSecond: downloadRate,
                    uploadBytesPerSecond: uploadRate
                ))
            }
        }
        
        return usages
            .sorted { $0.totalBytesPerSecond > $1.totalBytesPerSecond }
            .prefix(limit)
            .map { $0 }
    }
}

public final class NettopCSVParser: Sendable {
    public init() {}
    
    public func parseBatch(lines: [String]) -> (header: NettopCSVHeader?, samples: [NettopProcessSample]) {
        var header: NettopCSVHeader?
        var samples: [NettopProcessSample] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            if header == nil {
                if let parsedHeader = try? NettopCSVHeader.parse(trimmed) {
                    header = parsedHeader
                    continue
                }
            }
            
            if let header = header, let sample = try? header.parseSample(from: trimmed) {
                samples.append(sample)
            }
        }
        
        return (header, samples)
    }
}
