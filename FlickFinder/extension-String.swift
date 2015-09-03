//
//  extension-String.swift
//  FlickFinder
//
//  Created by Brian on 03/09/15.
//  Copyright (c) 2015 Brian King. All rights reserved.
//

import Foundation

// From http://stackoverflow.com/a/31432010/948341
extension String {
	func toDouble() -> Double? {
		let numberFormatter = NSNumberFormatter()
		numberFormatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")
		return numberFormatter.numberFromString(self)?.doubleValue
	}
}