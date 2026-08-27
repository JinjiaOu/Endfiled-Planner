//
//  BlueprintDisclaimerView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/22/26.
//

import SwiftUI

struct BlueprintDisclaimerView: View {
    
    @Binding var isPresented: Bool
    @AppStorage("hasAcceptedBlueprintDisclaimer") private var hasAccepted = false
    
    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    // 点击背景不关闭
                }
            
            // 免责声明卡片
            VStack(spacing: 0) {
                
                // 顶部标题栏
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                    
                    Text("DISCLAIMER")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                .padding()
                .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                
                // 免责内容
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        // 标题
                        Text("蓝图分享免责声明")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        Divider()
                            .background(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3))
                        
                        // 条款1
                        DisclaimerItem(
                            number: "1",
                            title: "内容来源",
                            content: "本应用中的所有蓝图分享码均来自社区玩家自发贡献，开发者仅提供展示平台。"
                        )
                        
                        // 条款2
                        DisclaimerItem(
                            number: "2",
                            title: "使用风险",
                            content: "蓝图使用前请自行测试和验证，开发者不对蓝图的正确性、完整性或适用性做任何保证。使用蓝图导致的任何游戏内损失由玩家自行承担。"
                        )
                        
                        // 条款3
                        DisclaimerItem(
                            number: "3",
                            title: "知识产权",
                            content: "所有蓝图的知识产权归原作者所有。本应用仅作为展示平台，不主张任何蓝图的所有权。"
                        )
                        
                        // 条款4
                        DisclaimerItem(
                            number: "4",
                            title: "内容审核",
                            content: "虽然我们尽力审核蓝图内容，但无法保证所有内容的准确性。如发现问题蓝图，请及时反馈。"
                        )
                        
                        // 条款5
                        DisclaimerItem(
                            number: "5",
                            title: "游戏数据",
                            content: "本应用为《明日方舟：终末地》游戏的非官方辅助工具，所有内容均为虚拟游戏数据，与现实无关。"
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding()
                }
                .background(Color(red: 0.12, green: 0.13, blue: 0.16))
                
                // 底部按钮
                VStack(spacing: 12) {
                    // 同意并继续按钮
                    Button {
                        acceptAndContinue()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("我已阅读并同意")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            ZStack {
                                Rectangle()
                                    .fill(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2))
                                Rectangle()
                                    .stroke(Color(red: 1.0, green: 0.8, blue: 0.0), lineWidth: 2)
                            }
                        )
                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                    }
                    
                    // 取消按钮
                    Button {
                        isPresented = false
                    } label: {
                        Text("取消")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding()
                .background(Color(red: 0.08, green: 0.09, blue: 0.12))
            }
            .frame(maxWidth: 500, maxHeight: 600)
            .clipShape(RoundedRectangle(cornerRadius: 0))
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.5),
                                Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), radius: 20)
            .padding()
        }
    }
    
    private func acceptAndContinue() {
        hasAccepted = true
        isPresented = false
    }
}

// MARK: - 免责条款项组件

struct DisclaimerItem: View {
    let number: String
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // 编号标签
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2))
                        .frame(width: 28, height: 28)
                    
                    Text(number)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text(content)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(4)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(red: 0.08, green: 0.09, blue: 0.12)
            .ignoresSafeArea()
        
        BlueprintDisclaimerView(isPresented: .constant(true))
    }
}
