//
//  EmojiArtDocumentView.swift
//  EmojiArt
//
//  Created by Ivan De Martino on 6/20/20.
//  Copyright © 2020 Ivan De Martino. All rights reserved.
//

import SwiftUI

struct EmojiArtDocumentView: View {
  
  @ObservedObject var document: EmojiArtDocument
  
  @State private var selectedEmojis: Set<EmojiArt.Emoji> = []
  
  var body: some View {
    VStack {
      ScrollView(.horizontal) {
        HStack {
          ForEach(EmojiArtDocument.palette.map { String($0) }, id: \.self) { emoji in
            Text("\(emoji)")
              .font(Font.system(size: self.defaultEmojiSize))
              .onDrag { NSItemProvider(object: emoji as NSString) }
          }
        }
        .padding(.horizontal)
      }
      Button(action: {
        self.selectedEmojis.forEach { self.document.removeEmoji($0) }
        self.selectedEmojis.removeAll()
      }) {
        Image(systemName: "trash")
      }
      .disabled(selectedEmojis.isEmpty)
      GeometryReader { geometry in
        ZStack {
          Color.white.overlay(
            OptionalImage(image: self.document.backgroundImage)
              .scaleEffect(self.backgroundScale())
              .offset(self.panOffset)
          )
            .gesture(self.tapGesture(in: geometry.size))
          ForEach(self.document.emojis) { emoji in
            Text(emoji.text)
              .font(animatableWithSize: emoji.fontSize * self.zoomScale)
              .position(self.position(for: emoji, in: geometry.size))
              .opacity(self.selectedEmojis.contains(matching: emoji) ? 0.5 : 1)
              .offset(self.selectedEmojis.contains(matching: emoji) ? self.gestureEmojiPanOffset : .zero)
              .gesture(self.panEmojiGesture())
              .onTapGesture {
                self.selectedEmojis.toggle(matching: emoji)
            }
          }
        }
        .clipped()
        .gesture(self.combinedGestures())
        .edgesIgnoringSafeArea([.bottom, .horizontal])
        .onDrop(of: ["public.image", "public.text"], isTargeted: nil) { providers, location in
          // SwiftUI bug (as of 13.4)? the location is supposed to be in our coordinate system
          // however, the y coordinate appears to be in the global coordinate system
          var location = CGPoint(x: location.x, y: geometry.convert(location, from: .global).y)
          location = CGPoint(x: location.x - geometry.size.width/2, y: location.y - geometry.size.height/2)
          location = CGPoint(x: location.x - self.panOffset.width, y: location.y - self.panOffset.height)
          location = CGPoint(x: location.x / self.zoomScale, y: location.y / self.zoomScale)
          return self.drop(providers: providers, at: location)
        }
      }
    }
  }
  
  // MARK: - Background Image Zoom -
  
  @State private var steadyStateZoomScale: CGFloat = 1.0
  @GestureState private var gestureZoomScale: CGFloat = 1.0
  
  private var zoomScale: CGFloat {
    steadyStateZoomScale * gestureZoomScale
  }
  
  private func zoomGesture() -> some Gesture {
    MagnificationGesture()
      .updating($gestureZoomScale) { latestGestureScale, gestureZoomScale, transaction in
        gestureZoomScale = latestGestureScale
    }
    .onEnded { finalGestureScale in
      if !self.selectedEmojis.isEmpty {
        self.selectedEmojis.forEach { self.document.scaleEmoji($0, by: finalGestureScale) }
      } else {
        self.steadyStateZoomScale *= finalGestureScale
      }
    }
  }
  
  private func backgroundScale() -> CGFloat {
    if selectedEmojis.isEmpty {
      return zoomScale
    } else {
      return steadyStateZoomScale
    }
  }
  
  // MARK: - Background Image Pan -
  
  @State private var steadyStatePanOffset: CGSize = .zero
  @GestureState private var gesturePanOffset: CGSize = .zero
  
  private var panOffset: CGSize {
    (steadyStatePanOffset + gesturePanOffset) * zoomScale
  }
  
  private func panGesture() -> some Gesture {
    DragGesture()
      .updating($gesturePanOffset) { latestDragGestureValue, gesturePanOffset, transaction in
        gesturePanOffset = latestDragGestureValue.translation / self.zoomScale
    }
    .onEnded { finalDragGestureValue in
      self.steadyStatePanOffset = self.steadyStatePanOffset + (finalDragGestureValue.translation / self.zoomScale)
    }
  }
  
  // MARK: - Combine Pan and Zoom -
  
  private func combinedGestures() -> some Gesture {
     panGesture().simultaneously(with: zoomGesture())
   }
  
  // MARK: - Emoji Pan -
  
  @GestureState private var gestureEmojiPanOffset: CGSize = .zero
  
  private func panEmojiGesture() -> some Gesture {
    DragGesture()
      .updating($gestureEmojiPanOffset) { latestDragGestureValue, gestureEmojiPanOffset, transaction in
        gestureEmojiPanOffset = latestDragGestureValue.translation
    }
      .onEnded { finalDragGestureValue in
        self.selectedEmojis.forEach { self.document.moveEmoji($0, by: finalDragGestureValue.translation / self.zoomScale) }
        self.selectedEmojis.removeAll()
    }
  }
  
  private func tapGesture(in size: CGSize) -> some Gesture {
    TapGesture(count: 2)
      .exclusively(before: TapGesture())
      .onEnded { gesture in
        switch gesture {
        case .first:
          withAnimation {
            self.zoomToFit(self.document.backgroundImage, in: size)
          }
        case .second:
          self.selectedEmojis.removeAll()
        }
    }
  }
  
  private func zoomToFit(_ image: UIImage?, in size: CGSize) {
    if let image = image, image.size.width > 0, image.size.height > 0 {
      let hZoom = size.width / image.size.width
      let vZoom = size.height / image.size.height
      self.steadyStatePanOffset = .zero
      self.steadyStateZoomScale = min(hZoom, vZoom)
    }
  }
  
  private func position(for emoji: EmojiArt.Emoji, in size: CGSize) -> CGPoint {
    var location = emoji.location
    let zScale = selectedEmojis.isEmpty ? zoomScale : steadyStateZoomScale
    location = CGPoint(x: location.x * zScale, y: location.y * zScale)
    location = CGPoint(x: location.x + size.width/2, y: location.y + size.height/2)
    location = CGPoint(x: location.x + panOffset.width, y: location.y + panOffset.height)
    return location
  }
  
  private func drop(providers: [NSItemProvider], at location: CGPoint) -> Bool {
    var found = providers.loadFirstObject(ofType: URL.self) { url in
      self.document.setBackgroundURL(url)
    }
    
    if !found {
      found = providers.loadObjects(ofType: String.self) { string in
        self.document.addEmoji(string, at: location, size: self.defaultEmojiSize)
      }
    }
    return found 
  }
  
  // MARK: - constants -
  
  private let defaultEmojiSize: CGFloat = 40
}
