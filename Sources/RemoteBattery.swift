import Foundation

/// Reads only the operating system's cached Bluetooth device summary.
final class RemoteBattery {
 private(set) var percent:Int?
 private(set) var connected=false
 private(set) var checkedAt:Date?
 private var running=false
 var onUpdate:(()->Void)?
 func refresh() {
  guard !running else {return};running=true
  DispatchQueue.global(qos:.utility).async { [weak self] in
   let result=Self.read()
   DispatchQueue.main.async { [weak self] in
    guard let self else{return};self.running=false
    switch result {
    case .success(let state):self.connected=state.connected;self.percent=state.percent;self.checkedAt=Date()
    case .failure:self.connected=false;self.percent=nil;self.checkedAt=nil
    }
    self.onUpdate?()
   }
  }
 }
 private static func read()->Result<(connected:Bool,percent:Int?),Error> {
  do {
   let task=Process();task.executableURL=URL(fileURLWithPath:"/usr/sbin/system_profiler");task.arguments=["SPBluetoothDataType","-json"]
   let out=Pipe();task.standardOutput=out;task.standardError=FileHandle.nullDevice
   try task.run();let bytes=out.fileHandleForReading.readDataToEndOfFile();task.waitUntilExit()
   guard task.terminationStatus == 0, let json=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],let roots=json["SPBluetoothDataType"] as? [[String:Any]] else {throw NSError(domain:"BluetoothSummary",code:1)}
   var matches=[[String:Any]]()
   for root in roots {for item in root["device_connected"] as? [[String:Any]] ?? [] {for (_,value) in item {guard let device=value as? [String:Any] else {continue};if (device["device_vendorID"] as? String)?.lowercased()=="0x2717",(device["device_productID"] as? String)?.lowercased()=="0x32b8" {matches.append(device)}}}}
   guard matches.count==1,let device=matches.first else {return .success((false,nil))}
   let raw=device["device_batteryLevelMain"] as? String
   let level=raw.flatMap{Int($0.trimmingCharacters(in:CharacterSet(charactersIn:"% ")))}.flatMap{(0...100).contains($0) ? $0 : nil}
   return .success((true,level))
  } catch {return .failure(error)}
 }
}
