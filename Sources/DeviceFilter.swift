import Foundation
import IOKit.hid

/// Uses macOS's per-service keyboard mapping. Refuses to replace another tool's mapping.
final class DeviceFilter {
 private(set) var location:UInt32?
 private(set) var installed=false
 private var desired:[UInt64:UInt64]=[:]
 enum FilterError:LocalizedError {
  case noDevice, multipleDevices, noLocation, existingMapping, command(String), verification
  var errorDescription:String? {switch self {
   case .noDevice:return "未找到小米遥控器"
   case .multipleDevices:return "检测到多只同型号遥控器，无法安全选择"
   case .noLocation:return "无法识别遥控器的设备位置"
   case .existingMapping:return "该遥控器已有其他按键规则，未覆盖"
   case .command(let detail):return "系统按键规则操作失败：\(detail)"
   case .verification:return "系统没有确认按键拦截规则"
  }}
 }
 private func matching(_ location:UInt32)->String {"{\"VendorID\":10007,\"ProductID\":12984,\"LocationID\":\(location)}"}
 private func run(_ args:[String]) throws -> String {
  let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/hidutil");p.arguments=args
  let out=Pipe();p.standardOutput=out;p.standardError=out
  try p.run();let data=out.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit()
  let text=String(data:data,encoding:.utf8) ?? ""
  guard p.terminationStatus == 0 else {throw FilterError.command(text.trimmingCharacters(in:.whitespacesAndNewlines))}
  return text
 }
 private func read(_ location:UInt32) throws -> [UInt64:UInt64] {
  let text=try run(["property","--matching",matching(location),"--get","UserKeyMapping"])
  guard text.contains("UserKeyMapping"), text.contains("RegistryID"), text.split(separator:"\n").count > 1 else {throw FilterError.noDevice}
  if text.contains("(null)") {return [:]}
  let regex=try NSRegularExpression(pattern:"HIDKeyboardModifierMapping(Dst|Src)\\s*=\\s*([0-9]+)")
  let ns=text as NSString; var result:[UInt64:UInt64]=[:];var src:UInt64?;var dst:UInt64?
  for match in regex.matches(in:text,range:NSRange(location:0,length:ns.length)) {
   let key=ns.substring(with:match.range(at:1));guard let value=UInt64(ns.substring(with:match.range(at:2))) else {throw FilterError.verification}
   if key == "Src" {src=value} else {dst=value}
   if let a=src,let b=dst {result[a]=b;src=nil;dst=nil}
  }
  if text.contains("HIDKeyboardModifierMapping") && result.isEmpty {throw FilterError.verification}
  return result
 }
 private func write(_ location:UInt32,_ mapping:[UInt64:UInt64]) throws {
  let entries=mapping.keys.sorted().map { ["HIDKeyboardModifierMappingSrc":$0,"HIDKeyboardModifierMappingDst":mapping[$0]!] }
  let data=try JSONSerialization.data(withJSONObject:["UserKeyMapping":entries],options:[.sortedKeys])
  guard let json=String(data:data,encoding:.utf8) else {throw FilterError.verification}
  _=try run(["property","--matching",matching(location),"--set",json])
 }
 func install(manager:IOHIDManager,codes:[String:String]) throws {
  let all=IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
  guard !all.isEmpty else {throw FilterError.noDevice};guard all.count == 1,let device=all.first else {throw FilterError.multipleDevices}
  guard let number=IOHIDDeviceGetProperty(device,kIOHIDLocationIDKey as CFString) as? NSNumber,number.uint32Value != 0 else {throw FilterError.noLocation}
  let currentLocation=number.uint32Value
  var entries:[UInt64:UInt64]=[:]
  for value in codes.values {
   let parts=value.split(separator:":");guard parts.count == 2,let page=UInt64(parts[0]),let usage=UInt64(parts[1]),page==7,usage>0,usage<=0xffff else {continue}
   entries[(page << 32) | usage]=0
  }
  guard !entries.isEmpty else {throw FilterError.verification}
  let current=try read(currentLocation)
  guard current.isEmpty || (installed && location == currentLocation && current == desired) else {throw FilterError.existingMapping}
  try write(currentLocation,entries)
  do {guard try read(currentLocation) == entries else {throw FilterError.verification}}
  catch {try? write(currentLocation,[:]);throw error}
  location=currentLocation;desired=entries;installed=true
 }
 func remove() throws {
  guard installed,let location else {return}
  let current=try read(location)
  guard current == desired else {self.location=nil;installed=false;desired=[:];throw FilterError.existingMapping}
  try write(location,[:]);guard try read(location).isEmpty else {throw FilterError.verification}
  self.location=nil;installed=false;desired=[:]
 }
 func deviceDisconnected(){location=nil;installed=false;desired=[:]}
}
