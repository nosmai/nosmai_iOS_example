//
//  ContentView.swift
//  Nosmai-iOS-Example
//
//  Created by Developer vativeApps on 15/09/2025.
//

import SwiftUI

struct CameraFilterView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> VideoFilterController {
        let controller = VideoFilterController()
        return controller
    }
    
    func updateUIViewController(_ uiViewController: VideoFilterController, context: Context) {
    }
}

struct ContentView: View {
    var body: some View {
        NavigationView {
            CameraFilterView()
                .ignoresSafeArea(.all)
                .navigationBarHidden(true)
        }
    }
}
