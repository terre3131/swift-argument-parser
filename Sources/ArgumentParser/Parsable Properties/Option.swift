//===----------------------------------------------------------*- swift -*-===//
//
// This source file is part of the Swift Argument Parser open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// A wrapper that represents a command-line option.
///
/// An option is a value that can be specified as a named value on the command
/// line. An option can have a default values specified as part of its
/// declaration; options with optional `Value` types implicitly have `nil` as
/// their default value.
///
///     struct Options: ParsableArguments {
///         @Option(default: "Hello") var greeting: String
///         @Option var name: String
///         @Option var age: Int?
///     }
///
/// `greeting` has a default value of `"Hello"`, which can be overridden by
/// providing a different string as an argument. `age` defaults to `nil`, while
/// `name` is a required argument because it is non-`nil` and has no default
/// value.
@propertyWrapper
public struct Option<Value>: Decodable, ParsedWrapper {
  internal var _parsedValue: Parsed<Value>
  
  internal init(_parsedValue: Parsed<Value>) {
    self._parsedValue = _parsedValue
  }
  
  public init(from decoder: Decoder) throws {
    try self.init(_decoder: decoder)
  }
  
  /// The value presented by this property wrapper.
  public var wrappedValue: Value {
    get {
      switch _parsedValue {
      case .value(let v):
        return v
      case .definition:
        fatalError("Trying to read value from definition.")
      }
    }
    set {
      _parsedValue = .value(newValue)
    }
  }
}

extension Option: CustomStringConvertible {
  public var description: String {
    switch _parsedValue {
    case .value(let v):
      return String(describing: v)
    case .definition:
      return "Option(*definition*)"
    }
  }
}

extension Option: DecodableParsedWrapper where Value: Decodable {}

// MARK: Property Wrapper Initializers

extension Option where Value: ExpressibleByArgument {
  /// Creates a property that reads its value from an labeled option.
  ///
  /// If the property has an `Optional` type, or you provide a non-`nil`
  /// value for the `initial` parameter, specifying this option is not
  /// required.
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - initial: A default value to use for this property.
  ///   - help: Information about how to use this option.
  public init(
    name: NameSpecification = .long,
    default initial: Value? = nil,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    help: ArgumentHelp? = nil
  ) {
    self.init(_parsedValue: .init { key in
      ArgumentSet(
        key: key,
        kind: .name(key: key, specification: name),
        parsingStrategy: ArgumentDefinition.ParsingStrategy(parsingStrategy),
        parseType: Value.self,
        name: name,
        default: initial, help: help)
      })
  }
}

/// The strategy to use when parsing a single value from `@Option` arguments.
///
/// - SeeAlso: `ArrayParsingStrategy``
public enum SingleValueParsingStrategy {
  /// Parse the input after the option. Expect it to be a value.
  ///
  /// For input such as `--foo foo` this would parse `foo` as the
  /// value. However, for the input `--foo --bar foo bar` would
  /// result in a error. Even though two values are provided, they don’t
  /// succeed each option. Parsing would result in an error such as
  ///
  ///     Error: Missing value for '--foo <foo>'
  ///     Usage: command [--foo <foo>]
  ///
  /// This is the **default behavior** for `@Option`-wrapped properties.
  case next
  
  /// Parse the next input, even if it could be interpreted as an option or
  /// flag.
  ///
  /// For input such as `--foo --bar baz`, if `.unconditional` is used for `foo`,
  /// this would read `--bar` as the value for `foo` and would use `baz` as
  /// the next positional argument.
  ///
  /// This allows reading negative numeric values, or capturing flags to be
  /// passed through to another program, since the leading hyphen is normally
  /// interpreted as the start of another option.
  ///
  /// - Note: This is usually *not* what users would expect. Use with caution.
  case unconditional
  
  /// Parse the next input, as long as that input can't be interpreted as
  /// an option or flag.
  ///
  /// - Note: This will skip other options and _read ahead_ in the input
  /// to find the next available value. This may be *unexpected* for users.
  /// Use with caution.
  ///
  /// For example, if `--foo` takes an values, then the input `--foo --bar bar`
  /// would be parsed such that the value `bar` is used for `--foo`.
  case scanningForValue
}

/// The strategy to use when parsing multiple values from `@Option` arguments into an
/// array.
public enum ArrayParsingStrategy {
  /// Parse one value per option, joining multiple into an array.
  ///
  /// For example, for a parsable type with a property defined as
  /// `@Option(parsing: .singleValue) var read: [String]`
  /// the input `--read foo --read bar` would result in the array
  /// `["foo", "bar"]`. The same would be true for the input
  /// `--read=foo --read=bar`.
  ///
  /// - Note: This follows the default behavior of differentiating between values and options. As
  ///     such the value for this option will be the next value (non-option) in the input. For the
  ///     above example, the input `--read --name Foo Bar` would parse `Foo` into
  ///     `read` (and `Bar` into `name`).
  case singleValue
  
  /// Parse the value immediately after the option while allowing repeating options, joining multiple into an array.
  ///
  /// This is identical to `.singleValue` except that the value will be read
  /// from the input immediately after the option even it it could be interpreted as an option.
  ///
  /// For example, for a parsable type with a property defined as
  /// `@Option(parsing: .unconditionalSingleValue) var read: [String]`
  /// the input `--read foo --read bar` would result in the array
  /// `["foo", "bar"]` -- just as it would have been the case for `.singleValue`.
  ///
  /// - Note: However, the input `--read --name Foo Bar --read baz` would result in
  /// `read` being set to the array `["--name", "baz"]`. This is usually *not* what users
  /// would expect. Use with caution.
  case unconditionalSingleValue
  
