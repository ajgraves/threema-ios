//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2024 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import XCTest

final class IDNASafetyHelperTests: XCTestCase {
    
    private var latin = "a"
    private var cyrillic = "а"
    private var greek = "ͱ"
    private var han = "繁"
    private var bopomofo = "ㄅ"
    private var hiragana = "ぁ"
    private var katakana = "ァ"
    private var hangul = "ᄀ"
    private var aInherited = "á"
    private var aLatin = "á"
    
    private let scripts: [Unicode.ThreemaScript] = [
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .bopomofo,
        .common,
        .inherited,
        .greek,
        .common,
        .greek,
        .common,
        .greek,
        .common,
        .greek,
        .common,
        .greek,
        .coptic,
        .greek,
        .cyrillic,
        .inherited,
        .cyrillic,
        .armenian,
        .common,
        .armenian,
        .hebrew,
        .arabic,
        .common,
        .arabic,
        .common,
        .arabic,
        .common,
        .arabic,
        .common,
        .arabic,
        .inherited,
        .arabic,
        .common,
        .arabic,
        .inherited,
        .arabic,
        .common,
        .arabic,
        .syriac,
        .arabic,
        .thaana,
        .nko,
        .samaritan,
        .mandaic,
        .arabic,
        .devanagari,
        .inherited,
        .devanagari,
        .common,
        .devanagari,
        .bengali,
        .gurmukhi,
        .gujarati,
        .oriya,
        .tamil,
        .telugu,
        .kannada,
        .malayalam,
        .sinhala,
        .thai,
        .common,
        .thai,
        .lao,
        .tibetan,
        .common,
        .tibetan,
        .myanmar,
        .georgian,
        .common,
        .georgian,
        .hangul,
        .ethiopic,
        .cherokee,
        .canadianAboriginal,
        .ogham,
        .runic,
        .common,
        .runic,
        .tagalog,
        .hanunoo,
        .common,
        .buhid,
        .tagbanwa,
        .khmer,
        .mongolian,
        .common,
        .mongolian,
        .common,
        .mongolian,
        .canadianAboriginal,
        .limbu,
        .taiLe,
        .newTaiLue,
        .khmer,
        .buginese,
        .taiTham,
        .balinese,
        .sundanese,
        .batak,
        .lepcha,
        .olChiki,
        .sundanese,
        .inherited,
        .common,
        .inherited,
        .common,
        .inherited,
        .common,
        .inherited,
        .common,
        .inherited,
        .common,
        .latin,
        .greek,
        .cyrillic,
        .latin,
        .greek,
        .latin,
        .greek,
        .latin,
        .cyrillic,
        .latin,
        .greek,
        .inherited,
        .latin,
        .greek,
        .common,
        .inherited,
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .inherited,
        .common,
        .greek,
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .braille,
        .common,
        .glagolitic,
        .latin,
        .coptic,
        .georgian,
        .tifinagh,
        .ethiopic,
        .cyrillic,
        .common,
        .han,
        .common,
        .han,
        .common,
        .han,
        .common,
        .han,
        .inherited,
        .hangul,
        .common,
        .han,
        .common,
        .hiragana,
        .inherited,
        .common,
        .hiragana,
        .common,
        .katakana,
        .common,
        .katakana,
        .bopomofo,
        .hangul,
        .common,
        .bopomofo,
        .common,
        .katakana,
        .hangul,
        .common,
        .hangul,
        .common,
        .katakana,
        .common,
        .han,
        .common,
        .han,
        .yi,
        .lisu,
        .vai,
        .cyrillic,
        .bamum,
        .common,
        .latin,
        .common,
        .latin,
        .sylotiNagri,
        .common,
        .phagsPa,
        .saurashtra,
        .devanagari,
        .kayahLi,
        .rejang,
        .hangul,
        .javanese,
        .cham,
        .myanmar,
        .taiViet,
        .meeteiMayek,
        .ethiopic,
        .meeteiMayek,
        .hangul,
        .unknown,
        .han,
        .latin,
        .armenian,
        .hebrew,
        .arabic,
        .common,
        .arabic,
        .common,
        .inherited,
        .common,
        .inherited,
        .common,
        .arabic,
        .common,
        .latin,
        .common,
        .latin,
        .common,
        .katakana,
        .common,
        .katakana,
        .common,
        .hangul,
        .common,
        .linearB,
        .common,
        .greek,
        .common,
        .inherited,
        .lycian,
        .carian,
        .oldItalic,
        .gothic,
        .ugaritic,
        .oldPersian,
        .deseret,
        .shavian,
        .osmanya,
        .cypriot,
        .imperialAramaic,
        .phoenician,
        .lydian,
        .meroiticHieroglyphs,
        .meroiticCursive,
        .kharoshthi,
        .oldSouthArabian,
        .avestan,
        .inscriptionalParthian,
        .inscriptionalPahlavi,
        .oldTurkic,
        .arabic,
        .brahmi,
        .kaithi,
        .soraSompeng,
        .chakma,
        .sharada,
        .takri,
        .cuneiform,
        .egyptianHieroglyphs,
        .bamum,
        .miao,
        .katakana,
        .hiragana,
        .common,
        .inherited,
        .common,
        .inherited,
        .common,
        .inherited,
        .common,
        .inherited,
        .common,
        .greek,
        .common,
        .arabic,
        .common,
        .hiragana,
        .common,
        .han,
        .common,
        .inherited,
        .unknown,
    ]
    
