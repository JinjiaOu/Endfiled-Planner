//
//  BlueprintDetailView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/21/26.
//

import SwiftUI

struct BlueprintDetailView: View {
    
    let blueprint: Blueprint
    @Environment(\.dismiss) var dismiss
    @State private var showCopyConfirmation = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 深色背景
                Color(red: 0.08, green: 0.09, blue: 0.12)
                    .ignoresSafeArea()
                
                // 网格背景
                Canvas { context, size in
                    let spacing: CGFloat = 30
                    var path = Path()
                    for x in stride(from: 0, through: size.width, by: spacing) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for y in stride(from: 0, through: size.height, by: spacing) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(
                        path,
                        with: .color(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.1)),
                        lineWidth: 0.5
                    )
                }
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        
                        // 标题区
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(blueprint.region)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3))
                                    )
                                
                                Spacer()
                                
                                Text("ID: \(blueprint.id)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            
                            Text(blueprint.name)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            
                            HStack(spacing: 8) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 14))
                                Text("作者：\(blueprint.author)")
                                    .font(.system(size: 14))
                            }
                            .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                        }
                        .padding()
                        .background(
                            ZStack {
                                Rectangle()
                                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                Rectangle()
                                    .stroke(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), lineWidth: 1)
                            }
                        )
                        .padding(.horizontal)
                        
                        // 备注
                        if !blueprint.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Rectangle()
                                        .fill(Color(red: 0.2, green: 0.6, blue: 0.9))
                                        .frame(width: 3, height: 16)
                                    
                                    Text("NOTES")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                Text(blueprint.notes)
                                    .font(.system(size: 15))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineSpacing(4)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                ZStack {
                                    Rectangle()
                                        .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                    Rectangle()
                                        .stroke(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.2), lineWidth: 1)
                                }
                            )
                            .padding(.horizontal)
                        }
                        
                        // 蓝图码
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Rectangle()
                                    .fill(Color(red: 0.2, green: 0.6, blue: 0.9))
                                    .frame(width: 3, height: 16)
                                
                                Text("BLUEPRINT CODE")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Spacer()
                                
                                Button {
                                    copyToClipboard(blueprint.code)
                                    showCopyConfirmation = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: showCopyConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                                        Text(showCopyConfirmation ? "COPIED" : "COPY")
                                    }
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(showCopyConfirmation ? Color(red: 0.4, green: 0.8, blue: 0.2) : Color(red: 0.2, green: 0.6, blue: 0.9))
                                }
                            }
                            
                            Text(blueprint.code)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                                .overlay(
                                    Rectangle()
                                        .stroke(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.3), lineWidth: 1)
                                )
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            ZStack {
                                Rectangle()
                                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                Rectangle()
                                    .stroke(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.2), lineWidth: 1)
                            }
                        )
                        .padding(.horizontal)
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.09, blue: 0.12), for: .navigationBar)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        
        // 1秒后重置提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showCopyConfirmation = false
        }
    }
}

#Preview {
    BlueprintDetailView(blueprint: Blueprint(
        id: "001",
        name: "示例蓝图",
        author: "测试作者",
        region: "谷地",
        code: "PREVIEW-CODE-123",
        notes: "这是一个用于预览的示例蓝图"
    ))
}
