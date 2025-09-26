// Copyright 2025 by CodingMarkus
// https://github.com/CodingMarkus/NSKeyedArchiveViewer
//
// Distributed under the GNU AFFERO GENERAL PUBLIC LICENSE, Version 3
// https://www.gnu.org/licenses/agpl-3.0.html

import Darwin
import Foundation

// ----------------------------------------------------------------------------

enum ArchvieError: Error  {
    case invalidFormat( msg: String )
    case cannotReadUID
}

// ----------------------------------------------------------------------------

/*
    Helpers to access CFKeyedArchiverUID which is a private class I can
    otherwise not interact with.
*/

private typealias GetTypeIDFn = @convention(c) ( ) -> CFTypeID
private typealias GetValueFn  = @convention(c) ( CFTypeRef ) -> UInt64

private let _uidGetTypeID: GetTypeIDFn? = {
    guard let p = dlsym(dlopen(nil, RTLD_NOW),  "_CFKeyedArchiverUIDGetTypeID")
        else { return nil }
    return unsafeBitCast(p, to: GetTypeIDFn.self)
}()

private let _uidGetValue: GetValueFn? = {
    guard let p = dlsym(dlopen(nil, RTLD_NOW), "_CFKeyedArchiverUIDGetValue")
        else { return nil }
    return unsafeBitCast(p, to: GetValueFn.self)
}()


func getIndex( keyedArchiverUID uid: Any) -> UInt?
{
    // When archive had XML format
    if let d = uid as? [String: Any],
        let n = d["CF$UID"] as? UInt
        { return n }

    // When archive had binary format
    guard let getTypeID = _uidGetTypeID,
        let getValue = _uidGetValue
        else { return nil }
    let cf = uid as AnyObject
    if CFGetTypeID(cf) == getTypeID() { return UInt(getValue(cf)) }
    return nil
}

// ----------------------------------------------------------------------------

/*
    Helper class to store decoded CFKeyedArchiverUID as an object
*/

final class KeyedArchiverUID: NSObject {
    let index: UInt
    init( _ index: UInt ) { self.index = index }
    override var description: String { "UID(\(index))" }
}


// ----------------------------------------------------------------------------

/*
    Actual code to decode and dump arbitrary archives
*/

// All objects of $objects
var decodedObjects = [AnyObject]()


func decodeObjects( _ objects: [Any] ) throws -> [AnyObject]
{
	func mapValue(_ v: Any) throws -> AnyObject {
		// Resolve keyed-archiver UID references to indices
		if let idx = getIndex(keyedArchiverUID: v) {
			return KeyedArchiverUID(idx)
		}

		// Primitives
		if let n = v as? NSNumber { return n }
		if let s = v as? String {
            if s == "$null" { return NSNull() }
            return s as NSString
        }

		// Arrays
		if let a = v as? [Any] {
			let mapped = try a.map { try mapValue($0) }
			return mapped as NSArray
		}

		// Dictionaries
		if let d = v as? [String: Any] {
			var out = [String: AnyObject]()
			out.reserveCapacity(d.count)
			for (k, val) in d {
				out[k] = try mapValue(val)
			}
			return out as NSDictionary
		}

		// Fallback
		return v as AnyObject
	}

    return try objects.map { try mapValue($0) }
}


