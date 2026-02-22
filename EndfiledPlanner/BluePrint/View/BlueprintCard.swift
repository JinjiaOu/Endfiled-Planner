//
//  BlueprintCard.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/21/26.
//

import SwiftUI

struct BlueprintCard: View {
    let blueprint: Blueprint
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // 顶部信息栏
            HStack {
                // 地区标签
                Text(blueprint.region)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3))
                    )
                
                Spacer()
                
                // ID 标识
                Text("ID: \(blueprint.id)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(red: 0.08, green: 0.09, blue: 0.12))
            
            // 主内容区
            VStack(alignment: .leading, spacing: 12) {
                
                // 蓝图名称
                Text(blueprint.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                // 作者
                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                    
                    Text(blueprint.author)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // 备注
                if !blueprint.notes.isEmpty {
                    Text(blueprint.notes)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                }
                
                Divider()
                    .overlay(Color.white.opacity(0.1))
                
                // 蓝图码预览
                HStack(spacing: 6) {
                    Image(systemName: "barcode")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                    
                    Text(blueprint.code)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                        .lineLimit(1)
                    
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
