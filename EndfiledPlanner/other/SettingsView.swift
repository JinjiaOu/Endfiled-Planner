//
//  SettingsView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI

struct SettingsView: View {
    
    @AppStorage("darkMode") private var darkMode = false
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("autoSave") private var autoSave = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.12)
                    .ignoresSafeArea()
                
                List {
                    
                    // 显示设置
                    Section {
                        Toggle(isOn: $showGrid) {
                            HStack {
                                Image(systemName: "square.grid.3x3")
                                    .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                Text("网格背景")
                                    .foregroundColor(.white)
                            }
                        }
                        .tint(Color(red: 1.0, green: 0.8, blue: 0.0))
                    } header: {
                        Text("DISPLAY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.13, blue: 0.16))
                    
                    // 功能设置
                    Section {
                        Toggle(isOn: $autoSave) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                                Text("自动保存")
                                    .foregroundColor(.white)
                            }
                        }
                        .tint(Color(red: 0.4, green: 0.8, blue: 0.2))
                    } header: {
                        Text("FUNCTIONS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.13, blue: 0.16))
                    
                    // 关于
                    Section {
                        HStack {
                            Text("VERSION")
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text("1.0.0")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                        }
                        
                        Button {
                            // 打开GitHub
                        } label: {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                Text("GitHub Repository")
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Button {
                            // 反馈
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.bubble")
                                    .foregroundColor(Color(red: 0.9, green: 0.5, blue: 0.2))
                                Text("Report Issue")
                                    .foregroundColor(.white)
                            }
                        }
                    } header: {
                        Text("ABOUT")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.13, blue: 0.16))
                    
                    // 数据管理
                    Section {
                        Button(role: .destructive) {
                            // 清除缓存
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear Cache")
                            }
                        }
                    } header: {
                        Text("DATA")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.13, blue: 0.16))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.09, blue: 0.12), for: .navigationBar)
        }
    }
}

#Preview {
    SettingsView()
}