    private let hexValues: [UInt32] = [
        0x0000,
        0x0041,
        0x005B,
        0x0061,
        0x007B,
        0x00AA,
        0x00AB,
        0x00BA,
        0x00BB,
        0x00C0,
        0x00D7,
        0x00D8,
        0x00F7,
        0x00F8,
        0x02B9,
        0x02E0,
        0x02E5,
        0x02EA,
        0x02EC,
        0x0300,
        0x0370,
        0x0374,
        0x0375,
        0x037E,
        0x0384,
        0x0385,
        0x0386,
        0x0387,
        0x0388,
        0x03E2,
        0x03F0,
        0x0400,
        0x0485,
        0x0487,
        0x0531,
        0x0589,
        0x058A,
        0x0591,
        0x0600,
        0x060C,
        0x060D,
        0x061B,
        0x061E,
        0x061F,
        0x0620,
        0x0640,
        0x0641,
        0x064B,
        0x0656,
        0x0660,
        0x066A,
        0x0670,
        0x0671,
        0x06DD,
        0x06DE,
        0x0700,
        0x0750,
        0x0780,
        0x07C0,
        0x0800,
        0x0840,
        0x08A0,
        0x0900,
        0x0951,
        0x0953,
        0x0964,
        0x0966,
        0x0981,
        0x0A01,
        0x0A81,
        0x0B01,
        0x0B82,
        0x0C01,
        0x0C82,
        0x0D02,
        0x0D82,
        0x0E01,
        0x0E3F,
        0x0E40,
        0x0E81,
        0x0F00,
        0x0FD5,
        0x0FD9,
        0x1000,
        0x10A0,
        0x10FB,
        0x10FC,
        0x1100,
        0x1200,
        0x13A0,
        0x1400,
        0x1680,
        0x16A0,
        0x16EB,
        0x16EE,
        0x1700,
        0x1720,
        0x1735,
        0x1740,
        0x1760,
        0x1780,
        0x1800,
        0x1802,
        0x1804,
        0x1805,
        0x1806,
        0x18B0,
        0x1900,
        0x1950,
        0x1980,
        0x19E0,
        0x1A00,
        0x1A20,
        0x1B00,
        0x1B80,
        0x1BC0,
        0x1C00,
        0x1C50,
        0x1CC0,
        0x1CD0,
        0x1CD3,
        0x1CD4,
        0x1CE1,
        0x1CE2,
        0x1CE9,
        0x1CED,
        0x1CEE,
        0x1CF4,
        0x1CF5,
        0x1D00,
        0x1D26,
        0x1D2B,
        0x1D2C,
        0x1D5D,
        0x1D62,
        0x1D66,
        0x1D6B,
        0x1D78,
        0x1D79,
        0x1DBF,
        0x1DC0,
        0x1E00,
        0x1F00,
        0x2000,
        0x200C,
        0x200E,
        0x2071,
        0x2074,
        0x207F,
        0x2080,
        0x2090,
        0x20A0,
        0x20D0,
        0x2100,
        0x2126,
        0x2127,
        0x212A,
        0x212C,
        0x2132,
        0x2133,
        0x214E,
        0x214F,
        0x2160,
        0x2189,
        0x2800,
        0x2900,
        0x2C00,
        0x2C60,
        0x2C80,
        0x2D00,
        0x2D30,
        0x2D80,
        0x2DE0,
        0x2E00,
        0x2E80,
        0x2FF0,
        0x3005,
        0x3006,
        0x3007,
        0x3008,
        0x3021,
        0x302A,
        0x302E,
        0x3030,
        0x3038,
        0x303C,
        0x3041,
        0x3099,
        0x309B,
        0x309D,
        0x30A0,
        0x30A1,
        0x30FB,
        0x30FD,
        0x3105,
        0x3131,
        0x3190,
        0x31A0,
        0x31C0,
        0x31F0,
        0x3200,
        0x3220,
        0x3260,
        0x327F,
        0x32D0,
        0x3358,
        0x3400,
        0x4DC0,
        0x4E00,
        0xA000,
        0xA4D0,
        0xA500,
        0xA640,
        0xA6A0,
        0xA700,
        0xA722,
        0xA788,
        0xA78B,
        0xA800,
        0xA830,
        0xA840,
        0xA880,
        0xA8E0,
        0xA900,
        0xA930,
        0xA960,
        0xA980,
        0xAA00,
        0xAA60,
        0xAA80,
        0xAAE0,
        0xAB01,
        0xABC0,
        0xAC00,
        0xD7FC,
        0xF900,
        0xFB00,
        0xFB13,
        0xFB1D,
        0xFB50,
        0xFD3E,
        0xFD50,
        0xFDFD,
        0xFE00,
        0xFE10,
        0xFE20,
        0xFE30,
        0xFE70,
        0xFEFF,
        0xFF21,
        0xFF3B,
        0xFF41,
        0xFF5B,
        0xFF66,
        0xFF70,
        0xFF71,
        0xFF9E,
        0xFFA0,
        0xFFE0,
        0x10000,
        0x10100,
        0x10140,
        0x10190,
        0x101FD,
        0x10280,
        0x102A0,
        0x10300,
        0x10330,
        0x10380,
        0x103A0,
        0x10400,
        0x10450,
        0x10480,
        0x10800,
        0x10840,
        0x10900,
        0x10920,
        0x10980,
        0x109A0,
        0x10A00,
        0x10A60,
        0x10B00,
        0x10B40,
        0x10B60,
        0x10C00,
        0x10E60,
        0x11000,
        0x11080,
        0x110D0,
        0x11100,
        0x11180,
        0x11680,
        0x12000,
        0x13000,
        0x16800,
        0x16F00,
        0x1B000,
        0x1B001,
        0x1D000,
        0x1D167,
        0x1D16A,
        0x1D17B,
        0x1D183,
        0x1D185,
        0x1D18C,
        0x1D1AA,
        0x1D1AE,
        0x1D200,
        0x1D300,
        0x1EE00,
        0x1F000,
        0x1F200,
        0x1F201,
        0x20000,
        0xE0001,
        0xE0100,
        0xE01F0,
    ]

