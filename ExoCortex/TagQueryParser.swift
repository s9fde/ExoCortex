import Foundation

struct TagQueryParser {
    enum Node {
        case tag(String)
        case word(String)
        case todoOpen
        case todoDone
        indirect case not(Node)
        indirect case and(Node, Node)
        indirect case or(Node, Node)
    }

    func parse(_ query: String) -> Node? {
        let tokens = tokenize(query)
        let output = shuntingYard(tokens)
        return buildTree(from: output)
    }

    func matches(node: Node?, line: String) -> Bool {
        guard let node else { return true }
        let lower = line.lowercased()
        switch node {
        case .tag(let value):
            return lower.contains("#" + value)
        case .word(let value):
            return lower.contains(value)
        case .todoOpen:
            return isOpenTodo(line: lower)
        case .todoDone:
            return isDoneTodo(line: lower)
        case .not(let inner):
            return !matches(node: inner, line: line)
        case .and(let lhs, let rhs):
            return matches(node: lhs, line: line) && matches(node: rhs, line: line)
        case .or(let lhs, let rhs):
            return matches(node: lhs, line: line) || matches(node: rhs, line: line)
        }
    }

    private enum Token {
        case operand(Node)
        case and
        case or
        case not
        case lparen
        case rparen
    }

    private func tokenize(_ query: String) -> [Token] {
        let raw = query.split(whereSeparator: { $0.isWhitespace })
        return raw.compactMap { fragment -> Token? in
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
                } else {
                    return .operand(.word(value.lowercased()))
                }
            }
        }
    }

    private func shuntingYard(_ tokens: [Token]) -> [Token] {
        var output: [Token] = []
        var ops: [Token] = []

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
            case .and, .or, .not:
                return true
            default:
                return false
            }
        }

        for token in tokens {
            switch token {
            case .operand:
                output.append(token)
            case .and, .or, .not:
                while let last = ops.last, isOperator(last), precedence(last) >= precedence(token) {
                    output.append(ops.removeLast())
                }
                ops.append(token)
            case .lparen:
                ops.append(token)
            case .rparen:
                while let last = ops.last {
                    if case .lparen = last { break }
                    output.append(ops.removeLast())
                }
                if let last = ops.last, case .lparen = last {
                    ops.removeLast()
                }
            }
        }
        while let last = ops.popLast() {
            output.append(last)
        }
        return output
    }

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

    private func isOpenTodo(line: String) -> Bool {
        line.contains("[ ]") || line.contains("- [ ]")
    }

    private func isDoneTodo(line: String) -> Bool {
        line.contains("[x]") || line.contains("[X]") || line.contains("- [x]") || line.contains("- [X]")
    }
}
