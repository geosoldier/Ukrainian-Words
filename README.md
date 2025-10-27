An iOS app to help beginners learn Ukrainian vocabulary and practice identifying the gender of words (masculine, feminine, neuter).

✨ Features

🎨 Minimalist UI with Ukrainian flag colors
🔊 Text-to-Speech: tap the speaker icon to hear Ukrainian words
✅ **Complete Visual Feedback**: Green checkmarks for correct answers, red X for incorrect answers
🔄 **Second Chance System**: Two attempts for each question before moving on
💝 **Encouragement Cards**: Supportive messages with correct answers (in green bold) after failed attempts
🎵 Enhanced audio feedback with distinct sounds (glass for correct, funk for incorrect)
📳 Haptic feedback for tactile confirmation
↩️ Previous button (review up to 5 past words)
📚 Built-in learning section explaining Ukrainian gender rules
⚙️ Settings screen with shuffle toggle, haptics, and usage instructions
📈 Score tracking per quiz session
🛠️ **Grammatically Accurate**: Proper Ukrainian gender classification (masculine, feminine, neuter only)
📖 Why Gender Matters

In Ukrainian, every noun belongs to one of three genders:

Masculine → usually end in a consonant
Feminine → often end in -а or -я
Neuter → often end in -о or -е
Learning gender is essential because it affects adjectives, verbs, and agreement in sentences.

🚀 Getting Started

Requirements

macOS with Xcode 15+
iPhone running iOS 17+ (tested on iPhone 14 Pro Max)
SwiftUI project template
Build & Run

Clone the repo:

```bash
git clone https://github.com/geosoldier/Ukrainian-Words.git
cd "Ukrainian Words"
open "Ukrainian Words.xcodeproj"
```

Connect your iphone and press the Run button in XCode.

## 📋 Version History

### Version 1.2.0 (October 2024)
- ✅ **NEW: Second Chance System** - Users get two attempts for both meaning and gender questions
- ❌ **NEW: Red X Visual Feedback** - Large animated red X with "Incorrect!" text for wrong answers
- 💝 **NEW: Encouragement Cards** - Supportive splash cards appear after failing both attempts
- 🎯 **NEW: User-Controlled Timing** - "Continue" button lets users dismiss encouragement cards at their own pace
- 💚 **NEW: Green Bold Correct Answers** - Correct answers displayed prominently in green and bold on encouragement cards
- 🔊 **IMPROVED: Enhanced Audio** - Better negative sound (Funk) for incorrect answers vs positive (Glass) for correct
- 🔄 **IMPROVED: Retry UI Feedback** - "Try again" prompts show when it's a second attempt
- 🛠️ **FIXED: Vocabulary Data** - Corrected 15 words incorrectly marked as "plural" gender to proper masculine/feminine/neuter
- 📚 **EDUCATIONAL: Grammar Accuracy** - Ensures only proper Ukrainian genders (masculine, feminine, neuter) are used

### Version 1.1.0 (October 2024)
- ✅ **NEW: Enhanced Visual Feedback** - Large animated green checkmark with "Correct!" text appears on screen for correct answers
- 🎬 **NEW: Spring Animations** - Smooth scale and fade animations for visual feedback
- ⏱️ **NEW: Auto-hide Timer** - Visual feedback automatically disappears after 1.5 seconds
- 🎯 **IMPROVED: Multi-sensory Experience** - Combined audio, haptic, and visual feedback for correct answers
- 🔧 **TECHNICAL: SwiftUI Overlay System** - Non-blocking overlay system for visual feedback

### Version 1.0.0 (App Store Release)
- 🎨 Minimalist UI with Ukrainian flag colors
- 🔊 Text-to-Speech pronunciation for Ukrainian words
- 🎵 Audio feedback (ding/buzz sounds)
- 📳 Haptic feedback support
- ↩️ Previous button with 5-word history
- 📚 Built-in Ukrainian gender learning guide
- ⚙️ Comprehensive settings screen
- 📈 Session score tracking
- 🌍 Category-based word filtering
- 📊 End-of-session summary with missed words
- 🔄 Retry missed words functionality

## 🗺️ Roadmap

### Upcoming Features
🎯 Streaks & daily goals
🔔 Notifications for daily practice  
📱 Apple Watch companion app
🌐 Localization for multiple languages
🎮 Gamification elements (achievements, badges)

### Completed Features ✅
- ✅ End-of-session summary (words missed, accuracy %) - *Implemented in v1.0.0*
- ✅ Light/Dark mode with Ukrainian accent colors - *Implemented in v1.0.0*  
- ✅ Categories (family, food, animals, travel, etc.) - *Implemented in v1.0.0*
- ✅ Enhanced visual feedback - *Implemented in v1.1.0*
- ✅ Second chance retry system - *Implemented in v1.2.0*
- ✅ Red X visual feedback for incorrect answers - *Implemented in v1.2.0*
- ✅ Encouragement cards with user-controlled timing - *Implemented in v1.2.0*
- ✅ Vocabulary data accuracy improvements - *Implemented in v1.2.0*
License

Currently closed-source for personal development and personal use. May switch to MIT or Apache 2.0 in the future.

Authorship

Developed by Eric Adams with AI assistance for SwiftUI conversion. Originally inspired by a Python flashcard script.
