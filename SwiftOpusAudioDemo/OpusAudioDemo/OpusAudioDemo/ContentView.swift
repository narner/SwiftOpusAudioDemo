//
//  ContentView.swift
//  OpusAudioDemo
//
//  Created by Nicholas Arner on 8/15/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    
    var body: some View {
        VStack {
            Text(audioManager.statusMessage)
                .padding()
            
            Button(action: {
                if audioManager.isRecording {
                    audioManager.stopRecordingAndPlay()
                } else {
                    audioManager.startRecording()
                }
            }) {
                Text(audioManager.isRecording ? "Stop Recording and Play" : "Start Recording")
                    .padding()
                    .background(audioManager.isRecording ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(!audioManager.hasMicrophonePermission || !audioManager.isAudioEngineReady)
        }
        .onAppear {
            audioManager.setup()
        }
    }
}
