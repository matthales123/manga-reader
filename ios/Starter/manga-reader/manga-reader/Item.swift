//
//  Item.swift
//  manga-reader
//
//  Created by Matt Hales on 3/28/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
