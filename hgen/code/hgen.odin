// TODO
// - Skip #if 0 blocks (HMM - what to do about #if SOME_THING_THAT_HGEN_DOESNT_KNOW_IF_ITS_TRUE_OR_FALSE)
// - Auto-generate constructors that just do a memberwise assignment? Could dump it in _generated.cpp
// misc notes
// - /**/ in front of #partial switch makes it so emacs doesn't wreck my indentation by auto-aligning #partial all they way to the left
//   (I guess emacs thinks it's a preprocessor directive?)

package main

import "core:os"
import "core:fmt"
import scan "core:text/scanner"
import "core:strings"
import "core:sort"

// Bump as necessary
MAX_FILES :: 512;

GENERATED_H_FILENAME :: "_generated.h";
GENERATED_CPP_FILENAME :: "_generated.cpp";

INCLUDE_SEARCH_ROOT : string; // set by command line args

is_illegal_target_dir :: proc(dir_: string) -> bool
{
    // @Hack - Simplest way to skip generating headers for external (dependency) files is to skip the
    //  "external/" directory wholesale. This check isn't very precise or configurable... but it works for now.
    
    ILLEGAL_TARGET_DIRS :: []string{ "external/", "common/", "shared/" };
    
    dir := ensure_trailing_slash_for_directory(dir_);

    for illegal in ILLEGAL_TARGET_DIRS
    {
        illegal_full := strings.concatenate([]string{ INCLUDE_SEARCH_ROOT, illegal });
        if strings.has_prefix(dir, illegal_full)
        {
            return true;
        }
    }

    return false;
}

ensure_trailing_slash_for_directory :: proc(dir: string) -> string
{
    result := dir;
    if !strings.has_suffix(dir, "/") && !strings.has_suffix(dir, "\\")
    {
        result = strings.concatenate([]string{dir, "/"});
    }
    
    return result;
}

canonicalize_dir_string :: proc(dir: string) -> string
{
    result := ensure_trailing_slash_for_directory(dir);
    result, _ = strings.replace_all(result, "\\", "/");
    return result;    
}

sort_file_infos :: proc(file_infos: ^[]os.File_Info)
{
    using sort;
    
    sort(Interface{
        collection = rawptr(file_infos),
        len = proc(it: Interface) -> int
        {
            collection := (^[]os.File_Info)(it.collection);
            return len(collection^);
        },
        less = compare_by_name_then_prefer_h_ext,
        swap = proc(it: Interface, i, j: int)
        {
            collection := (^[]os.File_Info)(it.collection);
            collection[i], collection[j] = collection[j], collection[i];
        },
    });

    sort(Interface{
        collection = rawptr(file_infos),
        len = proc(it: Interface) -> int
        {
            collection := (^[]os.File_Info)(it.collection);
            return len(collection^);
        },
        less = compare_by_name_then_prefer_h_ext,
        swap = proc(it: Interface, i, j: int)
        {
            collection := (^[]os.File_Info)(it.collection);
            collection[i], collection[j] = collection[j], collection[i];
        },
    });

    //---
    compare_by_name_then_prefer_h_ext :: proc(it: sort.Interface, i, j: int) -> bool
    {
        collection := (^[]os.File_Info)(it.collection);

        return collection[i].name < collection[j].name;

        // TODO - figure out why this isn't working. I legitimately think Odin's sort function
        //  is bugged, after like an hour of experimenting with this.
/*

        i_dot0 := strings.last_index_byte(collection[i].name, '.');
        i_dot1 := strings.last_index_byte(collection[j].name, '.');

        ext0 := "";
        name0 := collection[i].name;
        if i_dot0 != -1
        {
            ext0 = name0[i_dot0 + 1 : ];
            name0 = name0[ : i_dot0];
        }

        ext1 := "";
        name1 := collection[j].name;
        if i_dot1 != -1
        {
            ext1 = name1[i_dot1 + 1 : ];
            name1 = name1[ : i_dot1];
        }

        return (name0 < name1); // || (name0 == name1 && ext0 == "h" && ext1 != "h");
*/
    }
}

