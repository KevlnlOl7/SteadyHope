import SwiftUI

/// 列表
struct DataRow: View {
    var icon: String? = nil
    var title: String
    var subtitle: String? = nil
    var showEdit: Bool = true
    var text: String = "修改"
    var showDivider: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .font(.system(size: 20))
                        .frame(width: 28, alignment: .center)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                }
                Spacer(minLength: 10)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                Spacer()
                
                if showEdit {
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.4))
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
