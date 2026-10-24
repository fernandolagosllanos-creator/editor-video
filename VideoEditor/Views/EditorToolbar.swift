import SwiftUI

/// Una herramienta de la barra inferior.
struct ToolItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var isEnabled = true
    var isDestructive = false
    let action: () -> Void

    init(_ title: String, _ symbol: String, isEnabled: Bool = true, isDestructive: Bool = false,
         action: @escaping () -> Void) {
        self.id = title
        self.title = title
        self.symbol = symbol
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.action = action
    }
}

/// Barra inferior de íconos. Muestra las herramientas generales y, cuando hay un clip
/// seleccionado, cambia con una animación a las herramientas del clip.
struct EditorToolbar: View {
    let mainTools: [ToolItem]
    let clipTools: [ToolItem]
    let isClipMode: Bool
    let onExitClipMode: () -> Void

    var body: some View {
        ZStack {
            if isClipMode {
                HStack(spacing: 0) {
                    Button(action: onExitClipMode) {
                        VStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 34, height: 34)
                                .background(Theme.surfaceRaised, in: Circle())
                            Text("Listo").font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 58)
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Theme.stroke).frame(width: 1, height: 40)
                    toolRow(clipTools)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                toolRow(mainTools)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(height: 74)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 24)
        .padding(.horizontal, 10)
        .animation(Theme.spring, value: isClipMode)
    }

    private func toolRow(_ tools: [ToolItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tools) { tool in
                    ToolButton(tool: tool)
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

private struct ToolButton: View {
    let tool: ToolItem

    var body: some View {
        Button(action: tool.action) {
            VStack(spacing: 5) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tool.isDestructive ? AnyShapeStyle(Theme.accent2) : AnyShapeStyle(Color.white))
                    .frame(width: 30, height: 26)
                Text(tool.title)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 62, height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolPressStyle())
        .disabled(!tool.isEnabled)
        .opacity(tool.isEnabled ? 1 : 0.35)
    }
}

/// Al presionar, el ícono se achica un poco y aparece un brillo de color detrás.
private struct ToolPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.gradient)
                    .opacity(configuration.isPressed ? 0.35 : 0)
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
