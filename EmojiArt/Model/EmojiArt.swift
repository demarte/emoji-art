//
//  EmojiArt.swift
//  EmojiArt
//
//  Created by Ivan De Martino on 6/20/20.
//  Copyright © 2020 Ivan De Martino. All rights reserved.
//

import Foundation

struct EmojiArt: Codable {
  
  var backgroundURL: URL?
  var emojis = [Emoji]()
  
  struct Emoji: Identifiable, Codable, Hashable {
    let text: String
    var size: Int
    var x: Int
    var y: Int
    var id: Int
    
    fileprivate init(text: String, size: Int, x: Int, y: Int, id: Int) {
      self.text = text
      self.size = size
      self.x = x
      self.y = y
      self.id = id
    }
  }
  
  var json: Data? {
    return try? JSONEncoder().encode(self)
  }
  
  init?(json: Data?) {
    if json != nil, let newEmojiArt = try? JSONDecoder().decode(EmojiArt.self, from: json!) {
      self = newEmojiArt
    } else {
      return nil
    }
  }
  
  init() { }
  
  private var uniqueEmojiId = 0
  
  mutating func addEmoji(text: String, size: Int, x: Int, y: Int) {
    uniqueEmojiId += 1
    emojis.append(Emoji(text: text, size: size, x: x, y: y, id: uniqueEmojiId))
  }
  
  mutating func removeEmoji(_ emoji: Emoji) {
    if let index = emojis.firstIndex(matching: emoji) {
      emojis.remove(at: index)
    }
  }
}
