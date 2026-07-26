import SwiftUI

/// 顏色選擇圓圈按鈕元件，可用於選取貼紙底色或主題顏色
struct ColorPickerButton: View {
    /// 此按鈕代表的顏色
    let color: Color
    
    /// 目前全域/頁面所選擇的色彩狀態綁定
    @Binding var selectedColor: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 36, height: 36)
            .overlay(
                Circle().stroke(
                    Color.gray.opacity(0.5),
                    lineWidth: selectedColor == color ? 3 : 0
                )
            )
            .onTapGesture {
                selectedColor = color
            }
    }
}
