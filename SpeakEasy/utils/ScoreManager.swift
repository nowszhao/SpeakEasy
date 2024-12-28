import Foundation

class ScoreManager {
    func calculateScore(original: String, transcribed: String) -> (Double, [MismatchedWord]) {
        // 预处理文本：去除标点和空格，转换为字符数组
        let originalChars = preprocessText(original)
        let transcribedChars = preprocessText(transcribed)
        
        // print("原始文本(处理后): \(originalChars)")
        // print("识别文本(处理后): \(transcribedChars)")
        
        // 计算最长公共子序列
        let lcs = longestCommonSubsequence(originalChars, transcribedChars)
        
        // 计算匹配分数
        let matchCount = lcs.count
        let totalCount = originalChars.count
        let score = totalCount > 0 ? Double(matchCount) / Double(totalCount) : 0
        
        // 标记不匹配的字符
        let mismatches = findMismatches(
            original: originalChars,
            transcribed: transcribedChars,
            lcs: lcs
        )
        
        print("匹配字数: \(matchCount), 总字数: \(totalCount), 得分: \(score)")
        
        return (score, mismatches)
    }
    
    private func preprocessText(_ text: String) -> [Character] {
        // 移除标点符号和空白字符
        let filtered = text.filter { char in
            !char.isPunctuation && !char.isWhitespace
        }
        return Array(filtered)
    }
    
    private func longestCommonSubsequence(_ text1: [Character], _ text2: [Character]) -> [Character] {
        let m = text1.count
        let n = text2.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        // 填充 DP 表
        for i in 1...m {
            for j in 1...n {
                if text1[i-1] == text2[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else {
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
                }
            }
        }
        
        // 回溯找出最长公共子序列
        var lcs: [Character] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if text1[i-1] == text2[j-1] {
                lcs.insert(text1[i-1], at: 0)
                i -= 1
                j -= 1
            } else if dp[i-1][j] > dp[i][j-1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        
        return lcs
    }
    
    private func findMismatches(original: [Character], transcribed: [Character], lcs: [Character]) -> [MismatchedWord] {
        var mismatches: [MismatchedWord] = []
        var originalIndex = 0
        var transcribedIndex = 0
        var lcsIndex = 0
        var currentMismatch = ""
        var startIndex = 0
        
        while transcribedIndex < transcribed.count {
            if lcsIndex < lcs.count && transcribed[transcribedIndex] == lcs[lcsIndex] {
                // 当前字符匹配
                if !currentMismatch.isEmpty {
                    // 保存之前收集的不匹配字符
                    mismatches.append(MismatchedWord(
                        word: currentMismatch,
                        startIndex: startIndex,
                        endIndex: transcribedIndex
                    ))
                    currentMismatch = ""
                }
                lcsIndex += 1
                transcribedIndex += 1
                originalIndex += 1
            } else {
                // 当前字符不匹配
                if currentMismatch.isEmpty {
                    startIndex = transcribedIndex
                }
                currentMismatch.append(transcribed[transcribedIndex])
                transcribedIndex += 1
            }
        }
        
        // 处理最后一个不匹配部分
        if !currentMismatch.isEmpty {
            mismatches.append(MismatchedWord(
                word: currentMismatch,
                startIndex: startIndex,
                endIndex: transcribedIndex
            ))
        }
        
        return mismatches
    }
}

extension Character {
    var isPunctuation: Bool {
        // 检查是否为标点符号
        if let scalar = String(self).unicodeScalars.first {
            return CharacterSet.punctuationCharacters.contains(scalar)
                || scalar.properties.generalCategory == .otherPunctuation
                || scalar.properties.generalCategory == .initialPunctuation
                || scalar.properties.generalCategory == .finalPunctuation
        }
        return false
    }
} 