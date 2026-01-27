//
//  CalculatorTool.swift
//  AISDKCLI
//
//  Calculator tool that evaluates mathematical expressions
//

import Foundation
import AISDK

/// Calculator tool that evaluates mathematical expressions
struct CalculatorTool: Tool {
    let name = "calculator"
    let description = "Evaluate mathematical expressions. Supports basic arithmetic (+, -, *, /), parentheses, and common functions (sqrt, sin, cos, tan, log, exp, pow, abs, floor, ceil, round)."

    @Parameter(description: "The mathematical expression to evaluate (e.g., '2 + 2', 'sqrt(16)', 'sin(3.14159/2)')")
    var expression: String = ""

    init() {}

    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        do {
            let result = try evaluate(expression)
            return (formatResult(expression: expression, result: result), nil)
        } catch let error as CalculatorError {
            return ("Error evaluating '\(expression)': \(error.localizedDescription)", nil)
        }
    }

    // MARK: - Expression Evaluation

    private enum CalculatorError: LocalizedError {
        case invalidExpression(String)
        case divisionByZero
        case invalidFunction(String)
        case syntaxError(String)

        var errorDescription: String? {
            switch self {
            case .invalidExpression(let msg):
                return "Invalid expression: \(msg)"
            case .divisionByZero:
                return "Division by zero"
            case .invalidFunction(let name):
                return "Unknown function: \(name)"
            case .syntaxError(let msg):
                return "Syntax error: \(msg)"
            }
        }
    }

    private func evaluate(_ expression: String) throws -> Double {
        // Clean expression
        var expr = expression
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        // Replace constants
        expr = expr.replacingOccurrences(of: "pi", with: String(Double.pi))
        expr = expr.replacingOccurrences(of: "e", with: String(M_E))

        // Replace functions with internal markers
        expr = try replaceFunction(expr, name: "sqrt", function: { sqrt($0) })
        expr = try replaceFunction(expr, name: "sin", function: { sin($0) })
        expr = try replaceFunction(expr, name: "cos", function: { cos($0) })
        expr = try replaceFunction(expr, name: "tan", function: { tan($0) })
        expr = try replaceFunction(expr, name: "log", function: { log($0) })
        expr = try replaceFunction(expr, name: "log10", function: { log10($0) })
        expr = try replaceFunction(expr, name: "exp", function: { exp($0) })
        expr = try replaceFunction(expr, name: "abs", function: { abs($0) })
        expr = try replaceFunction(expr, name: "floor", function: { floor($0) })
        expr = try replaceFunction(expr, name: "ceil", function: { ceil($0) })
        expr = try replaceFunction(expr, name: "round", function: { round($0) })

        // Handle pow(a, b) specially
        expr = try replacePowFunction(expr)

        // Evaluate the expression using NSExpression
        // Note: NSExpression doesn't handle all cases, so we use a simple recursive descent parser
        return try evaluateExpression(expr)
    }

    private func replaceFunction(_ expr: String, name: String, function: (Double) -> Double) throws -> String {
        var result = expr
        while let range = result.range(of: "\(name)(") {
            let startIndex = range.upperBound
            guard let endIndex = findMatchingParen(result, from: startIndex) else {
                throw CalculatorError.syntaxError("Unmatched parenthesis in \(name)()")
            }

            let innerExpr = String(result[startIndex..<endIndex])
            let innerValue = try evaluate(innerExpr)
            let computedValue = function(innerValue)

            let fullRange = result.index(range.lowerBound, offsetBy: 0)..<result.index(after: endIndex)
            result.replaceSubrange(fullRange, with: String(computedValue))
        }
        return result
    }

    private func replacePowFunction(_ expr: String) throws -> String {
        var result = expr
        while let range = result.range(of: "pow(") {
            let startIndex = range.upperBound
            guard let endIndex = findMatchingParen(result, from: startIndex) else {
                throw CalculatorError.syntaxError("Unmatched parenthesis in pow()")
            }

            let innerExpr = String(result[startIndex..<endIndex])
            let parts = innerExpr.split(separator: ",", maxSplits: 1)
            guard parts.count == 2 else {
                throw CalculatorError.syntaxError("pow() requires two arguments")
            }

            let base = try evaluate(String(parts[0]))
            let exponent = try evaluate(String(parts[1]))
            let computedValue = pow(base, exponent)

            let fullRange = result.index(range.lowerBound, offsetBy: 0)..<result.index(after: endIndex)
            result.replaceSubrange(fullRange, with: String(computedValue))
        }
        return result
    }

    private func findMatchingParen(_ str: String, from start: String.Index) -> String.Index? {
        var depth = 1
        var current = start

        while current < str.endIndex {
            let char = str[current]
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth == 0 {
                    return current
                }
            }
            current = str.index(after: current)
        }

        return nil
    }

    // Simple expression evaluator
    private func evaluateExpression(_ expr: String) throws -> Double {
        var index = expr.startIndex
        return try parseAddSub(expr, &index)
    }

    private func parseAddSub(_ expr: String, _ index: inout String.Index) throws -> Double {
        var left = try parseMulDiv(expr, &index)

        while index < expr.endIndex {
            let char = expr[index]
            if char == "+" {
                index = expr.index(after: index)
                let right = try parseMulDiv(expr, &index)
                left = left + right
            } else if char == "-" {
                index = expr.index(after: index)
                let right = try parseMulDiv(expr, &index)
                left = left - right
            } else {
                break
            }
        }

        return left
    }

    private func parseMulDiv(_ expr: String, _ index: inout String.Index) throws -> Double {
        var left = try parsePower(expr, &index)

        while index < expr.endIndex {
            let char = expr[index]
            if char == "*" {
                index = expr.index(after: index)
                let right = try parsePower(expr, &index)
                left = left * right
            } else if char == "/" {
                index = expr.index(after: index)
                let right = try parsePower(expr, &index)
                if right == 0 {
                    throw CalculatorError.divisionByZero
                }
                left = left / right
            } else if char == "%" {
                index = expr.index(after: index)
                let right = try parsePower(expr, &index)
                left = left.truncatingRemainder(dividingBy: right)
            } else {
                break
            }
        }

        return left
    }

    private func parsePower(_ expr: String, _ index: inout String.Index) throws -> Double {
        let left = try parseUnary(expr, &index)

        if index < expr.endIndex && expr[index] == "^" {
            index = expr.index(after: index)
            let right = try parsePower(expr, &index)  // Right associative
            return pow(left, right)
        }

        return left
    }

    private func parseUnary(_ expr: String, _ index: inout String.Index) throws -> Double {
        if index < expr.endIndex && expr[index] == "-" {
            index = expr.index(after: index)
            return -(try parseUnary(expr, &index))
        }
        if index < expr.endIndex && expr[index] == "+" {
            index = expr.index(after: index)
            return try parseUnary(expr, &index)
        }
        return try parsePrimary(expr, &index)
    }

    private func parsePrimary(_ expr: String, _ index: inout String.Index) throws -> Double {
        if index < expr.endIndex && expr[index] == "(" {
            index = expr.index(after: index)
            let result = try parseAddSub(expr, &index)
            if index < expr.endIndex && expr[index] == ")" {
                index = expr.index(after: index)
            }
            return result
        }

        return try parseNumber(expr, &index)
    }

    private func parseNumber(_ expr: String, _ index: inout String.Index) throws -> Double {
        var numStr = ""
        var hasDecimal = false

        while index < expr.endIndex {
            let char = expr[index]
            if char.isNumber {
                numStr.append(char)
                index = expr.index(after: index)
            } else if char == "." && !hasDecimal {
                numStr.append(char)
                hasDecimal = true
                index = expr.index(after: index)
            } else {
                break
            }
        }

        guard let number = Double(numStr) else {
            throw CalculatorError.invalidExpression("Expected number at position")
        }

        return number
    }

    // MARK: - Result Formatting

    private func formatResult(expression: String, result: Double) -> String {
        let formattedResult: String
        if result.truncatingRemainder(dividingBy: 1) == 0 && abs(result) < 1e15 {
            formattedResult = String(format: "%.0f", result)
        } else {
            formattedResult = String(format: "%.10g", result)
        }

        return """
        📊 Calculation Result

        Expression: \(expression)
        Result: \(formattedResult)
        """
    }
}
