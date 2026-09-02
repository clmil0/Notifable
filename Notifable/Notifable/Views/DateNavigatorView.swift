import SwiftUI

struct DateNavigatorView: View {
    @Binding var referenceDate: Date
    @Binding var selectedFilter: DashboardFilter
    @Binding var slideDirection: Edge
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue
    
    var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    
    var body: some View {
        if selectedFilter != .rango {
            HStack(spacing: 8) {
                // Left Arrow
                Button {
                    navigateReferenceDate(forward: false)
                } label: {
                    Image(systemName: "chevron.left")
                        .padding(8)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                
                if selectedFilter == .mes {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                mesSubFilters
                            }
                            .onAppear {
                                let monthIndex = Calendar.current.component(.month, from: referenceDate) - 1
                                proxy.scrollTo(monthIndex, anchor: .center)
                            }
                            .onChange(of: referenceDate) { _, newValue in
                                withAnimation {
                                    let monthIndex = Calendar.current.component(.month, from: newValue) - 1
                                    proxy.scrollTo(monthIndex, anchor: .center)
                                }
                            }
                        }
                    }
                } else {
                    ZStack {
                        HStack(spacing: 8) {
                            if selectedFilter == .hoy {
                                hoySubFilters
                            } else if selectedFilter == .semana {
                                semanaSubFilters
                            }
                        }
                        .frame(maxWidth: .infinity)
                        // Animation identifiers and transitions for Carousel effect
                        .id(currentPeriodAnimationId)
                        .transition(.asymmetric(
                            insertion: .move(edge: slideDirection),
                            removal: .move(edge: slideDirection == .trailing ? .leading : .trailing)
                        ))
                    }
                    .clipped()
                    // Add Drag Gesture to subfilters for Hoy and Semana
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture()
                            .onEnded { value in
                                // Minimum swipe distance
                                if abs(value.translation.width) > 30 {
                                    if value.translation.width > 0 {
                                        // Swipe right -> Go to previous period
                                        navigateReferenceDate(forward: false)
                                    } else {
                                        // Swipe left -> Go to next period (if allowed)
                                        if canNavigateForward {
                                            navigateReferenceDate(forward: true)
                                        }
                                    }
                                }
                            }
                    )
                }
                
