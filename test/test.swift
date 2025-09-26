// Copyright 2025 by CodingMarkus
// https://github.com/CodingMarkus/NSKeyedArchiveViewer
//
// Distributed under the GNU AFFERO GENERAL PUBLIC LICENSE, Version 3
// https://www.gnu.org/licenses/agpl-3.0.html

import Foundation

final class Person: NSObject, NSSecureCoding {
	static var supportsSecureCoding: Bool { true }

	let name: String
	let birthDate: Date

	init(name: String, birthDate: Date) {
		self.name = name
		self.birthDate = birthDate
	}

	required convenience init?(coder: NSCoder) {
		guard
			let name = coder.decodeObject(
				of: NSString.self, forKey: "name"
			) as String?,
		    let date = coder.decodeObject(
				of: NSDate.self, forKey: "birthDate"
			) as Date?
			else { return nil }
		self.init(name: name, birthDate: date)
	}

	func encode(with coder: NSCoder) {
		coder.encode(name as NSString, forKey: "name")
		coder.encode(birthDate as NSDate, forKey: "birthDate")
	}
}


final class Department: NSObject, NSSecureCoding {
	static var supportsSecureCoding: Bool { true }

	let name: String
	let people: [Person]

	init(name: String, people: [Person]) {
		self.name = name
		self.people = people
	}

	required convenience init?(coder: NSCoder) {
		guard
			let name = coder.decodeObject(
				of: NSString.self, forKey: "name"
			) as String?,
			let people = coder.decodeObject(
				of: [NSArray.self, Person.self],
				forKey: "people"
			) as? [Person]
			else { return nil }
		self.init(name: name, people: people)
	}

	func encode(with coder: NSCoder) {
		coder.encode(name as NSString, forKey: "name")
		coder.encode(people as NSArray, forKey: "people")
	}
}


final class Branch: NSObject, NSSecureCoding {
	static var supportsSecureCoding: Bool { true }

	let name: String
	let departments: [Department]

	init(name: String, departments: [Department]) {
		self.name = name
		self.departments = departments
	}

	required convenience init?(coder: NSCoder) {
		guard
			let name = coder.decodeObject(
					of: NSString.self, forKey: "name"
			) as String?,
		    let deps = coder.decodeObject(
				of: [NSArray.self, Department.self],
				forKey: "departments"
			) as? [Department]
			else { return nil }
		self.init(name: name, departments: deps)
	}

	func encode(with coder: NSCoder) {
		coder.encode(name as NSString, forKey: "name")
		coder.encode(departments as NSArray, forKey: "departments")
	}
}



// --- Top-level "main" for script usage --------------------------------------

func buildSampleBranch() -> Branch {
	let df = ISO8601DateFormatter()
	let p1 = Person(name: "Alice Smith",
	    birthDate: df.date(from: "1990-05-10T00:00:00Z")!
	)
	let p2 = Person(name: "John Miller",
		birthDate: df.date(from: "1984-11-02T00:00:00Z")!
	)
	let p3 = Person(name: "Emma Johnson",
		birthDate: df.date(from: "1996-03-21T00:00:00Z")!
	)
	let p4 = Person(name: "Tom Walker",
		birthDate: df.date(from: "1992-07-14T00:00:00Z")!
	)
	let p5 = Person(name: "Sara Brown",
		birthDate: df.date(from: "1988-01-30T00:00:00Z")!
	)

	let d1 = Department(name: "Engineering", people: [p1, p2, p3])
	let d2 = Department(name: "Sales",       people: [p4])
	let d3 = Department(name: "HR",          people: [p5])

	return Branch(name: "New York Office", departments: [d1, d2, d3])
}

do {
	let branch = buildSampleBranch()
	let data = try NSKeyedArchiver.archivedData(
		withRootObject: branch, requiringSecureCoding: true
	)
	let url = URL(fileURLWithPath: "test.archive.plist")
	try data.write(to: url, options: .atomic)
	print("Wrote archive to \(url.path)")

	// Optional: verify unarchive
	let loaded = try NSKeyedUnarchiver.unarchivedObject(
		ofClass: Branch.self, from: data
	)
	print("Loaded branch: \(loaded?.name ?? "?"), "
	     + "departments: \(loaded?.departments.count ?? 0)"
	)

} catch {
	fputs("Error: \(error)\n", stderr)
	exit(1)
}