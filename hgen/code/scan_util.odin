package main

import scan "core:text/scanner"
import "core:strconv"

is_eof :: proc(scanner: ^scan.Scanner) -> bool
{
    using scan;
    
    return peek(scanner) == EOF;
}

@(private)
consume_until_or_past :: proc(scanner: ^scan.Scanner, set: []rune, should_pass: bool) -> string
{
    using scan;
    
    start: int = position(scanner).offset;
    length: int;
    
    for
    {
        c: rune = peek(scanner);
        if c == EOF
        {
            break;
        }

        delimiter_found := false;
        for delimiter in set
        {
            if c == delimiter
            {
                delimiter_found = true;
                break;
            }
        }

        if !delimiter_found || should_pass
        {
            next(scanner);
            length += 1;
        }

        if delimiter_found
        {
            break;
        }
    }

    return scanner.src[start: start + length];
}

consume_until_or_past_string :: proc(scanner: ^scan.Scanner, str: string, should_pass: bool) -> string
{
    using scan;

    if len(str) == 0
    {
        return "";
    }
    
    start: int = position(scanner).offset;
    length: int;
    
    for
    {
        c := peek(scanner);
        if c == EOF
        {
            break;
        }

        if str[0] == auto_cast c
        {
            saved := scanner^;
            lengthSaved := length;
            
            match := true;
            
            for cStr in str
            {
                cScan := next(scanner);
                length += 1;
                
                if cScan != cStr
                {
                    match = false;
                    break;
                }
            }

            if match
            {
                if !should_pass
                {
                    scanner^ = saved;
                    length = lengthSaved;
                }

                return scanner.src[start: start + length];
            }
            else
            {
                // @Slow - There are better string matching algorithms that use prefix tables, etc. That'd
                //  be overkill right now.
                
                scanner^ = saved;
                length = lengthSaved;
                next(scanner);
            }
        }
        else
        {
            next(scanner);
        }
    }

    return scanner.src[start: start + length];
}


consume_until_char_set :: proc(scanner: ^scan.Scanner, until_set: []rune) -> string
{
    return consume_until_or_past(scanner, until_set, false);
}

consume_until_char :: proc(scanner: ^scan.Scanner, until: rune) -> string
{
    return consume_until_or_past(scanner, []rune{until}, false);
}

consume_until_string :: proc(scanner: ^scan.Scanner, until: string) -> string
{
    return consume_until_or_past_string(scanner, until, false);
}

consume_past_char_set :: proc(scanner: ^scan.Scanner, past_set: []rune) -> string
{
    return consume_until_or_past(scanner, past_set, true);
}

consume_past_char :: proc(scanner: ^scan.Scanner, past: rune) -> string
{
    return consume_until_or_past(scanner, []rune{past}, true);
}

consume_past_string :: proc(scanner: ^scan.Scanner, past: string) -> string
{
    return consume_until_or_past_string(scanner, past, true);
}

consume_until :: proc{consume_until_char, consume_until_char_set, consume_until_string};
consume_past :: proc{consume_past_char, consume_past_char_set, consume_past_string};

try_consume :: proc(scanner: ^scan.Scanner, match: string) -> bool
{
    using scan;

    saved: Scanner = scanner^;

    for c in match
    {
        next_char := next(scanner);
        if next_char != c
        {
            scanner^ = saved;
            return false;
        }
    }

    return true;
}

consume_through_set :: proc(scanner: ^scan.Scanner, through_set: []rune) -> string
{
    using scan;
    
    start: int = position(scanner).offset;
    len: int;
    
    for
    {
        char_: rune = peek(scanner);
        if char_ == EOF
        {
            break;
        }

        match_found:= false;
        for match in through_set
        {
            if char_ == match
            {
                match_found = true;
                break;
            }
        }

        if !match_found
        {
            break;
        }

        next(scanner);
        len += 1;
    }

    return scanner.src[start : start + len];
}

consume_through_char :: proc(scanner: ^scan.Scanner, through: rune) -> string
{
    return consume_through_set(scanner, []rune{through});
}

consume_through :: proc{ consume_through_char, consume_through_set };

try_consume_int :: proc(scanner: ^scan.Scanner) -> (int, bool)
{
    using scan;
    using strconv;

    saved: Scanner = scanner^;

    valueStr := consume_through(scanner, []rune{'-', '+', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' }); // @Hack

    if value, ok := parse_int(valueStr); ok
    {
        return value, true;
    }

    scanner^ = saved;
    return ---, false;
}

try_consume_int64 :: proc(scanner: ^scan.Scanner) -> (i64, bool)
{
    using scan;
    using strconv;

    saved: Scanner = scanner^;

    valueStr := consume_through(scanner, []rune{'-', '+', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' }); // @Hack

    if value, ok := parse_i64(valueStr); ok
    {
        return value, true;
    }

    scanner^ = saved;
    return ---, false;
}

is_whitespace :: proc(r: rune) -> bool
{
    return r == '\t' || r == ' ' || r == '\n' || r == '\r';
}

consume_whitespace :: proc(scanner: ^scan.Scanner)
{
    using scan;

    for is_whitespace(peek(scanner))
    {
        next(scanner);
    }
}

consume_until_whitespace :: proc(scanner: ^scan.Scanner) -> string
{
    return consume_until(scanner, []rune{'\t', ' ', '\n', '\r' });
}

consume_until_new_line :: proc(scanner: ^scan.Scanner) -> string
{
    return consume_until(scanner, []rune{'\n', '\r'}); // NOTE - Assume \r is the start of a new line!
}

consume_past_new_line :: proc(scanner: ^scan.Scanner) -> string
{
    return consume_past(scanner, '\n');
}

reset_scanner :: proc(scanner: ^scan.Scanner)
{
    scan.init(scanner, scanner.src);
}
