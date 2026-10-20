import Testing

@testable import RUsage

struct ModelDisplayNameTests {
    @Test(arguments: [
        ("claude-opus-5-5", "Opus 5.5"),
        ("claude-sonnet-4-5-20250929", "Sonnet 4.5"),
        ("claude-4.5-sonnet", "Sonnet 4.5"),
        ("claude-haiku-5-5", "Haiku 5.5"),
        ("gpt-5.6-sol", "GPT-5.6 Sol"),
        ("gpt-6-astra", "GPT-6 Astra"),
        ("gpt-5.5", "GPT-5.5"),
        ("composer-2", "Composer 2"),
        ("unknown", "Other"),
    ])
    func readableNames(id: String, name: String) {
        #expect(ModelDisplayName.make(id) == name)
    }
}
