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
  @State private var chosenPalette: String = ""

  init(document: EmojiArtDocument) {
    self.document = document
    _chosenPalette = State(wrappedValue: document.defaultPalette)
  }
  
  var body: some View {
    VStack {
      HStack {
        PaletteChooser(document: self.document, chosenPalette: $chosenPalette)
        ScrollView(.horizontal) {
          HStack {
            ForEach(chosenPalette.map { String($0) }, id: \.self) { emoji in
              Text("\(emoji)")
                .font(Font.system(size: self.defaultEmojiSize))
                .onDrag { NSItemProvider(object: emoji as NSString) }
            }
          }
          .padding(.horizontal)
        }
      }
      GeometryReader { geometry in
        ZStack {
          Color.white.overlay(
            OptionalImage(image: self.document.backgroundImage)
              .scaleEffect(self.backgroundScale())
              .offset(self.panOffset)
          )
            .gesture(self.tapGesture(in: geometry.size))
          if self.isLoading {
            Image(systemName: "hourglass").imageScale(.large).spinning()
          }
          else {
            ForEach(self.document.emojis) { emoji in
              Text(emoji.text)
                .font(animatableWithSize: self.size(for: emoji))
                .position(self.position(for: emoji, in: geometry.size))
                .opacity(self.selectedEmojis.contains(matching: emoji) ? 0.5 : 1)
                .offset(self.offset(for: emoji, in: geometry.size))
                .gesture(self.panEmojiGesture(in: geometry.size))
                .onTapGesture {
                  self.selectedEmojis.toggle(matching: emoji)
              }
            }
          }
        }
        .clipped()
        .gesture(self.combinedGestures())
        .edgesIgnoringSafeArea([.bottom, .horizontal])
        .onReceive(self.document.$backgroundImage) { image in
          self.zoomToFit(image, in: geometry.size)
        }
        .onDrop(of: ["public.image", "public.text"], isTargeted: nil) { providers, location in
          // SwiftUI bug (as of 13.4)? the location is supposed to be in our coordinate system
          // however, the y coordinate appears to be in the global coordinate system
          var location = CGPoint(x: location.x, y: geometry.convert(location, from: .global).y)
          location = CGPoint(x: location.x - geometry.size.width/2, y: location.y - geometry.size.height/2)
          location = CGPoint(x: location.x - self.panOffset.width, y: location.y - self.panOffset.height)
          location = CGPoint(x: location.x / self.zoomScale, y: location.y / self.zoomScale)
          return self.drop(providers: providers, at: location)
        }
        .navigationBarItems(leading: Button(action: {
          if let url = UIPasteboard.general.url, url != self.document.backgroundURL {
            self.confirmBackgroundPaste = true
          } else {
            self.explainBackgroundPaste = true
          }
        }, label: {
          Image(systemName: "doc.on.clipboard").imageScale(.large)
            .alert(isPresented: self.$explainBackgroundPaste) {
              return Alert(
                title: Text("Paste Background"),
                message: Text("Copy the URL of an image to the clip board and touch this button to make it the background of your document."),
                dismissButton: .default(Text("OK"))
              )
          }
        }), trailing:  Button(action: {
          self.selectedEmojis.forEach { self.document.removeEmoji($0) }
          self.selectedEmojis.removeAll()
        }) {
          Image(systemName: "trash").imageScale(.large)
        }
        .disabled(self.selectedEmojis.isEmpty))
      }
      .zIndex(-1)
    }
    .alert(isPresented: self.$confirmBackgroundPaste) {
      Alert(
        title: Text("Paste Background"),
        message: Text("Replace your background with \(UIPasteboard.general.url?.absoluteString ?? "nothing")?."),
        primaryButton: .default(Text("OK")) {
          self.document.backgroundURL = UIPasteboard.general.url
        },
        secondaryButton: .cancel()
      )
    }
  }

  @State private var explainBackgroundPaste = false
  @State private var confirmBackgroundPaste = false

  var isLoading: Bool {
    document.backgroundURL != nil && document.backgroundImage == nil
  }
  
  // MARK: - Background Image Zoom -
  
  @GestureState private var gestureZoomScale: CGFloat = 1.0
  
  private var zoomScale: CGFloat {
    document.steadyStateZoomScale * gestureZoomScale
  }
  
  private func zoomGesture() -> some Gesture {
    MagnificationGesture()
      .updating($gestureZoomScale) { latestGestureScale, gestureZoomScale, transaction in
        gestureZoomScale = latestGestureScale
    }
    .onEnded { finalGestureScale in
      if self.selectedEmojis.isEmpty {
        self.document.steadyStateZoomScale *= finalGestureScale
      } else {
        self.selectedEmojis.forEach { self.document.scaleEmoji($0, by: finalGestureScale) }
      }
    }
  }
  
  private func backgroundScale() -> CGFloat {
    if selectedEmojis.isEmpty {
      return zoomScale
    } else {
      return document.steadyStateZoomScale
    }
  }

  private func size(for emoji: EmojiArt.Emoji) -> CGFloat {
    if selectedEmojis.isEmpty || selectedEmojis.contains(matching: emoji) {
      return emoji.fontSize * zoomScale
    } else {
      return emoji.fontSize * document.steadyStateZoomScale
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
  @GestureState private var dragLocation: CGPoint = .zero
  
  private func panEmojiGesture(in size: CGSize) -> some Gesture {
    DragGesture()
      .updating($dragLocation) { latestDragGestureValue, dragLocation, transaction in
        dragLocation = latestDragGestureValue.startLocation
    }
    .updating($gestureEmojiPanOffset) { latestDragGestureValue, gestureEmojiPanOffset, transaction in
      gestureEmojiPanOffset = latestDragGestureValue.translation
    }
    .onEnded { finalDragGestureValue in
      self.selectedEmojis.forEach { self.document.moveEmoji($0, by: finalDragGestureValue.translation / self.zoomScale) }
      for emoji in self.document.emojis {
        if self.isDragging(emoji: emoji, in: size, dragStartPosition: finalDragGestureValue.startLocation) {
          self.document.moveEmoji(emoji, by: finalDragGestureValue.translation / self.zoomScale)
        }
      }
    }
  }
  
  private func offset(for emoji: EmojiArt.Emoji, in size: CGSize) -> CGSize {
    if selectedEmojis.contains(matching: emoji) || isDragging(emoji: emoji, in: size, dragStartPosition: dragLocation) {
      return gestureEmojiPanOffset
    } else {
      return .zero
    }
  }
  
  private func isDragging(emoji: EmojiArt.Emoji, in size: CGSize, dragStartPosition: CGPoint) -> Bool {
    var emojiPosition = position(for: emoji, in: size)
    emojiPosition = CGPoint(x: emojiPosition.x - CGFloat(emoji.size/2), y: emojiPosition.y - CGFloat(emoji.size/2))
    let emojiRect = CGRect(origin: emojiPosition, size: CGSize(width: emoji.size, height: emoji.size))
    
    return emojiRect.contains(dragStartPosition)
  }
  
  // MARK: - Tap Gesture -
  
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
    if let image = image, image.size.width > 0, image.size.height > 0, size.width > 0, size.height > 0 {
      let hZoom = size.width / image.size.width
      let vZoom = size.height / image.size.height
      self.steadyStatePanOffset = .zero
      self.document.steadyStateZoomScale = min(hZoom, vZoom)
    }
  }
  
  private func position(for emoji: EmojiArt.Emoji, in size: CGSize) -> CGPoint {
    var location = emoji.location
    let zScale = selectedEmojis.isEmpty ? zoomScale : document.steadyStateZoomScale
    location = CGPoint(x: location.x * zScale, y: location.y * zScale)
    location = CGPoint(x: location.x + size.width/2, y: location.y + size.height/2)
    location = CGPoint(x: location.x + panOffset.width, y: location.y + panOffset.height)
    return location
  }
  
  private func drop(providers: [NSItemProvider], at location: CGPoint) -> Bool {
    var found = providers.loadFirstObject(ofType: URL.self) { url in
      self.document.backgroundURL = url
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