verify_or_panic :: proc(fact: bool, message: string, pos: scan.Position)
{
    // TODO - make the args here a varag?
    
    if !fact
    {
        // TODO - Report the location of the failed assert?
        // TODO - Report the cpp source file that had the issue?
        // TODO - Leave the existing generated.h file untouched if we exit via panic?
        
        line := pos.line;
        fmt.println("!!hgen exited with panic (", pos.line, "):", message);
        os.exit(1);
    }
}

Namespace :: struct
{
    name: string,
    cnt_brace_nested: int,
    is_inline: bool,
}

Enum :: struct
{
    name: string,
    type: string,
    is_enum_class: bool,
}

OutputFile :: struct
{
    handle: os.Handle,
    printed_rune_history: [2]rune,
    i_namespace_unopened: int, // NOTE - Namespaces that don't define anything we want to forward declare won't get printed

    dir: string,

    filename_current_input: string, // Doesn't include dir
    is_input_filename_printed: bool,
}

Parser :: struct
{
    namespace_stack: [dynamic]Namespace, // HMM - Should this be per output file? I think it might need to be... 
    
    cnt_brace_nested: int,
    cnt_paren_nested: int,
    cnt_bracket_nested: int,
}

Hgen :: struct
{
    gen_h: OutputFile,
    gen_cpp: OutputFile,

    scanner: scan.Scanner,
    parser: Parser,

    filename_current: string,
    is_current_file_cpp: bool, // else, .h
    
    dir_current: string,
    dirs_pending: map[string]bool,
    dirs_complete: map[string]bool,
}

push_namespace :: proc(using hgen: ^Hgen, namespace: Namespace)
{
    assert(namespace.cnt_brace_nested == 0);
    append(&parser.namespace_stack, namespace);
}

push_struct :: proc(using hgen: ^Hgen, name: string)
{
    ensure_innermost_namespace_opened(&gen_h, &parser.namespace_stack);
    write_string(&gen_h, "struct ");
    write_string(&gen_h, name);
    write_string(&gen_h, ";\n");
}

push_union :: proc(using hgen: ^Hgen, name: string)
{
    ensure_innermost_namespace_opened(&gen_h, &parser.namespace_stack);
    write_string(&gen_h, "union ");
    write_string(&gen_h, name);
    write_string(&gen_h, ";\n");
}

push_enum :: proc(using hgen: ^Hgen, enumeration: Enum)
{
    ensure_innermost_namespace_opened(&gen_h, &parser.namespace_stack);
    write_string(&gen_h, "enum ");
    if enumeration.is_enum_class
    {
        write_string(&gen_h, "class ");
    }
    write_string(&gen_h, enumeration.name);
    write_string(&gen_h, " : ");
    write_string(&gen_h, enumeration.type);
    write_string(&gen_h, ";\n");
}

push_func :: proc(using hgen: ^Hgen, header_raw: string)
{
    ensure_innermost_namespace_opened(&gen_cpp, &parser.namespace_stack);
    write_func_header_string(&gen_cpp, header_raw);
    write_string(&gen_cpp, ";\n");
}

/*
push_import_namespace :: proc(using hgen: ^Hgen, namespace: string, as: string)
{
    // NOTE - We only write these to _generated.cpp, because the only purpose these serve
    //  is to make omitted namespaces from function arguments work when we declare
    //  the same strings as forward declarations.
    
    ensure_innermost_namespace_opened(&gen_cpp, &parser.namespace_stack);
    
    if (len(as) > 0)
    {
        write_string(&gen_cpp, "ImportNamespaceAs(");
        write_string(&gen_cpp, namespace);
        write_string(&gen_cpp, ", ");
        write_string(&gen_cpp, as);
        write_string(&gen_cpp, ");\n");
    }
    else
    {
        write_string(&gen_cpp, "ImportNamespace(");
        write_string(&gen_cpp, namespace);
        write_string(&gen_cpp, ");\n");
    }
}
*/

push_l_brace :: proc(using hgen: ^Hgen)
{
    parser.cnt_brace_nested += 1;
    if len(parser.namespace_stack) > 0
    {
        parser.namespace_stack[len(parser.namespace_stack) - 1].cnt_brace_nested += 1;
    }
}

