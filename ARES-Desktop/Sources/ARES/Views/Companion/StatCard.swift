import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10))
                    .fontWeight(.bold)
                    .tracking(1.5)
                    .foregroundStyle(ARESColors.textSecondary)
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(ARESColors.textPrimary)
            }

            Spacer()
        }
        .padding(12)
        .background(ARESColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