func dumpObjectTree( rootIdx: UInt )
{

    func hexString(_ data: Data) -> String
    {
        var s = ""
        s.reserveCapacity(data.count * 2)
        for b in data { s.append(String(format: "%02X", b)) }
        return "<" + s + ">"
    }


	func jsonString( _ s: String ) -> String
    {
		var r = s.replacingOccurrences(of: "\\", with: "\\\\")
		r = r.replacingOccurrences(of: "\"", with: "\\\"")
		r = r.replacingOccurrences(of: "\n", with: "\\n")
		return "\"" + r + "\""
	}


	func write( _ s: String, _ indent: Int, terminator: String = "\n" )
    {
		print(
            String(repeating: "\t", count: indent) + s,
            terminator: terminator
        )
	}


    func append( _ s: String, terminator: String = "" )
    {
		write(s, 0, terminator: terminator)
	}


	let dateFmt: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "en_US_POSIX")
		f.timeZone = TimeZone(secondsFromGMT: 0)
		f.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
		return f
	}()


	func className( fromClassUID uid: KeyedArchiverUID ) -> String
    {
		let idx = uid.index
		guard
            idx < decodedObjects.count,
			let desc = decodedObjects[Int(idx)] as? NSDictionary,
			let raw = desc["$classname"] as? NSString
		    else { return "<Object>" }
        return (raw as String)
	}


    func classHierarchy( fromClassUID uid: KeyedArchiverUID ) -> [String]
    {
        let idx = uid.index
        guard idx < decodedObjects.count,
              let desc = decodedObjects[Int(idx)] as? NSDictionary,
              let arr = desc["$classes"] as? NSArray
        else { return [] }
        return arr.compactMap { $0 as? String }
    }


	func resolved( _ v: AnyObject ) -> AnyObject
    {
		if let uid = v as? KeyedArchiverUID {
			let i = uid.index
			if i < decodedObjects.count { return decodedObjects[Int(i)] }
		}
		return v
	}


	func dumpValue( _ v: AnyObject, indent: Int,
        endline: Bool = true, inline: Bool = false )
    {
		// NSDictionary with $class => structured object
		if let d = v as? NSDictionary,
            let clsUID = d["$class"] as? KeyedArchiverUID
        {
			let cls = className(fromClassUID: clsUID)
			write("{", inline ? 0 : indent)
			write("\"class\": \"\(cls)\",", indent + 1)
            let supers = classHierarchy(fromClassUID: clsUID)
            if !supers.isEmpty {
                write("\"classes\": [", indent + 1)
                for i in 0..<supers.count {
                    write(jsonString(supers[i]), indent + 2,
                          terminator: i + 1 < supers.count ? ",\n" : "\n")
                }
                write("]", indent + 1, terminator: "")
                append(",\n")
            }

            if cls == "NSString" || cls == "NSMutableString" {
                if let sval = d["NS.string"] as? NSString {
                    write("\"value\": \(jsonString(sval as String))",
                        indent + 1
                    )
                } else {
                    write("\"value\": \(jsonString(""))", indent + 1)
                }
                write("}", indent, terminator: endline ? "\n" : "")
                return
            }

            if cls == "NSData" || cls == "NSMutableData" {
                if let blob = d["NS.data"] as? Data {
                    write("\"value\": \(jsonString(hexString(blob)))",
                        indent + 1
                    )
                } else if let blobNS = d["NS.data"] as? NSData {
                    let hexString = hexString(blobNS as Data)
                    write("\"value\": \(jsonString(hexString))",
                        indent + 1
                    )
                } else {
                    write("\"value\": \(jsonString("<>") )", indent + 1)
                }
                write("}", indent, terminator: endline ? "\n" : "")
                return
            }

			if cls == "NSArray" {
				write("\"values\": [", indent + 1)
				if let items = d["NS.objects"] as? NSArray {
					for i in 0..<items.count {
						let itm = resolved(items[i] as AnyObject)
						dumpValue(itm, indent: indent + 2, endline: false)
						if i + 1 < items.count {
                            append(",\n")
                        } else {
                            append("\n")
                        }
					}
				}
				write("]", indent + 1)
				write("}", indent, terminator: endline ? "\n" : "")
				return
			}

			if cls == "NSDate" {
                if let t = d["NS.time"] as? NSNumber {
                    let date = Date(
                        timeIntervalSinceReferenceDate: t.doubleValue
                    )
                    let dateStr = dateFmt.string(from: date)
                    write("\"value\": \(jsonString(dateStr))", indent + 1)
                } else {
                    write("\"value\": \(jsonString(""))", indent + 1)
                }
                write("}", indent, terminator: endline ? "\n" : "")
                return
			}

			// Custom object: dump all user properties except $class
			write("\"properties\": {", indent + 1)
			let keys = d.allKeys.compactMap { $0 as? String }
				.filter { $0 != "$class" }
				.sorted()
			for (n, key) in keys.enumerated() {
				write("\"\(key)\": ", indent + 2, terminator: "")
				let valObj = resolved(d[key]! as AnyObject)
				dumpValue(valObj, indent: indent + 2,
                    endline: false, inline: true
                )
				if n + 1 < keys.count {
                    append(",\n")
                } else {
                    append("\n")
                }
            }
			write("}", indent + 1)
			write("}", indent, terminator: endline ? "\n" : "")
			return
		}

		if let dict = v as? NSDictionary {
			write("{", inline ? 0 : indent)
			write("\"class\": \"NSDictionary\",", indent + 1)
			write("\"values\": {", indent + 1)
			let keys = dict.allKeys.compactMap { $0 as? String }.sorted()
			for (n, key) in keys.enumerated() {
				write("\"\(key)\": ", indent + 2, terminator: "")
				dumpValue(resolved(dict[key]! as AnyObject),
                    indent: indent + 2, endline: false, inline: true
                )
                if n + 1 < keys.count { append(",\n") } else { append("\n") }
        	}
			write("}", indent + 1)
			write("}", indent, terminator: endline ? "\n" : "")
			return
		}

		// NSString
		if let s = v as? NSString {
            write("{", inline ? 0 : indent)
            write("\"class\": \"NSString\",", indent + 1)
            write("\"value\": \(jsonString(s as String))", indent + 1)
            write("}", indent, terminator: endline ? "\n" : "")
            return
		}

        // Bool (NS/CFBoolean is a NSNumber subclass)
        if let nb = v as? NSNumber, CFGetTypeID(nb) == CFBooleanGetTypeID()
        {
            write("{", inline ? 0 : indent)
            write("\"class\": \"Bool\",", indent + 1)
            write("\"value\": \(nb.boolValue ? "true" : "false")", indent + 1)
            write("}", indent, terminator: endline ? "\n" : "")
            return
        }

        // NSData
        if let rawNSData = v as? NSData {
            let hexString = hexString(rawNSData as Data)
            write("{", inline ? 0 : indent)
            write("\"class\": \"NSData\",", indent + 1)
            write("\"value\": \(jsonString(hexString))", indent + 1)
            write("}", indent, terminator: endline ? "\n" : "")
            return
        }

		// NSNumber
		if let n = v as? NSNumber {
            write("{", inline ? 0 : indent)
            write("\"class\": \"NSNumber\",", indent + 1)
            write("\"value\": \(n)", indent + 1)
            write("}", indent, terminator: endline ? "\n" : "")
            return
		}

		// Null
		if v is NSNull {
			write("{", inline ? 0 : indent)
			write("\"class\": \"NSNull\"", indent + 1)
	    	write("}", indent, terminator: endline ? "\n" : "")
			return
		}

		// Fallback
		write("{", inline ? 0 : indent)
		write("\"class\": \"Object\"", indent + 1)
		write("}", indent, terminator: endline ? "\n" : "")
	}

	let i = Int(rootIdx)
	guard i >= 0 && i < decodedObjects.count else { return }
	dumpValue(decodedObjects[i], indent: 0)
}


