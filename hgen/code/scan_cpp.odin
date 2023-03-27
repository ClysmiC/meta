package main

import scan "core:text/scanner"
import "core:strings"

Token_Type :: enum
{
    Nil = 0,
    
    Identifier,
    L_Paren,
    R_Paren,
    L_Bracket,
    R_Bracket,
    L_Brace,
    R_Brace,
    Comma,
    Preprocessor_Directive,
    Literal,
    Colon,
    Colon_Colon,
    Semicolon,
    Operator, // NOTE - Operators that we don't scan for in particular get bundled into here

    // Operators that we *do* scan for
    Equal,

    Comment,

    // Select reserved words
    Namespace,
    Inline,
    Enum,
    Class,
    Struct,
    Union,
    Template,
    Using,
    Typedef,

    // Pseudo-reserved words
    // (Not actually keywords, but I use them as if they are)
    Function,
    /* ImportNamespace, */
    /* ImportNamespaceAs, */

    Error,
    Eof,
}

Token :: struct
{
    type: Token_Type,
    lexeme: string,
}

scan_until_or_past_token_set :: proc(scanner: ^scan.Scanner, set: []Token_Type, should_pass: bool, only_match_in_this_context: bool) -> Token_Type
{
    result := Token_Type.Eof; // HMM - Should the default "not found" value be Nil? Eof kinda makes sense too...
    
    should_pass := should_pass;

    cnt_paren := 0;
    cnt_brace := 0;
    cnt_bracket := 0;

    LScan:
    for
    {
        token := peek_token(scanner);

        if !only_match_in_this_context || (cnt_paren == 0 && cnt_brace == 0 && cnt_bracket == 0)
        {
            for candidate in set
            {
                if candidate == token.type
                {
                    result = candidate;
                    break LScan;
                }
            }
        }

        #partial switch token.type
        {
            case .L_Paren: cnt_paren += 1;
            case .L_Bracket: cnt_bracket += 1;
            case .L_Brace: cnt_brace += 1;

            // @Hack, @Punt, this used to verify_or_panic, but scan_cpp.odin really shouldn't depend on that.
            //  There should be a better way to handle this, but for now I'll punt and just prematurely exit the scan
            //  without consuming the violating token

            case .R_Paren:      cnt_paren -= 1;     if cnt_paren < 0    { break; }
            case .R_Bracket:    cnt_bracket -= 1;   if cnt_bracket < 0  { break; }
            case .R_Brace:      cnt_brace -= 1;     if cnt_brace < 0    { break; }
        }

        next_token(scanner);
        if token.type == .Eof
        {
            should_pass = false; // We already consumed EOF
            break;
        }

        // TODO - Handle .Error ?
    }

    if should_pass
    {
        next_token(scanner);
    }

    return result;
}

scan_until_token_set :: #force_inline proc(scanner: ^scan.Scanner, set: []Token_Type) -> Token_Type
{
    return scan_until_or_past_token_set(scanner, set, false, false);
}

scan_until_token :: #force_inline proc(scanner: ^scan.Scanner, type: Token_Type) -> Token_Type
{
    return scan_until_or_past_token_set(scanner, []Token_Type{ type }, false, false);
}

scan_until_token_set_in_current_context :: #force_inline proc(scanner: ^scan.Scanner, set: []Token_Type) -> Token_Type
{
    return scan_until_or_past_token_set(scanner, set, false, true);
}

scan_until_token_in_current_context :: #force_inline proc(scanner: ^scan.Scanner, type: Token_Type) -> Token_Type
{
    return scan_until_or_past_token_set(scanner, []Token_Type{ type }, false, true);
}

scan_past_token_set :: #force_inline proc(scanner: ^scan.Scanner, set: []Token_Type) -> Token_Type
{
    return scan_until_or_past_token_set(scanner, set, true, false);
}

scan_past_token :: #force_inline proc(scanner: ^scan.Scanner, type: Token_Type) -> Token_Type
{
    return scan_until_or_past_token_set(scanner, []Token_Type{ type }, true, false);
}

scan_past_token_set_in_current_context :: #force_inline proc(scanner: ^scan.Scanner, set: []Token_Type) -> Token_Type
{
    return scan_until_or_past_token_set(scanner, set, true, true);
}

scan_past_token_in_current_context :: #force_inline proc(scanner: ^scan.Scanner, type: Token_Type) -> Token_Type
{
    return scan_until_or_past_token_set(scanner, []Token_Type{ type }, true, true);
}

scan_past :: proc{ scan_past_token, scan_past_token_set };
scan_until :: proc{ scan_until_token, scan_until_token_set };
scan_past_in_current_context :: proc{ scan_past_token_in_current_context, scan_past_token_set_in_current_context };
scan_until_in_current_context :: proc{ scan_until_token_in_current_context, scan_until_token_set_in_current_context };

