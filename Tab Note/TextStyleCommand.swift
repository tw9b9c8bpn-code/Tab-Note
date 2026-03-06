//
//  TextStyleCommand.swift
//  Tab Note
//

import Foundation

enum TextStyleCommand: String, CaseIterable {
    case title
    case heading
    case subheading
    case body
    case bulletedList
    case dashedList
    case numberedList

    var menuTitle: String {
        switch self {
        case .title: return "Title"
        case .heading: return "Heading"
        case .subheading: return "Subheading"
        case .body: return "Body"
        case .bulletedList: return "• Bulleted List"
        case .dashedList: return "— Dashed List"
        case .numberedList: return "1. Numbered List"
        }
    }
}

extension Notification.Name {
    static let toggleSearchBar = Notification.Name("toggleSearchBar")
    static let toggleAIPanel = Notification.Name("toggleAIPanel")
    static let toggleTabAreaVisibility = Notification.Name("toggleTabAreaVisibility")
    static let applyTextStyle = Notification.Name("applyTextStyle")
    static let answerQuestionAtCursor = Notification.Name("answerQuestionAtCursor")
    static let inlineAIStatusDidChange = Notification.Name("inlineAIStatusDidChange")
}