func dumpArchive( dict: [String: Any] ) throws
{
    guard let name = dict["$archiver"] as? String else {
        throw ArchvieError.invalidFormat(msg: "Missing achiver name")
    }
    guard let version = dict["$version"] as? Int else {
        throw ArchvieError.invalidFormat(msg: "Missing achiver version")
    }
    print("Archiver: \(name)\nVersion: \(version)")

    guard let topDict = dict["$top"] as? [String: Any] else {
        throw ArchvieError.invalidFormat(msg: "Missing top dictionary")
    }

    var optRootIdx: UInt? = nil
    if let rootAny = topDict["root"] {
        guard let rootIdx = getIndex(keyedArchiverUID: rootAny) else {
            throw ArchvieError.cannotReadUID
        }
        optRootIdx = rootIdx
    }

    guard let objects = dict["$objects"] as? [Any] else  {
        throw ArchvieError.invalidFormat(msg: "Missing objects array")
    }

    decodedObjects = try decodeObjects(objects)

    let rootIdx: UInt
    if let r = optRootIdx {
        rootIdx = r
    } else {
        // Build implicit root as a plain NSDictionary mapping $top keys to
        // values that are UIDs become KeyedArchiverUID so they resolve later
        let implicit = NSMutableDictionary(capacity: topDict.count)
        for (k, v) in topDict {
            if let idx = getIndex(keyedArchiverUID: v) {
                implicit[k] = KeyedArchiverUID(idx)
            } else if let s = v as? String {
                implicit[k] = s as NSString
            } else if let n = v as? NSNumber {
                implicit[k] = n
            } else if let arr = v as? [Any] {
                // map simple arrays conservatively
                implicit[k] = (try? decodeObjects(arr)) as AnyObject?
                    ?? (arr as NSArray)
            } else if let d = v as? [String: Any] {
                // nested plain dict from $top is rare; store as NSDictionary
                implicit[k] = d as NSDictionary
            } else {
                implicit[k] = NSNull()
            }
        }
        decodedObjects.append(implicit)
        rootIdx = UInt(decodedObjects.count - 1)
    }

    dumpObjectTree(rootIdx: rootIdx)
}


// ----------------------------------------------------------------------------

/*
    Command line interaction and loading file
*/

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: \(args[0]) <plist file>\n", stderr)
    exit(EX_USAGE)
}

let path = args[1]
let fileURL = URL(fileURLWithPath: path)

var isDir: ObjCBool = false
if
	!FileManager.default.fileExists(
		atPath: fileURL.path, isDirectory: &isDir
	)
	|| isDir.boolValue
{
    fputs("Error: file not found or is a directory: \(fileURL.path)\n", stderr)
    exit(EX_NOINPUT)
}

do {
    let data = try Data(contentsOf: fileURL)

    var format = PropertyListSerialization.PropertyListFormat.xml
    let plist = try PropertyListSerialization.propertyList(
		from: data, options: [ ], format: &format
	)
	guard let dict = plist as? [String: Any] else {
		fputs("Not a valid archive\n", stderr)
		exit(EX_DATAERR)
	}
    do {
        try dumpArchive(dict: dict)
    } catch {
        fputs("Parsing archive failed: \(error)\n", stderr)
        exit(EX_DATAERR)
    }

} catch {
    fputs("Loading archive failed: \(error)\n", stderr)
    exit(EX_DATAERR)
}
exit(EXIT_SUCCESS)