scan_past_comments :: proc(scanner: ^scan.Scanner, consume_trailing_whitespace := true)
{
    for
    {
        token := peek_token(scanner);
        if token.type == .Comment
        {
            next_token(scanner);
        }
        else
        {
            break;
        }
    }

    if consume_trailing_whitespace
    {
        consume_whitespace(scanner);
    }
}

next_token :: proc(scanner: ^scan.Scanner) -> Token
{
    using scan;

    for
    {
        consume_whitespace(scanner);

        start := position(scanner).offset;
        
        c := peek(scanner);

        switch c
        {
            case EOF: return Token{ .Eof, scanner.src[start : position(scanner).offset] };

            case '#':
            {
                // TODO - This might break if there is a // or /* comment on the same line after the preprocessor directive

                for
                {
                    line := consume_until_new_line(scanner);
                    if !strings.has_suffix(line, "\\")
                    {
                        break;
                    }

                    consume_past_new_line(scanner);
                }
                
                return Token{ .Preprocessor_Directive, scanner.src[start : position(scanner).offset] };
            }

            case 'a'..'z', 'A'..'Z', '_':
            {
                next(scanner);

                LIdent:
                for
                {
                    c_peek := peek(scanner);
                    switch c_peek
                    {
                        case 'a'..'z', 'A'..'Z', '_', '0'..'9':
                        {
                            next(scanner);
                        }

                        case:
                        {
                            break LIdent;
                        }
                    }
                }

                // Check for reserved words

                result := Token{ .Identifier, scanner.src[start : position(scanner).offset] };
                switch result.lexeme
                {
                    case "namespace":         result.type = .Namespace;
                    case "inline":            result.type = .Inline;
                    case "enum":              result.type = .Enum;
                    case "class":             result.type = .Class;
                    case "struct":            result.type = .Struct;
                    case "union":             result.type = .Union;
                    case "function":          result.type = .Function;
                    /* case "ImportNamespace":   result.type = .ImportNamespace; */
                    /* case "ImportNamespaceAs": result.type = .ImportNamespaceAs; */
                    case "template":          result.type = .Template;
                    case "using":             result.type = .Using;
                    case "typedef":           result.type = .Typedef;
                }
                    
                return result;
            }

            case ':':
            {
                next(scanner);

                if peek(scanner) == ':'
                {
                    next(scanner);
                    return Token{ .Colon_Colon, scanner.src[start : position(scanner).offset] };
                }
                else
                {
                    return Token{ .Colon, scanner.src[start : position(scanner).offset] };
                }
            }

            case '"':
            {
                next(scanner);

                for
                {
                    consume_until(scanner, []rune{'\\', '\"'});

                    maybe_close_quote := next(scanner);
                    switch maybe_close_quote
                    {
                        case '\"': return Token{ .Literal, scanner.src[start : position(scanner).offset] };
                        case '\\': next(scanner); // Skip the escaped character, it has no bearing for us
                        case:
                        {
                            assert(maybe_close_quote == EOF);
                            return Token{ .Error, scanner.src[start : position(scanner).offset] };
                        }
                    }
                }
            }
            
            case '/':
            {
                next(scanner);
                c_peek := peek(scanner);
                if c_peek == '/'
                {
                    next(scanner);
                    consume_until_new_line(scanner);
                    return Token{ .Comment, scanner.src[start : position(scanner).offset] };
                }
                else if c_peek == '*'
                {
                    next(scanner);
                    consume_until(scanner, "*/");

                    maybe_star := next(scanner);
                    maybe_slash := next(scanner);
                    
                    if maybe_star == '*' && maybe_slash == '/'
                    {
                        return Token{ .Comment, scanner.src[start : position(scanner).offset] };
                    }
                    else
                    {
                        assert(maybe_star == EOF);
                        return Token{ .Error, scanner.src[start : position(scanner).offset] };
                    }
                }
                else if c_peek == '='
                {
                    next(scanner);
                }

                return Token{ .Operator, scanner.src[start : position(scanner).offset] };
            }

            // @Hack - Folding a lot of things (including pointers, references, ?) into "operator".
            //  I don't make much of an effort to distinguish between things like multiplication vs pointer (*)
            //  or 'and' vs rvalue reference (&&), since the code-gen doesn't really need to know any of that.
            
            case '+', '-', '&', '|', '=':
            {
                // Operators that can exist alone, duplicated, or trailed by = (e.g., +, ++, +=)
                // Also handles ->
                
                next(scanner);
                
                c_peek := peek(scanner);

                advanced_again := false;
                if (c_peek == c) || (c == '-' && c_peek == '>') || c_peek == '='
                {
                    advanced_again = true;
                    next(scanner);
                }

                result_type := Token_Type.Operator;
                if c == '=' && !advanced_again
                {
                    result_type = .Equal;
                }

                return Token{ result_type, scanner.src[start : position(scanner).offset] };
            }

            case '<', '>':
            {
                // Operators that can exist alone, duplicated, trailed by =, or duplicated and trailed by =
                
                next(scanner);
                
                c_peek := peek(scanner);
                if c_peek == c
                {
                    next(scanner);
                }

                c_peek = peek(scanner);
                if c_peek == '='
                {
                    next(scanner);
                }
                
                return Token{ .Operator, scanner.src[start : position(scanner).offset] };
            }

            case '!', '*', '%':
            {
                // Operators that can exist alone, or trailed by =
                
                next(scanner);
                
                c_peek := peek(scanner);
                if c_peek == '='
                {
                    next(scanner);
                }

                return Token{ .Operator, scanner.src[start : position(scanner).offset] };
            }

            case '?', '^', '~':
            {
                // Operators that can't really be followed by anything.
                //  No attempt is made to detect the ternary operator. In fact, we return .Colon for ':'
                //  since we actually care about that one in enum declarations.

                next(scanner);
                return Token{ .Operator, scanner.src[start : position(scanner).offset] };
            }

            case '(':
            {
                next(scanner);
                return Token{ .L_Paren, scanner.src[start : position(scanner).offset] };
            }

            case ')':
            {
                next(scanner);
                return Token{ .R_Paren, scanner.src[start : position(scanner).offset] };
            }

            case '{':
            {
                next(scanner);
                return Token{ .L_Brace, scanner.src[start : position(scanner).offset] };
            }

            case '}':
            {
                next(scanner);
                return Token{ .R_Brace, scanner.src[start : position(scanner).offset] };
            }

            case '[':
            {
                next(scanner);
                return Token{ .L_Bracket, scanner.src[start : position(scanner).offset] };
            }

            case ']':
            {
                next(scanner);
                return Token{ .R_Bracket, scanner.src[start : position(scanner).offset] };
            }

            case ';':
            {
                next(scanner);
                return Token{ .Semicolon, scanner.src[start : position(scanner).offset] };
            }

            case '0'..'9':
            {
                next(scanner);

                // Skip over prefix
                
                if c == '0'
                {
                    c_peek := peek(scanner);
                    if c_peek == 'x' || c_peek == 'X' || c_peek == 'b' || c_peek == 'B'
                    {
                        next(scanner);
                    }
                }

                has_decimal := false;

                LDigit:
                for
                {
                    c_peek := peek(scanner);

                    switch c_peek
                    {
                        // @Punt - Always scanning hex digits, regardless of prefix
                        
                        case '0'..'9', 'a'..'f', 'A'..'F', '\'': next(scanner);
                        case '.':
                        {
                            if !has_decimal
                            {
                                next(scanner);
                                has_decimal = true;
                            }
                            else
                            {
                                break LDigit;
                            }
                        }

                        case: break LDigit;
                    }
                }

                if has_decimal
                {
                    c_peek := peek(scanner);
                    if c_peek == 'f' || c_peek == 'F'
                    {
                        next(scanner);
                    }
                }
                else
                {
                    c_peek := peek(scanner);
                    if c_peek == 'u' || c_peek == 'U'
                    {
                        next(scanner);
                    }

                    c_peek = peek(scanner);
                    if c_peek == 'l' || c_peek == 'L'
                    {
                        next(scanner);

                        c_peek = peek(scanner);
                        if c_peek == 'l' || c_peek == 'L'
                        {
                            next(scanner);
                        }
                    }
                }

                return Token{ .Literal, scanner.src[start : position(scanner).offset] };
            }

            case ',':
            {
                next(scanner);
                return Token{ .Comma, scanner.src[start : position(scanner).offset] };
            }

            case '.':
            {
                next(scanner);
                return Token{ .Operator, scanner.src[start : position(scanner).offset] };
            }

            case '\'':
            {
                next(scanner);

                c_next := next(scanner);
                if c_next == '\\'
                {
                    next(scanner);
                }

                c_peek := peek(scanner);
                if c_peek == '\''
                {
                    next(scanner);
                    return Token{ .Literal, scanner.src[start : position(scanner).offset] };
                }
                else
                {
                    return Token{ .Error, scanner.src[start : position(scanner).offset] };    
                }
            }

            case:
            {
                return Token{ .Error, scanner.src[start : position(scanner).offset] };
            }
        }
    }
}

peek_token :: proc(scanner: ^scan.Scanner) -> Token
{
    copy := scanner^;
    return next_token(&copy);
}
