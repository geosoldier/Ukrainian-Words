import SwiftUI
import UIKit
import AVFoundation
import AudioToolbox
import Foundation

// MARK: - Theme (Ukrainian colors)
struct AppTheme {
    static let flagBlue   = Color(red: 0/255, green: 87/255, blue: 184/255)
    static let flagYellow = Color(red: 255/255, green: 215/255, blue: 0/255)
    
    // Colors that work in both light and dark modes
    static let softBlue = Color(red: 0/255, green: 87/255, blue: 184/255).opacity(0.12)
    static let softYellow = Color(red: 255/255, green: 215/255, blue: 0/255).opacity(0.12)
    
    // Background colors that adapt to system appearance
    static let cardBackground = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    
    // Secondary color for borders and text
    static let secondaryColor = Color.secondary.opacity(0.25)
}

// MARK: - Data Models
struct VocabItem: Identifiable, Equatable {
    let id = UUID()
    let word: String
    let meaning: String
    let gender: String
    let categories: [String]
}

// JSON structures for vocabulary data
struct VocabularyData: Codable {
    let nouns: [VocabItem]
    let verbs: [SimpleItem]
    let adjectives: [SimpleItem]
}

struct SimpleItem: Codable {
    let word: String
    let meaning: String
    let categories: [String]
}

// Make VocabItem conform to Codable for JSON decoding
extension VocabItem: Codable {
    enum CodingKeys: String, CodingKey {
        case word, meaning, gender, categories
        // Note: 'id' is not included, so it will use the default UUID() value
    }
}

enum QuizPhase { case meaning, gender, done }

enum PartOfSpeech: String, CaseIterable, Identifiable {
    case nouns
    case verbs
    case adjectives
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .nouns: return "Nouns"
        case .verbs: return "Verbs"
        case .adjectives: return "Adjectives"
        }
    }
}

enum AudioSetup {
    static func configureForTTS() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback overrides the mute/silent switch
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            print("Audio session error: \(error)")
        }
    }
}

// Per-card UI/score state so going back doesn't double-score
struct CardState: Equatable {
    var selectedMeaning: String? = nil
    var selectedGender: String? = nil
    var meaningWasCorrect: Bool? = nil
    var genderWasCorrect: Bool? = nil
    var phase: QuizPhase = .meaning
    var scoreGrantedMeaning: Bool = false
    var scoreGrantedGender: Bool = false
}

// MARK: - Settings
struct QuizSettings {
    @AppStorage("hapticsEnabled") var hapticsEnabled: Bool = true
    @AppStorage("shuffleEnabled") var shuffleEnabled: Bool = true

    // Session
    @AppStorage("sessionLength") var sessionLength: Int = 20  // 10/20/50 or 0=All

    // TTS
    @AppStorage("speechEnabled") var speechEnabled: Bool = true
    @AppStorage("speechRate") var speechRate: Double = 0.5

    // Sounds
    @AppStorage("answerSoundsEnabled") var answerSoundsEnabled: Bool = true

    // UI
    @AppStorage("showInstructions") var showInstructions: Bool = true
    @AppStorage("hasSeenWelcome") var hasSeenWelcome: Bool = false
    @AppStorage("darkModeEnabled") var darkModeEnabled: Bool = false

    // Word type
    @AppStorage("partOfSpeech") var partOfSpeechRaw: String = PartOfSpeech.nouns.rawValue
    var partOfSpeech: PartOfSpeech {
        get { PartOfSpeech(rawValue: partOfSpeechRaw) ?? .nouns }
        set { partOfSpeechRaw = newValue.rawValue }
    }
}

// MARK: - Haptics & Sounds
struct Haptics {
    static func success(enabled: Bool) { guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func error(enabled: Bool) { guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

struct SoundFX {
    static let correctID: SystemSoundID = 1110
    static let wrongID: SystemSoundID = 1107
    static func playCorrect(enabled: Bool) { guard enabled else { return }; AudioServicesPlaySystemSound(correctID) }
    static func playWrong(enabled: Bool)   { guard enabled else { return }; AudioServicesPlaySystemSound(wrongID) }
}

// MARK: - Speech (Text-to-Speech)
final class SpeechManager {
    static let shared = SpeechManager()
    private let synth = AVSpeechSynthesizer()
    func speak(_ text: String, enabled: Bool, rate sliderRate: Double) {
        guard enabled else { return }
        let avRate = AVSpeechUtteranceDefaultSpeechRate + Float((sliderRate - 0.5)) * 0.4
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "uk-UA") ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        u.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, avRate))
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }
}

