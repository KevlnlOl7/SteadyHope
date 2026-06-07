import SwiftUI

/// 列表
struct DataRow: View {
    var icon: String? = nil
    var title: String
    var subtitle: String? = nil
    var showEdit: Bool = true
    var text: String = "修改"
    var showDivider: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .foregroundColor(.blue)
                        .font(.system(size: 20))
                        .frame(width: 28, alignment: .center)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(.black)
                }
                Spacer(minLength: 10)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                if showEdit {
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.3))
                }
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 20)
            
            if showDivider {
                Divider()
                    .padding(.leading, 20)
                    .padding(.trailing, 10)
            }
        }
    }
}
