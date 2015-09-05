//
//  Bucket.swift
//  FlickFinder
//
//  Created by Brian on 05/09/15.
//  Copyright (c) 2015 Brian King. All rights reserved.
//

import Foundation

class JsonBucket {
	var contents = [[String: AnyObject]]()
	var capacity: Int
	let autoStir: Bool

	var count: Int { return contents.count }
	var isFull: Bool { return count >= capacity }

	init(capacity: Int, autoStir: Bool = true) {
		self.capacity = capacity
		self.autoStir = autoStir
	}

	func add(jsonObjects: [[String: AnyObject]]) {
		let freeSpace = capacity - count
		if freeSpace > jsonObjects.count {
			contents += jsonObjects
		} else {
			contents += Array(jsonObjects[0..<freeSpace])
		}
		if autoStir {
			stir()
		}
	}

	func stir() {
		contents = _shuffle(contents)
	}

	func take() -> [String: AnyObject]? {
		if contents.count > 0 {
			return contents.removeAtIndex(0)
		}
		return nil
	}

	func empty() {
		contents.removeAll(keepCapacity: true)
	}

	func _shuffle<C: MutableCollectionType where C.Index == Int>(var list: C) -> C {
		let c = Swift.count(list)
		if c < 2 { return list }
		for i in 0..<(c - 1) {
			let j = Int(arc4random_uniform(UInt32(c - i))) + i
			swap(&list[i], &list[j])
		}
		return list
	}
}