// MARK: - ViewModel
final class QuizViewModel: ObservableObject {
    // Settings
    @Published var settings = QuizSettings()

    // Data
    @Published private(set) var fullDeck: [VocabItem] = []
    @Published private(set) var workingDeck: [VocabItem] = []

    // Quiz State
    @Published var currentIndex = 0
    @Published var phase: QuizPhase = .meaning
    @Published var score: Double = 0
    @Published var totalAsked: Int = 0
    @Published var meaningOptions: [String] = []
    @Published var selectedMeaning: String? = nil
    @Published var selectedGender: String? = nil
    @Published var showSummary: Bool = false
    @Published var missedItems: [VocabItem] = []
    @Published var activeCategories: Set<String> = []

    // Per-card saved state
    private var stateByID: [UUID: CardState] = [:]

    // Back history (≤ 5)
    private var backHistory: [Int] = []
    private let backLimit = 5

    // Categories order
    let allCategories: [String] = [
        "Objects", "Food", "Family", "People", "Professions", "Time",
        "Weather", "Nature", "Places", "Transport", "School", "Abstract", "Home"
    ]

    init() {
        print("🔄 QuizViewModel.init() starting")
        loadWords()
        print("✅ loadWords() completed")
        loadPersistedCategories()
        print("✅ loadPersistedCategories() completed")
        rebuildWorkingDeck()
        print("✅ rebuildWorkingDeck() completed")
        ensureStateAndStart()
        print("✅ ensureStateAndStart() completed")
    }

