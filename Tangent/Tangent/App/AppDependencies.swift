struct AppDependencies {
    let noteStore: any NoteStore
    let audioRecorder: any AudioRecorder
    let transcriber: any Transcriber
    let languageModel: any DiaryLanguageModel
    let modelCatalog: any ModelCatalog
    let reminderScheduler: any ReminderScheduler
}
