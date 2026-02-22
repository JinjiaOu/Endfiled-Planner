//
//  BlueprintSetDetailView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/21/26.
//

import SwiftUI

struct BlueprintSetDetailView: View {
    
    let blueprintSet: BlueprintSet
    @Environment(\.dismiss) var dismiss
    @State private var copiedBlueprintId: String?
    
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
                        
                        // 蓝图集信息卡片
                        VStack(alignment: .leading, spacing: 16) {
                            
                            // 标题区
                            HStack {
                                HStack(spacing: 4) {
                                    Text(blueprintSet.region)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    
                                    Text("·")
                                        .foregroundColor(.white.opacity(0.4))
                                    
                                    Text(blueprintSet.location)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3))
                                )
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 10))
                                    Text("\(blueprintSet.blueprints.count)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.2))
                                )
                            }
                            
                            // 名称
                            Text(blueprintSet.name)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                            
                            // 作者
                            HStack(spacing: 8) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 14))
                                Text("作者：\(blueprintSet.author)")
                                    .font(.system(size: 14))
                            }
                            .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                            
                            // 描述
                            if !blueprintSet.description.isEmpty {
                                Text(blueprintSet.description)
                                    .font(.system(size: 15))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineSpacing(4)
                            }
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
                        
                        // 蓝图列表
                        VStack(spacing: 0) {
                            // 标题栏
                            HStack {
                                Rectangle()
                                    .fill(Color(red: 0.2, green: 0.6, blue: 0.9))
                                    .frame(width: 3, height: 16)
                                
                                Text("BLUEPRINT LIST")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Spacer()
                                
                                Text("\(blueprintSet.blueprints.count) ITEMS")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                            
                            // 蓝图项列表
                            VStack(spacing: 0) {
                                ForEach(blueprintSet.blueprints.sorted(by: { $0.order < $1.order })) { blueprint in
                                    BlueprintItemRow(
                                        blueprint: blueprint,
                                        isCopied: copiedBlueprintId == blueprint.id,
                                        onCopy: {
                                            copyToClipboard(blueprint.code, id: blueprint.id)
                                        }
                                    )
                                    
                                    if blueprint.id != blueprintSet.blueprints.last?.id {
                                        Divider()
                                            .overlay(Color.white.opacity(0.05))
                                            .padding(.horizontal, 16)
                                    }
                                }
                            }
                            .background(Color(red: 0.12, green: 0.13, blue: 0.16))
                        }
                        .background(
                            Rectangle()
                                .stroke(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.2), lineWidth: 1)
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
    
    private func copyToClipboard(_ code: String, id: String) {
        UIPasteboard.general.string = code
        copiedBlueprintId = id
        
        // 1秒后重置
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            copiedBlueprintId = nil
        }
    }
}

// MARK: - 蓝图项行

struct BlueprintItemRow: View {
    let blueprint: BlueprintItem
    let isCopied: Bool
    let onCopy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // 顶部：序号 + 名称
            HStack(alignment: .top, spacing: 12) {
                // 序号徽章
                Text("\(blueprint.order)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.15))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), lineWidth: 2)
                    )
                
                // 名称和备注
                VStack(alignment: .leading, spacing: 6) {
                    Text(blueprint.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if !blueprint.notes.isEmpty {
                        Text(blueprint.notes)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                }
                
                Spacer()
            }
            
            // 蓝图码区域
            HStack(spacing: 0) {
                // 蓝图码
                HStack(spacing: 8) {
                    Image(systemName: "barcode")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                    
                    Text(blueprint.code)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                .overlay(
                    Rectangle()
                        .stroke(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.3), lineWidth: 1)
                )
                
                // 复制按钮
                Button {
                    onCopy()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 12))
                        Text(isCopied ? "COPIED" : "COPY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(isCopied ? Color(red: 0.4, green: 0.8, blue: 0.2) : Color(red: 0.2, green: 0.6, blue: 0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isCopied
                            ? Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.15)
                            : Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.15)
                    )
                    .overlay(
                        Rectangle()
                            .stroke(
                                isCopied
                                    ? Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.5)
                                    : Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.5),
                                lineWidth: 1
                            )
                    )
                }
            }
        }
        .padding(16)
    }
}

#Preview {
    BlueprintSetDetailView(blueprintSet: BlueprintSet(
        id: "set_001",
        name: "不用手拿植物——一键毕业省钱版",
        author: "示例UP主",
        region: "四号谷地",
        location: "枢纽区",
        description: "完整的自动化生产线系列",
        blueprints: [
            BlueprintItem(id: "bp_001", order: 1, name: "分基地全发电", code: "EF01081OupAE8706t79", notes: "一矿分基地+一基段"),
            BlueprintItem(id: "bp_002", order: 2, name: "分基地半发电", code: "EF010i5uiE49e55rruDeO", notes: "高级电池4.5")
        ]
    ))
}