    func loadWords() {
        print("🔄 Starting loadWords() function")
        print("🔍 Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
        print("🔍 Bundle path: \(Bundle.main.bundlePath)")
        
        // Load vocabulary from JSON file
        guard let url = Bundle.main.url(forResource: "ukrainian_vocabulary", withExtension: "json") else {
            print("❌ Error: Could not find ukrainian_vocabulary.json in bundle")
            print("🔍 Available JSON files: \(Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil))")
            fullDeck = []
            return
        }
        
        print("✅ Found JSON file at: \(url)")
        
        do {
            let data = try Data(contentsOf: url)
            print("✅ Loaded data, size: \(data.count) bytes")
            
            let decoder = JSONDecoder()
            let vocabularyData = try decoder.decode(VocabularyData.self, from: data)
            print("✅ Successfully decoded JSON")
            print("📚 Nouns count: \(vocabularyData.nouns.count)")
            print("📚 Verbs count: \(vocabularyData.verbs.count)")
            print("📚 Adjectives count: \(vocabularyData.adjectives.count)")
            
            // Populate fullDeck based on selected part of speech
            switch settings.partOfSpeech {
            case .nouns:
                fullDeck = vocabularyData.nouns
            case .verbs:
                // Convert SimpleItem to VocabItem for verbs (no gender)
                fullDeck = vocabularyData.verbs.map { verb in
                    VocabItem(word: verb.word, meaning: verb.meaning, gender: "N/A", categories: verb.categories)
                }
            case .adjectives:
                // Convert SimpleItem to VocabItem for adjectives (no gender)
                fullDeck = vocabularyData.adjectives.map { adj in
                    VocabItem(word: adj.word, meaning: adj.meaning, gender: "N/A", categories: adj.categories)
                }
            }
            
            print("✅ Loaded \(fullDeck.count) words into fullDeck for \(settings.partOfSpeech.displayName)")
            
            // Rebuild working deck after loading
            rebuildWorkingDeck()
            
        } catch {
            print("❌ Error decoding JSON: \(error)")
            fullDeck = []
        }
    }

    func rebuildWorkingDeck() {
        var deck = fullDeck
        let selected = activeCategories
        if !selected.isEmpty {
            deck = deck.filter { !$0.categories.isEmpty && !selected.isDisjoint(with: Set($0.categories)) }
        }
        deck = settings.shuffleEnabled ? deck.shuffled() : deck

        // NEW: enforce session length
        let limit = settings.sessionLength  // 10 / 20 / 50 / 0 (All)
        if limit > 0, deck.count > limit {
            workingDeck = Array(deck.prefix(limit))
        } else {
            workingDeck = deck
        }

        currentIndex = 0
        backHistory.removeAll()
        stateByID.removeAll()
        score = 0
        totalAsked = 0
        showSummary = false
        missedItems = []
        ensureStateAndStart()
    }

    // Public so SettingsView can call it
    func ensureStateAndStart() {
        if let id = current?.id, stateByID[id] == nil { stateByID[id] = CardState() }
        restoreStateToUI()
        makeMeaningOptions()
    }

    var current: VocabItem? {
        guard workingDeck.indices.contains(currentIndex) else { return nil }
        return workingDeck[currentIndex]
    }

    var progress: Double {
        guard !workingDeck.isEmpty else { return 0 }
        let base = Double(currentIndex) / Double(workingDeck.count)
        switch phase {
        case .meaning: return base
        case .gender:  return min(1.0, base + (1.0 / Double(workingDeck.count)) * 0.5)
        case .done:    return min(1.0, base + (1.0 / Double(workingDeck.count)))
        }
    }

    private func makeMeaningOptions() {
        meaningOptions = []
        guard let cur = current else { return }
        var options = Set([cur.meaning])
        var pool = workingDeck.shuffled()
        while options.count < 4, let next = pool.popLast() {
            if next.meaning != cur.meaning { options.insert(next.meaning) }
        }
        meaningOptions = Array(options).shuffled()
    }

    private func restoreStateToUI() {
        guard let id = current?.id else { return }
        let st = stateByID[id] ?? CardState()
        selectedMeaning = st.selectedMeaning
        selectedGender = st.selectedGender
        phase = st.phase
    }

    private func updateState(_ change: (inout CardState) -> Void) {
        guard let id = current?.id else { return }
        var st = stateByID[id] ?? CardState()
        change(&st)
        stateByID[id] = st
    }

    func submitMeaning(_ choice: String) {
        guard phase == .meaning, let cur = current else { return }
        updateState { st in
            st.selectedMeaning = choice
            let isCorrect = (choice == cur.meaning)
            st.meaningWasCorrect = isCorrect
            if isCorrect && !st.scoreGrantedMeaning {
                score += 0.5
                st.scoreGrantedMeaning = true
                Haptics.success(enabled: settings.hapticsEnabled)
                SoundFX.playCorrect(enabled: settings.answerSoundsEnabled)
            } else if !isCorrect {
                Haptics.error(enabled: settings.hapticsEnabled)
                SoundFX.playWrong(enabled: settings.answerSoundsEnabled)
            }
            // Only show gender step for nouns
            if settings.partOfSpeech == .nouns {
                st.phase = .gender
            } else {
                st.phase = .done
                if st.meaningWasCorrect == false, let cur = current {
                    if !missedItems.contains(where: { $0.id == cur.id }) { missedItems.append(cur) }
                }
                totalAsked += 1
            }
        }
        restoreStateToUI()
    }

    func submitGender(_ choice: String) {
        guard phase == .gender, let cur = current else { return }
        updateState { st in
            st.selectedGender = choice
            let isCorrect = (choice == cur.gender)
            st.genderWasCorrect = isCorrect
            if isCorrect && !st.scoreGrantedGender {
                score += 0.5
                st.scoreGrantedGender = true
                Haptics.success(enabled: settings.hapticsEnabled)
                SoundFX.playCorrect(enabled: settings.answerSoundsEnabled)
            } else if !isCorrect {
                Haptics.error(enabled: settings.hapticsEnabled)
                SoundFX.playWrong(enabled: settings.answerSoundsEnabled)
            }
            if st.phase != .done { totalAsked += 1 }
            st.phase = .done
            // Record as missed if either meaning or gender was wrong
            let wasMeaningCorrect = st.meaningWasCorrect ?? false
            let wasGenderCorrect  = st.genderWasCorrect ?? false
            if !(wasMeaningCorrect && wasGenderCorrect), let cur = current {
                // avoid duplicates if somehow revisiting
                if !missedItems.contains(where: { $0.id == cur.id }) {
                    missedItems.append(cur)
                }
            }
        }
        restoreStateToUI()
    }

    func next() {
        if backHistory.last != currentIndex {
            backHistory.append(currentIndex)
            if backHistory.count > backLimit { backHistory.removeFirst(backHistory.count - backLimit) }
        }
        if currentIndex + 1 < workingDeck.count {
            currentIndex += 1
        } else {
            // End of session -> show summary instead of auto-rebuilding
            showSummary = true
        }
        if let id = current?.id, stateByID[id] == nil { stateByID[id] = CardState() }
        restoreStateToUI()
        makeMeaningOptions()
    }

    func previous() {
        guard let prevIndex = backHistory.popLast() else { return }
        currentIndex = prevIndex
        if let id = current?.id, stateByID[id] == nil { stateByID[id] = CardState() }
        restoreStateToUI()
        makeMeaningOptions()
    }

    var canGoBack: Bool { !backHistory.isEmpty }

    var scoreText: String { String(format: "Score: %.1f / %d", score, totalAsked) }
    var counterText: String { workingDeck.isEmpty ? "" : "Word \(currentIndex + 1) of \(workingDeck.count)" }

    func resetScore() {
        score = 0; totalAsked = 0
        for (id, var st) in stateByID {
            st.scoreGrantedMeaning = false
            st.scoreGrantedGender = false
            stateByID[id] = st
        }
    }

    // TTS proxy
    func speakCurrentWord() {
        guard let w = current?.word else { return }
        SpeechManager.shared.speak(w, enabled: settings.speechEnabled, rate: settings.speechRate)
    }
    
    // Save and load categories from UserDefaults
    // MARK: - Category persistence
    private let categoriesKey = "activeCategories" // UserDefaults key

    func persistCategories() {
        UserDefaults.standard.set(Array(activeCategories), forKey: categoriesKey)
    }

    func loadPersistedCategories() {
        if let saved = UserDefaults.standard.stringArray(forKey: categoriesKey) {
            activeCategories = Set(saved)
        }
    }

    func toggleCategory(_ cat: String) {
        if activeCategories.contains(cat) {
            activeCategories.remove(cat)
        } else {
            activeCategories.insert(cat)
        }
        persistCategories()
        rebuildWorkingDeck()
        ensureStateAndStart()
    }
    
    // =========================
    // ✅ ADDITIONS FOR SUMMARY:
    // =========================
    
    /// Rebuild the deck from only the missed items and start a fresh session
    func retryMissedOnly() {
        guard !missedItems.isEmpty else {
            showSummary = false
            return
        }
        workingDeck = missedItems.shuffled()
        currentIndex = 0
        backHistory.removeAll()
        stateByID.removeAll()
        score = 0
        totalAsked = 0
        missedItems.removeAll()
        showSummary = false
        ensureStateAndStart()
    }

    /// Start a new full session using current filters and session length
    func startNewSessionFromFilters() {
        rebuildWorkingDeck()
        showSummary = false
        ensureStateAndStart()
    }
}

// MARK: - Welcome / Gender Guide
struct WelcomeView: View {
    var dismissAction: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Flag header
                    HStack(spacing: 0) { AppTheme.flagBlue; AppTheme.flagYellow }
                        .frame(height: 8).mask(RoundedRectangle(cornerRadius: 6))
                        .padding(.bottom, 2)

