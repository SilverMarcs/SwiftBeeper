//
//  String++.swift
//  BeeperMac
//
//  Created by Zabir Raihan on 05/03/2026.
//

import SwiftUI

extension String {
    var markdownAttributed: AttributedString {
        (try? AttributedString(
            markdown: self,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(self)
    }
}