    // MARK: - Tests
    
    func testScriptRanges() {
        XCTAssertEqual(scripts.count, hexValues.count)
        for i in 0..<scripts.count {
            XCTAssertEqual(scripts[i], Unicode.script(for: hexValues[i]), "\(hexValues[i])")
        }
    }
    
    func testSimpleURL() {
        testURL(string: "threema.ch", expected: true)
        testURL(string: "threemа.ch", expected: false) // cyrillic a
        testURL(string: "人人贷.公司", expected: true)
        testURL(string: "gfrör.li", expected: true)
        testURL(string: "wikipedia.org", expected: true)
        testURL(string: "hallo-hallo.ch", expected: true)
        testURL(string: "🤡.org", expected: false)
    }
    
    func testMixedScriptsURL() {
        testURL(string: "\(greek)\(greek).com", expected: true)
        testURL(string: "\(latin)\(greek).ch", expected: false)
        testURL(string: "\(latin)\(han)\(hiragana)\(katakana).香港", expected: true)
        testURL(string: "\(han)\(bopomofo).香港", expected: true)
        testURL(string: "\(latin)\(han)\(bopomofo).香港", expected: true)
        testURL(string: "\(latin)\(han)\(hangul).com", expected: true)
        testURL(string: "\(hiragana)\(bopomofo).com", expected: false)
        testURL(string: "\(latin)\(han)\(hangul)\(bopomofo).com", expected: false)
        testURL(string: "\(katakana)\(hangul).ch", expected: false)
        testURL(string: "\(han)\(cyrillic).com", expected: false)
        testURL(string: "\(aLatin)\(latin).ch", expected: true)
        testURL(string: "\(aInherited)\(aLatin)\(latin).ch", expected: true)
    }

    func testMixedScriptComponentURL() {
        testURL(string: "\(greek).\(latin).\(hangul).рф", expected: true)
        testURL(string: "\(greek).\(latin)\(hangul).\(hangul).рф", expected: true)
        testURL(string: "\(greek)\(latin).\(latin).\(hangul).рф", expected: false)
    }

    // MARK: - Private functions

    private func testURL(string: String, expected: Bool) {
        
        XCTAssertEqual(URL(string: "https://\(string)")!.isIDNASafe, expected)
    }
}