                    Text("Welcome! Ласкаво просимо!")
                        .font(.largeTitle).fontWeight(.bold)

                    Text(LocalizedStringKey("A quick guide to **Ukrainian language learning** before you practice."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Group {
                        Text(LocalizedStringKey("**Masculine (чол. рід)**"))
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey("• Usually ends in a **consonant** or **-й**: _стіл_, _хліб_, _телефон_."))
                            Text(LocalizedStringKey("• Some nouns ending in **-ь** are masculine: _кінь_ \"horse\", _день_ \"day\"."))
                            Text(LocalizedStringKey("• Nouns for **male people** are masculine: _хлопець_ \"boy\", _чоловік_ \"man\"."))
                            Text(LocalizedStringKey("• ⚠️ A few masculine nouns end in **-о**: _тато_ \"dad\", _дядько_ \"uncle\"."))
                        }
                    }

                    Group {
                        Text(LocalizedStringKey("**Feminine (жін. рід)**"))
                            .font(.headline).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey("• Commonly ends in **-а / -я**: _книга_, _вода_, _історія_."))
                            Text(LocalizedStringKey("• Many nouns ending in **-ь** are feminine: _ніч_ \"night\", _любов_ \"love\", _сіль_ \"salt\"."))
                            Text(LocalizedStringKey("• Abstract **-ість** words are feminine: _швидкість_ \"speed\", _молодість_ \"youth\"."))
                            Text(LocalizedStringKey("• Female people/roles are feminine: _жінка_, _вчителька_."))
                        }
                    }

                    Group {
                        Text(LocalizedStringKey("**Neuter (сер. рід)**"))
                            .font(.headline).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey("• Often ends in **-о / -е**: _вікно_, _море_, _місто_."))
                            Text(LocalizedStringKey("• Some end in **-я** (special pattern): _ім'я_ \"name\", _плем'я_ \"tribe\"."))
                            Text(LocalizedStringKey("• Many **-ко** diminutives are neuter: _яблуко_ \"apple\"."))
                        }
                    }

                    Group {
                        Text(LocalizedStringKey("**Tips**"))
                            .font(.headline).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey("• Endings are great **rules of thumb**, but there are **exceptions**."))
                            Text(LocalizedStringKey("• When in doubt, check a dictionary; your ear will improve with exposure."))
                            Text(LocalizedStringKey("• This app quizzes **meaning first**, then **gender** to reinforce both."))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ready to practice?")
                            .font(.headline).padding(.top, 10)
                        Text("You can change settings (shuffle, sounds, pronunciation, categories) anytime with the gear icon.")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Language Guide")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismissAction()
                    } label: {
                        Text("Start practicing")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

// MARK: - Settings UI
struct SettingsView: View {
    @ObservedObject var vm: QuizViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showWelcome = false

    var body: some View {
        Form {
            // Intro strip
            Section {
                HStack(spacing: 0) { AppTheme.flagBlue; AppTheme.flagYellow }
                    .frame(height: 6)
                    .mask(RoundedRectangle(cornerRadius: 6))
                    .padding(.vertical, 6)
                Text("Customize your practice and learn how the app works.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Instructions
            Section(header: Text("Instructions")) {
                Toggle("Show quick instructions", isOn: $vm.settings.showInstructions)
                Button {
                    showWelcome = true
                } label: {
                    Label("Open Language Guide", systemImage: "book.fill")
                }
            }

            // Appearance
            Section(header: Text("Appearance")) {
                Toggle("Dark Mode", isOn: $vm.settings.darkModeEnabled)
                    .onChange(of: vm.settings.darkModeEnabled) { oldValue, newValue in
                        // Apply dark mode setting
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                            windowScene.windows.forEach { window in
                                window.overrideUserInterfaceStyle = newValue ? .dark : .light
                            }
                        }
                    }
            }

            // Feedback (haptics/sounds/tts)
            Section(header: Text("Feedback")) {
                Toggle("Haptics (ding/buzz feel)", isOn: $vm.settings.hapticsEnabled)
                Toggle("Answer sounds", isOn: $vm.settings.answerSoundsEnabled)
                Toggle("Pronounce word (Ukrainian)", isOn: $vm.settings.speechEnabled)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Speech rate")
                        Spacer()
                        Text(String(format: "%.2f", vm.settings.speechRate))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $vm.settings.speechRate, in: 0.2...0.9)
                }
            }

            // Session length
            Section(header: Text("Session Length")) {
                Picker("Number of words", selection: $vm.settings.sessionLength) {
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                    Text("All").tag(0)   // 0 means no limit
                }
                .pickerStyle(.segmented)

                Text(vm.settings.sessionLength == 0
                     ? "Practice with all available words."
                     : "Practice with \(vm.settings.sessionLength) words per session.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Button("Apply to current deck") {
                    vm.rebuildWorkingDeck()
                    vm.ensureStateAndStart()
                }
            }

            // Deck behavior
            Section(header: Text("Deck Behavior")) {
                Toggle("Shuffle deck", isOn: $vm.settings.shuffleEnabled)
                    .onChange(of: vm.settings.shuffleEnabled) { oldValue, newValue in
                        vm.rebuildWorkingDeck()
                        vm.ensureStateAndStart()
                    }
                Picker("Word type", selection: $vm.settings.partOfSpeechRaw) {
                    Text(PartOfSpeech.nouns.displayName).tag(PartOfSpeech.nouns.rawValue)
                    Text(PartOfSpeech.verbs.displayName).tag(PartOfSpeech.verbs.rawValue)
                    Text(PartOfSpeech.adjectives.displayName).tag(PartOfSpeech.adjectives.rawValue)
                }
                .onChange(of: vm.settings.partOfSpeechRaw) { oldValue, newValue in
                    vm.loadWords()
                    vm.rebuildWorkingDeck()
                    vm.ensureStateAndStart()
                }
            }

            // Active filters (ALWAYS render the Section; gate the content)
            Section(header: Text("Active Filters")) {
                if vm.activeCategories.isEmpty {
                    Text(vm.activeCategories.sorted().joined(separator: ", "))
                        .foregroundColor(.secondary)
                } else {
                    Text(vm.activeCategories.sorted().joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Categories grid
            Section(header: Text("Categories")) {
                CategoryGrid(vm: vm)
            }
            
            // Actions
            Section {
                HStack {
                    Button("Close") { dismiss() }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.softYellow)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.flagYellow, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    Button("Apply") {
                        vm.rebuildWorkingDeck()
                        vm.ensureStateAndStart()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppTheme.softBlue)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.flagBlue, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeView { showWelcome = false }
                .presentationDetents([.large])
        }
    }
}

// MARK: - Session Summary UI
struct SessionSummaryView: View {
    @ObservedObject var vm: QuizViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Headline numbers
                let total = vm.totalAsked
                let missed = vm.missedItems.count
                let correct = max(0, total - missed)
                let pct = total > 0 ? Int(round(Double(correct) * 100.0 / Double(total))) : 0

                // Flag stripe
                HStack(spacing: 0) { AppTheme.flagBlue; AppTheme.flagYellow }
                    .frame(height: 8)
                    .mask(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 6)

                Text("Session Summary")
                    .font(.largeTitle).fontWeight(.bold)

                HStack(spacing: 20) {
                    summaryStat(title: "Accuracy", value: "\(pct)%")
                    summaryStat(title: "Correct",  value: "\(correct)")
                    summaryStat(title: "Total",    value: "\(total)")
                }
                .padding(.vertical, 4)

                if missed > 0 {
                    // Missed list
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Missed Words").font(.headline)
                        List(vm.missedItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.word).font(.headline)
                                Text("\(item.meaning) • \(item.gender.capitalized)")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                } else {
                    VStack(spacing: 10) {
                        Text("Perfect! 🎉").font(.title2)
                        Text("You didn't miss any words this time.")
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }

                Spacer()

                // Actions
                VStack(spacing: 10) {
                    if !vm.missedItems.isEmpty {
                        Button {
                            vm.retryMissedOnly()
                            dismiss()
                        } label: {
                            Text("Retry missed only")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.softBlue)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.flagBlue, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Button {
                        vm.startNewSessionFromFilters()
                        dismiss()
                    } label: {
                        Text("Start new session")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.softYellow)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.flagYellow, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
            .navigationTitle("Summary")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func summaryStat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 28, weight: .bold))
            Text(title).font(.footnote).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(AppTheme.softBlue)
        )
    }
}

struct CategoryGrid: View {
    @ObservedObject var vm: QuizViewModel

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(vm.allCategories, id: \.self) { cat in
                // Binding that reflects membership in the Set
                let isSelected = Binding<Bool>(
                    get: { vm.activeCategories.contains(cat) },
                    set: { newValue in
                        if newValue { vm.activeCategories.insert(cat) }
                        else { vm.activeCategories.remove(cat) }
                        vm.persistCategories()
                        vm.rebuildWorkingDeck()
                        vm.ensureStateAndStart()
                        print("Active categories now:", vm.activeCategories.sorted()) // debug
                    }
                )

                CategoryChip(title: cat, isSelected: isSelected)
            }
        }
        .padding(.vertical, 4)
    }
}

struct CategoryChip: View {
    let title: String
    @Binding var isSelected: Bool

    var body: some View {
        Button {
            isSelected.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppTheme.softBlue : AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppTheme.flagBlue : AppTheme.secondaryColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main Quiz UI
struct ContentView: View {
    @ObservedObject var viewModel: QuizViewModel
    let selectedPartOfSpeech: PartOfSpeech
    let onBackToSplash: () -> Void
    @State private var showingSettings = false
    @State private var showingChangeTopicConfirmation = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false

    var body: some View {
        VStack(spacing: 14) {
            // Flag stripe header
            HStack(spacing: 0) { AppTheme.flagBlue; AppTheme.flagYellow }
                .frame(height: 6)
                .mask(RoundedRectangle(cornerRadius: 6))
                .padding(.top, 6)

            // Header row
            HStack {
                Button {
                    viewModel.previous()
                } label: {
                    Image(systemName: "chevron.left")
                        .imageScale(.large)
                        .padding(8)
                }
                .disabled(!viewModel.canGoBack)
                .opacity(viewModel.canGoBack ? 1 : 0.35)
                .accessibilityLabel("Previous word")

                Spacer()
                Text(viewModel.scoreText).font(.headline)
                Spacer()

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                        .padding(8)
                }
                .accessibilityLabel("Settings")
            }
            
            // Topic indicator and change button
            HStack {
                Text("Learning: \(selectedPartOfSpeech.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Change Topic") {
                    showingChangeTopicConfirmation = true
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundColor(.orange)
                .confirmationDialog(
                    "Change Learning Topic?",
                    isPresented: $showingChangeTopicConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Change Topic", role: .destructive) {
                        onBackToSplash()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will reset your current progress and return to the topic selection screen.")
                }
            }

            // Counter & progress
            HStack {
                Text(viewModel.counterText).font(.subheadline).foregroundColor(.secondary)
                Spacer()
            }

            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)
                .tint(AppTheme.flagBlue)

            if let item = viewModel.current {
                // Word + speaker
                HStack(spacing: 8) {
                    Text(item.word)
                        .font(.system(size: 44, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Button { viewModel.speakCurrentWord() } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .imageScale(.large)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.softBlue))
                    }
                    .accessibilityLabel("Pronounce word")
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)

                // Step 1: Meaning
                if viewModel.phase == .meaning {
                    Text("Select the meaning").font(.subheadline).foregroundColor(.secondary)
                    ForEach(viewModel.meaningOptions, id: \.self) { option in
                        Button { viewModel.submitMeaning(option) } label: {
                            Text(option)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(option == viewModel.selectedMeaning
                                              ? (option == item.meaning ? Color.green.opacity(0.2) : Color.red.opacity(0.18))
                                              : AppTheme.cardBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(option == viewModel.selectedMeaning
                                                ? (option == item.meaning ? Color.green : Color.red)
                                                : AppTheme.secondaryColor, lineWidth: 1)
                                )
                        }
                        .disabled(viewModel.selectedMeaning != nil)
                    }
                }

                // Step 2: Gender
                if viewModel.phase == .gender {
                    if viewModel.settings.partOfSpeech == .nouns {
                        Text("Select the gender").font(.subheadline).foregroundColor(.secondary)
                    }
                    HStack(spacing: 12) {
                        ForEach(["masculine", "feminine", "neuter"], id: \.self) { g in
                            Button { viewModel.submitGender(g) } label: {
                                Text(g.capitalized)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(g == viewModel.selectedGender
                                                  ? (g == item.gender ? Color.green.opacity(0.2) : Color.red.opacity(0.18))
                                                  : AppTheme.cardBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(g == viewModel.selectedGender
                                                    ? (g == item.gender ? Color.green : Color.red)
                                                    : AppTheme.secondaryColor, lineWidth: 1)
                                    )
                            }
                            .disabled(viewModel.selectedGender != nil)
                        }
                    }
                    .opacity(viewModel.settings.partOfSpeech == .nouns ? 1 : 0)
                    .frame(height: viewModel.settings.partOfSpeech == .nouns ? nil : 0)
                }

                // Step 3: Done
                if viewModel.phase == .done {
                    VStack(spacing: 6) {
                        Text("Correct meaning: \(item.meaning)")
                        if viewModel.settings.partOfSpeech == .nouns {
                            Text("Correct gender: \(item.gender.capitalized)")
                        }
                    }
                    Button {
                        viewModel.next()
                    } label: {
                        Text("Next word")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(AppTheme.softBlue)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.flagBlue, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 6)
                }
            } else {
                Text("No words loaded.").foregroundColor(.secondary)
            }

            Spacer()

            // Footer: reset
            Button("Reset score") { viewModel.resetScore() }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.softYellow)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.flagYellow, lineWidth: 1))
                )
        }
        .padding()
        .onAppear {
            if !hasSeenWelcome { showWelcome = true }
            // Set the selected part of speech in the view model
            viewModel.settings.partOfSpeech = selectedPartOfSpeech
            // Always reload words when part of speech changes to ensure correct data
            viewModel.loadWords()
            viewModel.rebuildWorkingDeck()
        }
        .sheet(isPresented: $showWelcome, onDismiss: {
            hasSeenWelcome = true
        }) {
            WelcomeView {
                hasSeenWelcome = true
                showWelcome = false
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(vm: viewModel)
                .presentationDetents([.medium, .large])
        }
            
        .sheet(isPresented: $viewModel.showSummary) {
            SessionSummaryView(vm: viewModel)
                .presentationDetents([.large])
        }
    }
}