  /// Parse all values up to the next option.
  ///
  /// For example, for a parsable type with a property defined as
  /// `@Option(parsing: .upToNextOption) var files: [String]`
  /// the input `--files foo bar` would result in the array
  /// `["foo", "bar"]`.
  ///
  /// Parsing stops as soon as there’s another option in the input, such that
  /// `--files foo bar --verbose` would also set `files` to the array
  /// `["foo", "bar"]`.
  case upToNextOption
  
  /// Parse all remaining arguments into an array.
  ///
  /// `.remaining` can be used for capturing pass-through flags. For example, for
  /// a parsable type defined as
  /// `@Option(parsing: .remaining) var passthrough: [String]`:
  ///
  ///     $ cmd --passthrough --foo 1 --bar 2 -xvf
  ///     ------------
  ///     options.passthrough == ["--foo", "1", "--bar", "2", "-xvf"]
  ///
  /// - Note: This will read all input following the option, without attempting to do any parsing. This is
  /// usually *not* what users would expect. Use with caution.
  ///
  /// Consider using a trailing `@Argument` instead, and letting users explicitly turn off parsing
  /// through the terminator `--`. That is the more common approach. For example:
  /// ```swift
  /// struct Options: ParsableArguments {
  ///     @Option()
  ///     var name: String
  ///
  ///     @Argument()
  ///     var remainder: [String]
  /// }
  /// ```
  /// would allow to parse the input `--name Foo -- Bar --baz` such that the `remainder`
  /// would hold the values `["Bar", "--baz"]`.
  case remaining
}

extension Option {
  /// Creates a property that reads its value from an labeled option, parsing
  /// with the given closure.
  ///
  /// If the property has an `Optional` type, or you provide a non-`nil`
  /// value for the `initial` parameter, specifying this option is not
  /// required.
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - initial: A default value to use for this property.
  ///   - help: Information about how to use this option.
  ///   - transform: A closure that converts a string into this property's
  ///     type or throws an error.
  public init(
    name: NameSpecification = .long,
    default initial: Value? = nil,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    help: ArgumentHelp? = nil,
    transform: @escaping (String) throws -> Value
  ) {
    self.init(_parsedValue: .init { key in
      let kind = ArgumentDefinition.Kind.name(key: key, specification: name)
      let help = ArgumentDefinition.Help(options: [], help: help, key: key)
      let arg = ArgumentDefinition(kind: kind, help: help, parsingStrategy: ArgumentDefinition.ParsingStrategy(parsingStrategy), update: .unary({
        (origin, _, valueString, parsedValues) in
        parsedValues.set(try transform(valueString), forKey: key, inputOrigin: origin)
      }), initial: { origin, values in
        if let v = initial {
          values.set(v, forKey: key, inputOrigin: origin)
        }
      })
      return ArgumentSet(alternatives: [arg])
      })
  }
  
  /// Creates an array property that reads its values from zero or more
  /// labeled options.
  ///
  /// This property defaults to an empty array.
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - parsingStrategy: The behavior to use when parsing multiple values
  ///     from the command-line arguments.
  ///   - help: Information about how to use this option.
  public init<Element>(
    name: NameSpecification = .long,
    parsing parsingStrategy: ArrayParsingStrategy = .singleValue,
    help: ArgumentHelp? = nil
  ) where Element: ExpressibleByArgument, Value == Array<Element> {
    self.init(_parsedValue: .init { key in
      let kind = ArgumentDefinition.Kind.name(key: key, specification: name)
      let help = ArgumentDefinition.Help(options: [.isOptional, .isRepeating], help: help, key: key)
      let arg = ArgumentDefinition(kind: kind, help: help, parsingStrategy: ArgumentDefinition.ParsingStrategy(parsingStrategy), update: .appendToArray(forType: Element.self, key: key), initial: { origin, values in
        values.set([], forKey: key, inputOrigin: origin)
      })
      return ArgumentSet(alternatives: [arg])
      })
  }
  
  /// Creates an array property that reads its values from zero or more
  /// labeled options, parsing with the given closure.
  ///
  /// This property defaults to an empty array.
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - parsingStrategy: The behavior to use when parsing multiple values
  ///     from the command-line arguments.
  ///   - help: Information about how to use this option.
  ///   - transform: A closure that converts a string into this property's
  ///     element type or throws an error.
  public init<Element>(
    name: NameSpecification = .long,
    parsing parsingStrategy: ArrayParsingStrategy = .singleValue,
    help: ArgumentHelp? = nil,
    transform: @escaping (String) throws -> Element
  ) where Value == Array<Element> {
    self.init(_parsedValue: .init { key in
      let kind = ArgumentDefinition.Kind.name(key: key, specification: name)
      let help = ArgumentDefinition.Help(options: [.isOptional, .isRepeating], help: help, key: key)
      let arg = ArgumentDefinition(kind: kind, help: help, parsingStrategy: ArgumentDefinition.ParsingStrategy(parsingStrategy), update: .unary({
        (origin, name, valueString, parsedValues) in
        let element = try transform(valueString)
        parsedValues.update(forKey: key, inputOrigin: origin, initial: [Element](), closure: {
          $0.append(element)
        })
      }),
                                   initial: { origin, values in
                                    values.set([], forKey: key, inputOrigin: origin)
      })
      return ArgumentSet(alternatives: [arg])
      })
  }
}