push_r_brace :: proc(using hgen: ^Hgen)
{
    parser.cnt_brace_nested -= 1;
    verify_or_panic(parser.cnt_brace_nested >= 0, "Extra '}'", scan.position(&scanner));

    if len(parser.namespace_stack) > 0
    {
        i_namespace := len(parser.namespace_stack) - 1;
        namespace_innermost := &parser.namespace_stack[i_namespace];
        
        namespace_innermost.cnt_brace_nested -= 1;
        verify_or_panic(namespace_innermost.cnt_brace_nested >= 0, "Extra '}'", scan.position(&scanner));

        if namespace_innermost.cnt_brace_nested == 0
        {
            close_namespace(&gen_h, namespace_innermost.name, i_namespace);
            close_namespace(&gen_cpp, namespace_innermost.name, i_namespace);
            pop(&parser.namespace_stack);

            //--
            
            close_namespace :: proc(using out: ^OutputFile, namespace_name: string, i_namespace: int)
            {
                was_opened := (i_namespace_unopened > i_namespace);
                if was_opened
                {
                    i_namespace_unopened -= 1;
                    ensure_blank_line(out);
                    write_string(out, "} // namespace ");
                    write_string(out, namespace_name);
                    ensure_blank_line(out);
                }
            }
        }
    }
}

ensure_blank_line :: proc(using out: ^OutputFile)
{
    if printed_rune_history[1] != '\n'
    {
        write_string(out, "\n\n");
    }
    else if printed_rune_history[0] != '\n'
    {
        write_string(out, "\n");
    }
}

write_string :: proc(using out: ^OutputFile, str: string)
{
    for c in str
    {
        // @Hack - Don't want these creeping in...
        if c == '\r'
        {
            continue;
        }

        printed_rune_history[0] = printed_rune_history[1];
        printed_rune_history[1] = c;

        os.write_rune(handle, c);
    }
}

write_func_header_string :: proc(using out: ^OutputFile, header_raw: string)
{
    prev_char_is_omitted_new_line := false;
    
    for c in header_raw
    {
        if c == '\r'
        {
            continue;
        }

        // Don't print indentation!
        if (c == ' ' || c == '\t') && prev_char_is_omitted_new_line
        {
            continue;
        }

        c_write := c;
        
        if c == '\n'
        {
            prev_char_is_omitted_new_line = true;

            if printed_rune_history[1] == '('
            {
                continue;
            }
            
            c_write = ' ';
        }
        else
        {
            prev_char_is_omitted_new_line = false;
        }

        // @Cleanup - We should only be doing this in one place...
        //  see 'write_string'
        
        printed_rune_history[0] = printed_rune_history[1];
        printed_rune_history[1] = c_write;
        
        os.write_rune(out.handle, c_write);
    }
}

write_namespace_opening :: proc(using out: ^OutputFile, namespace: Namespace)
{
    ensure_blank_line(out);

    if namespace.is_inline
    {
        write_string(out, "inline ");
    }
    
    write_string(out, "namespace ");
    write_string(out, namespace.name);
    write_string(out, "\n{");
    ensure_blank_line(out);
}

ensure_innermost_namespace_opened :: proc(using out: ^OutputFile, namespace_stack: ^[dynamic]Namespace)
{
    if !is_input_filename_printed
    {
        ensure_blank_line(out);
        write_string(out, "// ");
        write_string(out, filename_current_input);
        ensure_blank_line(out);
        
        is_input_filename_printed = true;
    }
    
    for ; i_namespace_unopened < len(namespace_stack); i_namespace_unopened += 1
    {
        namespace := namespace_stack[i_namespace_unopened];
        write_namespace_opening(out, namespace);
    }
}
                                       
