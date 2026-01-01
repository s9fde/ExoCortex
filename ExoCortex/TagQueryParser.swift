//
//  TagQueryParser.swift
//  ExoCortex
//
//  Parser for tag-based filter queries with boolean operators.
//  Supports: #tag, todo:open, todo:done, &&, ||, !, and parentheses.
//

import Foundation

// MARK: - Tag Query Parser

/// Parses and evaluates filter queries for log lines.
/// Supports tags (#tag), todo states, boolean operators (&&, ||, !), and grouping.
struct TagQueryParser {
    
    // MARK: - AST Node
    
    /// Abstract syntax tree node representing a filter expression
    enum Node {
        case tag(String)        // Match lines containing #tag
        case word(String)       // Match lines containing word
        case todoOpen           // Match open todo items [ ]
        case todoDone           // Match completed todo items [x]
        indirect case not(Node)          // Logical NOT
        indirect case and(Node, Node)    // Logical AND
        indirect case or(Node, Node)     // Logical OR
    }

    // MARK: - Public Methods
    
    /// Parse a query string into an AST
    /// - Parameter query: The filter query (e.g., "#work && todo:open")
    /// - Returns: Root node of the AST, or nil if parsing fails
    func parse(_ query: String) -> Node? {
        let tokens = tokenize(query)
        let postfix = shuntingYard(tokens)
        return buildTree(from: postfix)
    }

    /// Evaluate whether a line matches the given filter
    /// - Parameters:
    ///   - node: The filter AST (nil matches all lines)
    ///   - line: The line to test
    /// - Returns: True if the line matches the filter
    func matches(node: Node?, line: String) -> Bool {
        guard let node else { return true }
        
        let lower = line.lowercased()
        
        switch node {
        case .tag(let value):
            return lower.contains("#\(value)")
        case .word(let value):
            return lower.contains(value)
        case .todoOpen:
            return lower.contains("[ ]") || lower.contains("- [ ]")
        case .todoDone:
            return lower.contains("[x]") || lower.contains("- [x]")
        case .not(let inner):
            return !matches(node: inner, line: line)
        case .and(let lhs, let rhs):
            return matches(node: lhs, line: line) && matches(node: rhs, line: line)
        case .or(let lhs, let rhs):
            return matches(node: lhs, line: line) || matches(node: rhs, line: line)
        }
    }

    // MARK: - Tokenization
    
    private enum Token {
        case operand(Node)
        case and
        case or
        case not
        case lparen
        case rparen
    }

    private func tokenize(_ query: String) -> [Token] {
        query.split(whereSeparator: \.isWhitespace).compactMap { fragment -> Token? in
            let value = String(fragment)
            
            switch value.lowercased() {
            case "&&": return .and
            case "||": return .or
            case "!": return .not
            case "(": return .lparen
            case ")": return .rparen
            case "todo:open": return .operand(.todoOpen)
            case "todo:done": return .operand(.todoDone)
            default:
                if value == "(" { return .lparen }
                if value == ")" { return .rparen }
                if value.hasPrefix("#") {
                    return .operand(.tag(String(value.dropFirst()).lowercased()))
                }
                return .operand(.word(value.lowercased()))
            }
        }
    }

    // MARK: - Shunting Yard Algorithm
    
    private func shuntingYard(_ tokens: [Token]) -> [Token] {
        var output: [Token] = []
        var operators: [Token] = []

        func precedence(_ token: Token) -> Int {
            switch token {
            case .not: return 3
            case .and: return 2
            case .or: return 1
            default: return 0
            }
        }

        func isOperator(_ token: Token) -> Bool {
            switch token {
            case .and, .or, .not: return true
            default: return false
            }
        }

        for token in tokens {
            switch token {
            case .operand:
                output.append(token)
            case .and, .or, .not:
                while let last = operators.last, isOperator(last), precedence(last) >= precedence(token) {
                    output.append(operators.removeLast())
                }
                operators.append(token)
            case .lparen:
                operators.append(token)
            case .rparen:
                while let last = operators.last {
                    if case .lparen = last { break }
                    output.append(operators.removeLast())
                }
                if let last = operators.last, case .lparen = last {
                    operators.removeLast()
                }
            }
        }
        
        while let last = operators.popLast() {
            output.append(last)
        }
        
        return output
    }

    // MARK: - AST Construction
    
    private func buildTree(from postfix: [Token]) -> Node? {
        var stack: [Node] = []
        
        for token in postfix {
            switch token {
            case .operand(let node):
                stack.append(node)
            case .not:
                guard let last = stack.popLast() else { return nil }
                stack.append(.not(last))
            case .and:
                guard let rhs = stack.popLast(), let lhs = stack.popLast() else { return nil }
                stack.append(.and(lhs, rhs))
            case .or:
                guard let rhs = stack.popLast(), let lhs = stack.popLast() else { return nil }
                stack.append(.or(lhs, rhs))
            case .lparen, .rparen:
                break
            }
        }
        
        return stack.last
    }
}