// MARK: - Splash Screen
struct SplashScreenView: View {
    @Binding var selectedPartOfSpeech: PartOfSpeech?
    
    var body: some View {
        VStack(spacing: 30) {
            // Flag header
            HStack(spacing: 0) { AppTheme.flagBlue; AppTheme.flagYellow }
                .frame(height: 12)
                .mask(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 20)
            
            // App title
            VStack(spacing: 8) {
                Text("Ukrainian")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(AppTheme.flagBlue)
                
                Text("Language Learning")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            
            // Choose what to learn
            VStack(spacing: 16) {
                Text("What would you like to learn?")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(spacing: 12) {
                    // Nouns button
                    Button {
                        selectedPartOfSpeech = .nouns
                    } label: {
                        HStack {
                            Image(systemName: "book.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nouns")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("Learn objects, people, places")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(AppTheme.softBlue)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.flagBlue, lineWidth: 2))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    
                    // Verbs button
                    Button {
                        selectedPartOfSpeech = .verbs
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Verbs")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("Learn actions and activities")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(AppTheme.softYellow)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.flagYellow, lineWidth: 2))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    
                    // Adjectives button
                    Button {
                        selectedPartOfSpeech = .adjectives
                    } label: {
                        HStack {
                            Image(systemName: "paintbrush.fill")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Adjectives")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("Learn descriptions and qualities")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.purple.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple, lineWidth: 2))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
            }
            
            Spacer()
            
            // Footer info
            VStack(spacing: 8) {
                Text("Choose your learning path")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("You can change this later in settings")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 30)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - App Entry
@main
struct Ukrainian_WordsApp: App {
    @State private var selectedPartOfSpeech: PartOfSpeech?
    @StateObject private var quizViewModel = QuizViewModel()
    
    init() {
        AudioSetup.configureForTTS()
        
        // Apply saved dark mode setting on launch
        let darkModeEnabled = UserDefaults.standard.bool(forKey: "darkModeEnabled")
        if darkModeEnabled {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.windows.forEach { window in
                    window.overrideUserInterfaceStyle = .dark
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let selectedPartOfSpeech = selectedPartOfSpeech {
                ContentView(
                    viewModel: quizViewModel,
                    selectedPartOfSpeech: selectedPartOfSpeech,
                    onBackToSplash: { self.selectedPartOfSpeech = nil }
                )
            } else {
                SplashScreenView(selectedPartOfSpeech: $selectedPartOfSpeech)
            }
        }
    }
}
