//
//  BlueprintSetCard.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/21/26.
//

import SwiftUI

struct BlueprintSetCard: View {
    let blueprintSet: BlueprintSet
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // 顶部信息栏
            HStack {
                // 地区标签
                HStack(spacing: 4) {
                    Text(blueprintSet.region)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    
                    Text("·")
                        .foregroundColor(.white.opacity(0.4))
                    
                    Text(blueprintSet.location)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3))
                )
                
                Spacer()
                
                // 蓝图数量
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                    Text("\(blueprintSet.blueprints.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.2))
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(red: 0.08, green: 0.09, blue: 0.12))
            
            // 主内容区
            VStack(alignment: .leading, spacing: 12) {
                
                // 蓝图集名称
                Text(blueprintSet.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                // 作者
                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                    
                    Text(blueprintSet.author)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // 描述
                if !blueprintSet.description.isEmpty {
                    Text(blueprintSet.description)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                }
                
                Divider()
                    .overlay(Color.white.opacity(0.1))
                
                // 蓝图预览
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                    
                    Text("包含 \(blueprintSet.blueprints.count) 个蓝图")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.5))
                }
            }
            .padding(16)
            .background(Color(red: 0.12, green: 0.13, blue: 0.16))
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3),
                            Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.1), radius: 8, x: 0, y: 4)
    }
}
