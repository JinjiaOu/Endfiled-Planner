//
//  ResourceCalculatorView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI

struct ResourceCalculatorView: View {
    
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
                        with: .color(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.1)),
                        lineWidth: 0.5
                    )
                }
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // 页面横幅
                        VStack(alignment: .leading, spacing: 0) {
                            
                            // 顶部装饰条
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(Color(red: 0.4, green: 0.8, blue: 0.2))
                                    .frame(width: 40, height: 2)
                                
                                Circle()
                                    .fill(Color(red: 0.4, green: 0.8, blue: 0.2))
                                    .frame(width: 4, height: 4)
                                
                                Spacer()
                            }
                            .padding(.bottom, 12)
                            
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("SYSTEM STATUS")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                                    
                                    Text("资源计算引擎")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Text("Resource Calculator Engine")
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                Spacer()
                                
                                // 状态指示器
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 8, height: 8)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.orange.opacity(0.3), lineWidth: 4)
                                                .scaleEffect(1.5)
                                        )
                                    
                                    Text("DEV")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding(20)
                        }
                        .background(
                            ZStack {
                                Rectangle()
                                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                
                                Rectangle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.5),
                                                Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            }
                        )
                        .padding(.horizontal)
                        .padding(.top, 20)
                        
                        // 开发中提示卡片
                        VStack(spacing: 16) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 60))
                                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.5))
                            
                            Text("UNDER DEVELOPMENT")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                            
                            Text("功能开发中")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                FeatureItem(text: "原材料需求计算", color: Color(red: 0.4, green: 0.8, blue: 0.2))
                                FeatureItem(text: "生产成本估算", color: Color(red: 0.4, green: 0.8, blue: 0.2))
                                FeatureItem(text: "批量生产规划", color: Color(red: 0.4, green: 0.8, blue: 0.2))
                                FeatureItem(text: "资源优化建议", color: Color(red: 0.4, green: 0.8, blue: 0.2))
                            }
                            .padding(.top, 8)
                        }
                        .padding(30)
                        .frame(maxWidth: .infinity)
                        .background(
                            ZStack {
                                Rectangle()
                                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                
                                Rectangle()
                                    .stroke(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.2), lineWidth: 1)
                            }
                        )
                        .padding(.horizontal)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                        
                        Text("RESOURCE CALCULATOR")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.09, blue: 0.12), for: .navigationBar)
        }
    }
}

// 功能列表项
struct FeatureItem: View {
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundColor(color.opacity(0.6))
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

#Preview {
    ResourceCalculatorView()
}