                // Right Arrow
                Button {
                    navigateReferenceDate(forward: true)
                } label: {
                    Image(systemName: "chevron.right")
                        .padding(8)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .disabled(!canNavigateForward)
                .opacity(canNavigateForward ? 1.0 : 0.3)
            }
            .padding(.horizontal)
        }
    }
    
    private var currentPeriodAnimationId: Double {
        let cal = customCalendar
        if selectedFilter == .hoy {
            return cal.dateInterval(of: .weekOfYear, for: referenceDate)?.start.timeIntervalSince1970 ?? referenceDate.timeIntervalSince1970
        } else if selectedFilter == .semana {
            return cal.dateInterval(of: .month, for: referenceDate)?.start.timeIntervalSince1970 ?? referenceDate.timeIntervalSince1970
        }
        return referenceDate.timeIntervalSince1970
    }
    
    private var canNavigateForward: Bool {
        let calendar = Calendar.current
        let now = Date()
        switch selectedFilter {
        case .hoy:
            return !calendar.isDate(referenceDate, equalTo: now, toGranularity: .weekOfYear)
        case .semana:
            return !calendar.isDate(referenceDate, equalTo: now, toGranularity: .month)
        case .mes:
            return !calendar.isDate(referenceDate, equalTo: now, toGranularity: .year)
        default: return false
        }
    }
    
    private func navigateReferenceDate(forward: Bool) {
        let calendar = Calendar.current
        let value = forward ? 1 : -1
        
        // Update direction before animation
        slideDirection = forward ? .trailing : .leading
        
        withAnimation(.spring) {
            switch selectedFilter {
            case .hoy:
                if let newDate = calendar.date(byAdding: .weekOfYear, value: value, to: referenceDate) {
                    referenceDate = min(newDate, Date())
                }
            case .semana:
                if let newDate = calendar.date(byAdding: .month, value: value, to: referenceDate) {
                    referenceDate = min(newDate, Date())
                }
            case .mes:
                if let newDate = calendar.date(byAdding: .year, value: value, to: referenceDate) {
                    referenceDate = min(newDate, Date())
                }
            default:
                break
            }
        }
    }
    
    private var customCalendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        return cal
    }
    
    @ViewBuilder
    private var hoySubFilters: some View {
        let cal = customCalendar
        let now = Date()
        if let weekInterval = cal.dateInterval(of: .weekOfYear, for: referenceDate) {
            let dayNames = ["L", "M", "X", "J", "V", "S", "D"]
            
            ForEach(0..<7, id: \.self) { i in
                if let dayDate = cal.date(byAdding: .day, value: i, to: weekInterval.start) {
                    let isFuture = cal.startOfDay(for: dayDate) > cal.startOfDay(for: now)
                    let isSelected = cal.isDate(dayDate, inSameDayAs: referenceDate)
                    
                    Button {
                        withAnimation(.spring) {
                            referenceDate = dayDate
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(dayNames[i])
                                .font(.caption2)
                                .fontWeight(.semibold)
                            Text("\(cal.component(.day, from: dayDate))")
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? .white : (colorScheme == .dark ? .white : .black))
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? themeColor.opacity(0.8) : Color.primary.opacity(0.05))
                        )
                    }
                    .disabled(isFuture)
                    .opacity(isFuture ? 0.3 : 1.0)
                }
            }
        }
    }
    
    @ViewBuilder
    private var semanaSubFilters: some View {
        let cal = customCalendar
        let now = Date()
        
        if let monthInterval = cal.dateInterval(of: .month, for: referenceDate) {
            let weeks = weeksInMonth(monthInterval: monthInterval, calendar: cal)
            
            ForEach(weeks, id: \.start) { weekInt in
                let isFuture = cal.startOfDay(for: weekInt.start) > cal.startOfDay(for: now)
                let isSelected = cal.isDate(referenceDate, equalTo: weekInt.start, toGranularity: .weekOfYear)
                
                Button {
                    withAnimation(.spring) {
                        referenceDate = weekInt.start
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text("L \(cal.component(.day, from: weekInt.start))")
                            .font(.caption)
                        Text("D \(cal.component(.day, from: weekInt.end.addingTimeInterval(-1)))")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(isSelected ? .white : (colorScheme == .dark ? .white : .black))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? themeColor.opacity(0.8) : Color.primary.opacity(0.05))
                    )
                }
                .disabled(isFuture)
                .opacity(isFuture ? 0.3 : 1.0)
            }
        }
    }
    
    private func weeksInMonth(monthInterval: DateInterval, calendar: Calendar) -> [DateInterval] {
        var weeks: [DateInterval] = []
        var current = monthInterval.start
        while current < monthInterval.end {
            if let weekInt = calendar.dateInterval(of: .weekOfYear, for: current) {
                if !weeks.contains(where: { $0.start == weekInt.start }) {
                    weeks.append(weekInt)
                }
            }
            if let nextWeek = calendar.date(byAdding: .day, value: 7, to: current) {
                current = nextWeek
            } else {
                break
            }
        }
        return weeks
    }
    
    @ViewBuilder
    private var mesSubFilters: some View {
        let calendar = Calendar.current
        let now = Date()
        if let yearInterval = calendar.dateInterval(of: .year, for: referenceDate) {
            let monthNames = ["Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]
            
            ForEach(0..<12, id: \.self) { i in
                if let monthDate = calendar.date(byAdding: .month, value: i, to: yearInterval.start) {
                    let isFuture = calendar.component(.year, from: monthDate) > calendar.component(.year, from: now) || (calendar.component(.year, from: monthDate) == calendar.component(.year, from: now) && calendar.component(.month, from: monthDate) > calendar.component(.month, from: now))
                    let isSelected = calendar.isDate(monthDate, equalTo: referenceDate, toGranularity: .month)
                    
                    Button {
                        withAnimation(.spring) {
                            referenceDate = monthDate
                        }
                    } label: {
                        Text(monthNames[i])
                            .font(.subheadline)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .foregroundStyle(isSelected ? .white : (colorScheme == .dark ? .white : .black))
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? themeColor.opacity(0.8) : Color.primary.opacity(0.05))
                            )
                    }
                    .id(i)
                    .disabled(isFuture)
                    .opacity(isFuture ? 0.3 : 1.0)
                }
            }
        }
    }
}
