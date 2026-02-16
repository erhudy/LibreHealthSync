import SwiftUI

struct FAQView: View {
    var body: some View {
        List {
            Section {
                FAQItem(
                    question: "What is this app for?",
                    answer: "This app is to fill in a couple of feature gaps in Abbott's official app, specifically that I want to sync my blood glucose data into HealthKit, and I want a Live Activity that shows my current blood glucose reading. Both of these features were inspired by the [GlucoseDirect](https://github.com/creepymonster/GlucoseDirect) app. This app's purpose is much more focused than GlucoseDirect. If Abbott added these features to its own app, I would happily delete this one."
                )
                FAQItem(
                    question: "How much data can this app sync from LibreLinkUp?",
                    answer: "The LibreLinkUp API presents 12-16 hours of data at any one time. The app will attempt to sync as much data as the API provides it."
                )
                FAQItem(
                    question: "Why does the Live Activity disappear eventually?",
                    answer: "iOS always removes Live Activities after 8 hours. This is a limitation imposed by iOS. Just reopen the app and background it again."
                )
                FAQItem(
                    question: "Why doesn't the Live Activity update regularly?",
                    answer: "iOS updates the value on the Live Activity when it feels like it, basically. In my experience, it usually updates every 10-15 minutes."
                )
                FAQItem(
                    question: "Why is this not on the App Store?",
                    answer: "For liability reasons and because it would likely be rejected, because it declares that it needs the Audio playback Background Capability, in order to make iOS update from LibreLinkUp on an exacting schedule."
                )
            }
        }
        .navigationTitle("FAQ")
    }
}

private struct FAQItem: View {
    let question: String
    let answer: LocalizedStringKey

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        } label: {
            Text(question)
                .font(.body)
                .fontWeight(.medium)
        }
    }
}
