//
//  MyLayoutsView.swift
//  EndfiledPlanner
//

import SwiftUI

/// "我的布局"列表：缩略图 + 名字 + 来源地图 + 建筑数 + 时间；点一个放到画布上，左滑删除/改名，长按也能改名删除
struct MyLayoutsView: View {
    @ObservedObject var store: MyLayoutStore
    /// 当前画布的地图，来源地图不一样时标出来
    let currentMap: MapType
    /// 点了某个布局：外面关掉列表后开始摆
    var onPlace: (SavedLayout) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: SavedLayout? = nil
    @State private var renameText = ""
    @State private var deleting: SavedLayout? = nil

    private let background = Color(red: 0.08, green: 0.09, blue: 0.12)
    private let accent = Color(red: 0.9, green: 0.5, blue: 0.2)

    var body: some View {
        NavigationStack {
            Group {
                if store.layouts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 34))
                            .foregroundColor(.white.opacity(0.3))
                        Text("还没有保存的布局")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                        Text("在画布上用「框选」选中一组建筑，点「存为布局」")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.layouts) { saved in
                            Button {
                                onPlace(saved)
                                dismiss()
                            } label: {
                                row(saved)
                            }
                            .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { deleting = saved } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    Button { startRename(saved) } label: {
                                        Label("改名", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button { startRename(saved) } label: { Label("改名", systemImage: "pencil") }
                                    Button(role: .destructive) { deleting = saved } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                        Text("点一个布局放到画布上")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(background)
            .navigationTitle("我的布局")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.foregroundColor(accent)
                }
            }
            .alert("改名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("布局名字", text: $renameText)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") {
                    if let renaming { store.rename(renaming.id, to: renameText) }
                    renaming = nil
                }
            }
            .alert("删除布局", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("删除", role: .destructive) {
                    if let deleting { store.delete(deleting.id) }
                    deleting = nil
                }
            } message: {
                Text("「\(deleting?.name ?? "")」删除后不能恢复")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func startRename(_ saved: SavedLayout) {
        renameText = saved.name
        renaming = saved
    }

    private func row(_ saved: SavedLayout) -> some View {
        HStack(spacing: 12) {
            LayoutThumbnail(layout: saved)
                .frame(width: 72, height: 72)
                .background(Color(red: 0.06, green: 0.07, blue: 0.10))
                .overlay(Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text(saved.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(saved.mapType.displayName)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(saved.mapType == currentMap ? Color.white.opacity(0.12) : accent.opacity(0.25))
                        .foregroundColor(saved.mapType == currentMap ? .white.opacity(0.7) : accent)
                    Text("\(saved.buildingCount) 个建筑 · \(saved.belts.count) 条线 · \(saved.width)×\(saved.height) 格")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
                Text(saved.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// 布局缩略图：按外框等比缩放，建筑画成分类颜色的方块，线画成橙色（传送带）/蓝色（管道）折线
struct LayoutThumbnail: View {
    let layout: SavedLayout

    var body: some View {
        Canvas { context, size in
            let w = CGFloat(max(layout.width, 1)), h = CGFloat(max(layout.height, 1))
            let cell = min(size.width / w, size.height / h) * 0.9
            let ox = (size.width - w * cell) / 2, oy = (size.height - h * cell) / 2
            func center(_ p: GridPoint) -> CGPoint {
                CGPoint(x: ox + (CGFloat(p.col) + 0.5) * cell, y: oy + (CGFloat(p.row) + 0.5) * cell)
            }
            for belt in layout.belts {
                guard let first = belt.segments.first else { continue }
                var path = Path()
                path.move(to: center(first.cell))
                for seg in belt.segments.dropFirst() { path.addLine(to: center(seg.cell)) }
                let color = belt.lineType == .belt ? Color(red: 1.0, green: 0.55, blue: 0.1) : Color(red: 0.3, green: 0.7, blue: 1.0)
                context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: max(1, cell * 0.5))
            }
            for placed in layout.buildings {
                guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
                let s = placed.effectiveSize(definition: def)
                let rect = CGRect(x: ox + CGFloat(placed.origin.col) * cell, y: oy + CGFloat(placed.origin.row) * cell,
                                  width: CGFloat(s.width) * cell, height: CGFloat(s.height) * cell)
                context.fill(Path(rect), with: .color(def.category.color.opacity(0.55)))
                context.stroke(Path(rect), with: .color(def.category.color), lineWidth: 0.5)
            }
        }
    }
}