main :: proc()
{
    verify_or_panic(len(os.args) > 2, "Please provide a target directory arg, and a search root directory", scan.Position{});

    dir_arg := canonicalize_dir_string(os.args[1]);
    INCLUDE_SEARCH_ROOT = canonicalize_dir_string(os.args[2]);
    
    fmt.println("hgen begin");
    
    {
        using hgen: Hgen;
        dirs_pending[dir_arg] = true;
        
        for len(dirs_pending) > 0
        {
            // Pull a directory out of the pending list
            
            // HMM - Better way to just get the first key out of a map?
            // NOTE - We don't care about ordering. Just care about moving everything from pending -> complete

            for dir_it, _ in dirs_pending
            {
                dir_current = dir_it;
                break;
            }

            assert(len(dir_current) > 0);
            assert(!(dir_current in dirs_complete));

            skipped_directory := false;
            
            if is_illegal_target_dir(dir_current)
            {
                fmt.print(" @ (skipping directory", dir_current);
                fmt.println("[blacklisted])");
                skipped_directory = true;
            }
            else
            {
                // Find all the input files in that directory
                
                dir_handle, ok := os.open(dir_current);
                if ok != 0
                {
                    fmt.print(" @ (skipping directory", dir_current);
                    fmt.println("[not found]");
                    skipped_directory = true;
                }
                else
                {
                    defer os.close(dir_handle);

                    file_infos: []os.File_Info;
                    file_infos, ok = os.read_dir(dir_handle, MAX_FILES);
                    assert(ok == 0);
                    defer delete(file_infos);
                    
                    sort_file_infos(&file_infos);
                    
                    fmt.println(" @", dir_current);

                    // Open our output files

                    {
                        output_h_str := strings.concatenate([]string{dir_current, GENERATED_H_FILENAME});
                        output_cpp_str := strings.concatenate([]string{dir_current, GENERATED_CPP_FILENAME});

                        open_output_file :: proc(out: ^OutputFile, full_filename: string, dir: string)
                        {
                            ok: os.Errno;
                            out.handle, ok = os.open(full_filename, os.O_WRONLY | os.O_CREATE | os.O_TRUNC);
                            assert(ok == 0);
                            out.printed_rune_history[0] = 0;
                            out.printed_rune_history[1] = 0;
                            out.is_input_filename_printed = false;
                            out.dir = dir;

                            write_string(out, "// NOTE - This file is auto-generated by hgen. DO NOT MODIFY!");
                            ensure_blank_line(out);
                        }

                        open_output_file(&gen_h, output_h_str, dir_current);
                        open_output_file(&gen_cpp, output_cpp_str, dir_current);
                    }
                    
                    // Visit each file in the directory
                    
                    for file_info in file_infos
                    {
                        // Make sure it's a user h/cpp file
                        
                        if file_info.name == GENERATED_H_FILENAME || file_info.name == GENERATED_CPP_FILENAME
                        {
                            continue;
                        }

                        is_h_file := strings.has_suffix(file_info.name, ".h");
                        is_cpp_file := strings.has_suffix(file_info.name, ".cpp");
                        if !is_h_file && !is_cpp_file
                        {
                            continue;
                        }

                        // Peek at the file (and maybe early-out)
                        
                        file, ok := os.read_entire_file(file_info.fullpath);
                        assert(ok);
                        defer delete(file);

                        scan.init(&scanner, string(file));

                        first_token := peek_token(&scanner);
                        if first_token.type == .Comment
                        {
                            // TODO - Make this more flexible about spacing?
                            if strings.has_prefix(first_token.lexeme, "// !SkipFile")
                            {
                                fmt.print("  (skipping", file_info.name);
                                fmt.println(")");
                                continue;
                            }
                        }
                        
                        verify_or_panic(parser.cnt_brace_nested == 0, "Previous file ended with unbalanced braces", scan.position(&scanner));
                        verify_or_panic(parser.cnt_bracket_nested == 0, "Previous file ended with unbalanced brackets", scan.position(&scanner));
                        verify_or_panic(parser.cnt_paren_nested == 0, "Previous file ended with unbalanced parens", scan.position(&scanner));

                        assert(len(parser.namespace_stack) == 0);
                        assert(gen_h.i_namespace_unopened == 0);
                        assert(gen_cpp.i_namespace_unopened == 0);

                        // Set input filename in various convenient places
                        
                        hgen.filename_current = file_info.name;
                        hgen.is_current_file_cpp = is_cpp_file;
                        gen_h.filename_current_input = file_info.name;
                        gen_h.is_input_filename_printed = false;
                        gen_cpp.filename_current_input = file_info.name;
                        gen_cpp.is_input_filename_printed = false;
                        
                        fmt.print("  ");
                        fmt.println(file_info.name);

                        // Parse the file (for real now)
                        
                        LTokens:
                        for
                        {
                            scan_past_comments(&scanner);

                            start := scan.position(&scanner);
                            
                            token := next_token(&scanner);

                            /**/#partial switch token.type
                            {
                                case .Eof: break LTokens;
                                case .Error:
                                {
                                    verify_or_panic(false, "Scan error", start);
                                }

                                case .Namespace:
                                {
                                    ident := next_token(&scanner);
                                    verify_or_panic(ident.type == .Identifier, "Expected identifier after 'namespace'", start);

                                    skip := false;
                                    if peek_token(&scanner).type == .Comment
                                    {
                                        comment := next_token(&scanner);

                                        // TODO - Make this more flexible about spacing
                                        skip = (comment.lexeme == "// !SkipNamespace");
                                    }

                                    if !skip
                                    {
                                        push_namespace(&hgen, Namespace{ ident.lexeme, 0, false });
                                    }
                                }

                                case .L_Brace:
                                {
                                    push_l_brace(&hgen);
                                }

                                case .R_Brace:
                                {
                                    push_r_brace(&hgen);
                                }

                                case .Enum:
                                {
                                    is_enum_class := false;
                                    
                                    ident := next_token(&scanner);
                                    if ident.type == .Class
                                    {
                                        is_enum_class = true;
                                        ident = next_token(&scanner);
                                    }
                                    
                                    verify_or_panic(ident.type == .Identifier, "Expected identifier after 'enum' (or 'enum class')", start);
                                    
                                    if peek_token(&scanner).type != .Colon
                                    {
                                        // Can't forward declare without explicit size
                                        
                                        continue;
                                    }

                                    next_token(&scanner);
                                    
                                    type := next_token(&scanner);
                                    verify_or_panic(type.type == .Identifier, "Expected identifier after ':'", start);
                                    
                                    push_enum(&hgen, Enum{ ident.lexeme, type.lexeme, is_enum_class });
                                }

                                case .Struct, .Union:
                                {
                                    // TODO - Handle nested structs, like I often use in unions.
                                    // Or more simply... just skip over the entire struct body by matching the { and }
                                    
                                    ident := peek_token(&scanner);
                                    if (ident.type == .Identifier)
                                    {
                                        next_token(&scanner);

                                        if (token.type == .Struct)
                                        {
                                            // TODO - parse through simple inheritance
                                            // TODO - if this was just a forward decl, don't generate another forward decl (although no harm in doing so)
                                            
                                            push_struct(&hgen, ident.lexeme);

                                            after_struct := peek_token(&scanner);
                                            if (after_struct.type == .Semicolon)
                                            {
                                                next_token(&scanner);
                                            }
                                            else if (after_struct.type == .L_Brace)
                                            {
                                                // Skip struct body
                                                // NOTE - This doesn't forward declare some stuff inside the struct, which is maybe bad...
                                                
                                                next_token(&scanner);                                                
                                                scan_past_in_current_context(&scanner, Token_Type.R_Brace);
                                            }
                                        }
                                        else
                                        {
                                            assert(token.type == .Union);
                                            push_union(&hgen, ident.lexeme);
                                        }
                                    }
                                    else
                                    {
                                        // Anonymous struct/union. Nothing we need to do.
                                    }
                                }

                                case .Class:
                                {
                                    verify_or_panic(false, "Unexpected 'class' ... use 'struct' instead", start); // NOTE - I only use structs
                                }

                                case .Preprocessor_Directive:
                                {
                                    // TODO - Guard generated forward declarations with the same preprocessor #if's that we find in the source?

                                    //
                                    if strings.has_prefix(token.lexeme, "#include")
                                    {
                                        i_quote_first := strings.index_byte(token.lexeme, '"');
                                        i_quote_last := strings.last_index_byte(token.lexeme, '"');

                                        if (i_quote_last > i_quote_first)
                                        {
                                            path := token.lexeme[i_quote_first + 1 : i_quote_last];
                                            verify_or_panic(strings.last_index_byte(path, '\\') == -1, "Unexpected '\\' in #include. Please use '/' instead.", start);
                                            
                                            i_last_slash := strings.last_index_byte(path, '/');
                                            if i_last_slash != -1
                                            {
                                                path = path[0 : i_last_slash + 1];

                                                path = strings.concatenate([]string{INCLUDE_SEARCH_ROOT, path});
                                                path = canonicalize_dir_string(path);

                                                if path in dirs_complete
                                                {
                                                    // Do nothing
                                                }
                                                else if path in dirs_pending
                                                {
                                                    // Do nothing
                                                }
                                                else
                                                {
                                                    dirs_pending[path] = true;
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                case .Internal, .Inline:
                                {
                                    allow_namespace :: true;
                                    parser_handle_function_keyword(&hgen, token, start, allow_namespace);
                                }

                                case .Using:
                                {
                                    // Skip over the namespace token so it doesn't mess us up!
                                    // @Hack - Probably want to handle this more properly

                                    if peek_token(&scanner).type == .Namespace
                                    {
                                        next_token(&scanner);
                                    }
                                }

                                /*
                                case .ImportNamespace, .ImportNamespaceAs:
                                {
                                    if len(parser.namespace_stack) == 0
                                    {
                                        // We definitely don't want to drop ImportNamespaces in the global _generated namespace.
                                        //  This case can happen if there is an ImportNamespace inside of a global function...
                                    }
                                    else if parser.namespace_stack[len(parser.namespace_stack) - 1].cnt_brace_nested != 1
                                    {
                                        // We only want to write ImportNamespace[As] if it is at the top level
                                        //  of a namespace (which is sometimes used to make arguments more readable).
                                        //  If it is nested inside a function/struct definition, we don't need to handle it.
                                    }
                                    else
                                    {
                                        namespace_cur := &parser.namespace_stack[len(parser.namespace_stack) - 1];
                                        if namespace_cur.cnt_brace_nested == 1
                                        {
                                            l_paren := next_token(&scanner);
                                            verify_or_panic(l_paren.type == .L_Paren, "Expected '(' after 'ImportNamespace[As]'", start);

                                            ident := next_token(&scanner);
                                            verify_or_panic(ident.type == .Identifier, "Expected identifier after '('", start);

                                            alias: Token;
                                            if token.type == .ImportNamespaceAs
                                            {
                                                comma := next_token(&scanner);
                                                verify_or_panic(comma.type == .Comma, "Expected ',' after identifier", start);

                                                alias = next_token(&scanner);
                                                verify_or_panic(alias.type == .Identifier, "Expected identifier after ','", start);
                                            }

                                            r_paren := next_token(&scanner);
                                            verify_or_panic(r_paren.type == .R_Paren, "Expected ')' after identifier", start);

                                            push_import_namespace(&hgen, ident.lexeme, alias.lexeme); // NOTE - alias is empty for ImportNamespace
                                        }
                                    }
                                }
                                */

                                case .Template:
                                {
                                    match := scan_until_token_set(&scanner, []Token_Type{ .Struct, .Internal, .Inline });

                                    /**/#partial switch match
                                    {
                                        case .Struct:
                                        {
                                            // TODO - Forward declare these?
                                            continue;
                                        }

                                        case .Internal: fallthrough;
                                        case .Inline:
                                        {
                                            allow_namespace :: false;
                                            parser_handle_function_keyword(&hgen, token, start, allow_namespace);
                                        }

                                        case: assert(false); fallthrough;
                                        case .Eof:
                                        {
                                            verify_or_panic(false, "Expected 'struct', 'internal', or 'inline' after 'template<...>'", start);
                                        }
                                    }
                                }

                                case .Typedef:
                                {
                                    scan_past_token(&scanner, .Semicolon);
                                    end := scan.position(&scanner);

                                    ensure_innermost_namespace_opened(&gen_h, &parser.namespace_stack);
                                    write_string(&gen_h, scanner.src[start.offset:end.offset]);
                                    write_string(&gen_h, "\n");
                                }
                            }
                        }

                        verify_or_panic(parser.cnt_brace_nested == 0, "File ended with unbalanced braces", scan.position(&scanner));
                        verify_or_panic(parser.cnt_bracket_nested == 0, "File ended with unbalanced brackets", scan.position(&scanner));
                        verify_or_panic(parser.cnt_paren_nested == 0, "File ended with unbalanced parens", scan.position(&scanner));
                    }
                }
            }

            // All done with this directory

            dirs_complete[dir_current] = true;
            delete_key(&dirs_pending, dir_current);

            if !skipped_directory
            {
                os.close(gen_h.handle);
                os.close(gen_cpp.handle);
            }
        }
    }

    fmt.println("hgen complete");
}

parser_handle_function_keyword :: proc(using hgen: ^Hgen, prev_token: Token, scanner_start: scan.Position, allow_namespace: bool)
{
    if prev_token.type == .Inline && allow_namespace && peek_token(&scanner).type == .Namespace
    {
        // inline namespace
        
        next_token(&scanner);
        
        ident := next_token(&scanner);
        verify_or_panic(ident.type == .Identifier, "Expected identifier after 'namespace'", scanner_start);

        push_namespace(hgen, Namespace{ ident.lexeme, 0, true });
    }
    else
    {
        // function

        using strings;
        
        builder := make_builder();
        defer destroy_builder(&builder);
        
        l_paren := scan_until_token(&scanner, .L_Paren);
        if l_paren != .L_Paren
        {
            assert(l_paren == .Eof);
            verify_or_panic(false, "Expected '(' at some point after 'internal' or 'inline'", scanner_start);
        }

        thru_func_name := scanner.src[scanner_start.offset : scan.position(&scanner).offset];

        next_token(&scanner);

        write_string(&builder, thru_func_name);
        write_string(&builder, "(");

        for
        {
            scan_past_comments(&scanner);
            arg_start := scan.position(&scanner).offset;

            // Write arg to header
            
            token_after_arg : Token;

            arg_written := false;

            for
            {
                scan_until_in_current_context(&scanner, []Token_Type{ .R_Paren, .Comma, .Identifier });
                token_after_arg = peek_token(&scanner);

                if token_after_arg.type == .Identifier
                {
                    if token_after_arg.lexeme == "OPTIONAL0"
                    {
                        // write type
                        consume_whitespace(&scanner);
                        write_string(&builder, scanner.src[arg_start : scan.position(&scanner).offset]);

                        next_token(&scanner);

                        verify_or_panic(next_token(&scanner).type == .L_Paren, "Expected '(' after OPTIONAL0", scanner_start);

                        name := next_token(&scanner);
                        verify_or_panic(name.type == .Identifier, "Expected identifier after OPTIONAL0", scanner_start);

                        // write name
                        write_string(&builder, name.lexeme);

                        verify_or_panic(next_token(&scanner).type == .R_Paren, "Expected ')' after identifier in OPTIONAL0", scanner_start);

                        // write value
                        write_string(&builder, "={}");

                        token_after_arg = peek_token(&scanner);
                        arg_written = true;
                    }
                    else if token_after_arg.lexeme == "OPTIONAL"
                    {
                        // write type
                        consume_whitespace(&scanner);
                        write_string(&builder, scanner.src[arg_start : scan.position(&scanner).offset]);

                        next_token(&scanner);

                        verify_or_panic(next_token(&scanner).type == .L_Paren, "Expected '('' after OPTIONAL0", scanner_start);

                        name := next_token(&scanner);
                        verify_or_panic(name.type == .Identifier, "Expected identifier after OPTIONAL0", scanner_start);

                        // write name
                        write_string(&builder, name.lexeme);

                        verify_or_panic(next_token(&scanner).type == .Comma, "Expected ','' after identifier in OPTIONAL", scanner_start);

                        consume_whitespace(&scanner);
                        default_value_start := scan.position(&scanner).offset;

                        // scan until macro close
                        scan_until_in_current_context(&scanner, []Token_Type{ .R_Paren });
                        verify_or_panic(peek_token(&scanner).type == .R_Paren, "Expected ')' to close OPTIONAL", scanner_start);

                        // write value
                        write_string(&builder, "=");
                        write_string(&builder, scanner.src[default_value_start : scan.position(&scanner).offset]);
                        arg_written = true;

                        // consume macro close
                        next_token(&scanner);

                        scan_until_in_current_context(&scanner, []Token_Type{ .R_Paren, .Comma });
                        token_after_arg = peek_token(&scanner);
                    }
                    else
                    {
                        // Identifier likely part of type. Keep going.
                        next_token(&scanner);
                        continue;
                    }
                }

                break;
            }

            verify_or_panic(token_after_arg.type != .Eof, "Unexpected end of file while parsing argument", scanner_start);

            if !arg_written
            {
                write_string(&builder, scanner.src[arg_start : scan.position(&scanner).offset]);
                arg_written = true;
            }

            // Advance past token after arg
            
            next_token(&scanner);

            if token_after_arg.type == .Comma
            {
                write_string(&builder, ", ");
            }
            else
            {
                assert(token_after_arg.type == .R_Paren);
                write_string(&builder, ")");
                break;  // Done writing function
            }
        }

        push_func(hgen, to_string(builder));
    }
}
