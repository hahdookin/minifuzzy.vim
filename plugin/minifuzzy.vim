vim9script

# Exec callbacks
const EditArg = (arg: string): string =>  execute("edit " .. arg)
const SplitArg = (arg: string): string =>  execute("split " .. arg)
const VsplitArg = (arg: string): string =>  execute("vsplit " .. arg )
const EchoArg = (arg: string): string =>  execute("echo " .. string(arg), "")
const GitCheckoutArg = (arg: string): string => execute("Git checkout " .. arg)
const GotoLineNumberArg = (arg: string): string => execute(":" .. arg)

# Format callbacks
const DefaultFormatArg = (arg: string): string => arg
const GetBufLineByNumber = (arg: string): string => repeat(" ", len(string(line('$'))) - len(arg)) .. arg .. " " .. (len(getbufline(bufname(), str2nr(arg))) > 0 ? getbufline(bufname(), str2nr(arg))[0] : "")


# Builds a Unix find command that ignores directories present in the
# "ignore_directories" list
const ignore_directories = [ 'node_modules', '.git' ]
def BuildFindCommand(): string
    var cmd_exprs = ignore_directories->mapnew((_, dir) => '-type d -name ' .. dir .. ' -prune')
    cmd_exprs->add('-type f -print')
    return 'find . ' .. cmd_exprs->join(' -o ')
enddef

# Globals used by filter
var search_string = ""
var output_list = []
var use_arg_command = ""
var max_option_length = 0
var On_enter_callback: func(string): string
var Format_callback: func(string): string
var selection_index = 0

# Character Code Strings
const bs_cc_str = "12825396" # Backspace
const up_cc_str = "128107117" # Arrow key up
const down_cc_str = "128107100" # Arrow key down

def FilterCallback(winid: number, key: string): bool
    const cc_str = key->mapnew((_, v) => string(char2nr(v)))
    if cc_str == bs_cc_str # <BS> is constantly fed, seems like a bug
        return false
    endif
    if key == "\<Esc>"
        popup_close(winid)
        return true
    endif

    const bufnr = winbufnr(winid)
    var matches = []
    var display_matches = []

    var lines = []

    # Helper functions
    # Updates the matches list and display matches based on the search_string
    def UpdateMatches(ss: string)
        if search_string == ""
            matches = output_list
            display_matches = output_list->mapnew((_, v) => Format_callback(v))
        else
            const both_matches = output_list->mapnew((_, v) => ({ a: v, b: Format_callback(v) })) # ALL in { a: value, b: format(value) }
            const matches_tuple = both_matches->matchfuzzy(search_string, { text_cb: (t) => t.b }) # Fuzzy matches of .b

            matches = matches_tuple->mapnew((_, v) => v.a)
            display_matches = matches_tuple->mapnew((_, v) => v.b)
        endif
    enddef

    # Determins if this key press is an arrow key
    def IsKeyArrow(): bool
        return cc_str == up_cc_str || cc_str == down_cc_str
    enddef

    def Clamp(x: number, low: number, high: number): number
        if x < low
            return low
        elseif x > high
            return high
        endif
        return x
    enddef

    # The search_string gets matched against Format_callback(output_list[i]),
    # not output_list[i]. However, once a value is selected, output_list[i] is
    # passed to the On_enter_callback as the argument.
    # For example, MinifuzzyLines sets output_list to the range(1, line("$")), but
    # the Format_callback is set to return the line contents at the line
    # number.

    # <CR>: Select best match and exit close window
    if char2nr(key) == 13 # <Enter>
        # No need to update display_matches, nothing will be displayed after
        # <CR> is pressed.
        UpdateMatches(search_string)
        popup_close(winid)
        if len(matches) > 0
            On_enter_callback(matches[selection_index])
        endif
        return 1
    endif


    if IsKeyArrow()
        # For arrow key presses, update the matches list first and then 
        # do stuff
        UpdateMatches(search_string)
        if cc_str == up_cc_str # Arrow up
            UpdateMatches(search_string)
            selection_index -= 1
            if selection_index < 0
                selection_index = 0
            endif
            # should_skip = true
        elseif cc_str == down_cc_str # Arrow down
            selection_index += 1
            var len_count = search_string == "" ? len(output_list) : len(matches)
            if selection_index >= len_count
                selection_index = len_count - 1
            endif
        endif
    else
        # For everything else, do the stuff and then update the matches list
        if char2nr(key) == 16 # <C-p>
            search_string = ""
        else # any other key
            search_string ..= key
        endif
        selection_index = 0
        UpdateMatches(search_string)
    endif

    #####################
    # UpdatePopupBuffer()
    #####################
    # Clear buffer
    for i in range(1, line("$", winid))
        setbufline(bufnr, i, "")
    endfor

    # Collect buffer lines
    lines->add(search_string)
    for m in display_matches
        lines->add(m)
    endfor

    # Fill the buffer
    for i in range(len(lines))
        setbufline(bufnr, i + 1, lines[i])
    endfor

    prop_add(selection_index + 2, 1, { 
        length: max_option_length, 
        type: 'match', 
        bufnr: bufnr 
    })

    return true
enddef

def CommandOutputList(command: string): list<string>
    return split(system(command), "\n")
enddef

# def CommandOutputList_Async(command: string)
#     job_start(command, {
#         out_cb: (ch: channel, msg: string) => {
#             output_list->add(msg)
#         }
#     })
# enddef

# def BuffersList(): list<any>
def BuffersList(): list<string>
    # return range(1, bufnr('$'))->filter((_, val) => buflisted(val))->map((_, v) => ({ nr: v, name: bufname(v) }))
    return range(1, bufnr('$'))->filter((_, val) => buflisted(val) && bufnr() != val)->map((_, v) => bufname(v) )
enddef

def GetMRU(limit: number): list<string>
    final recently_used: list<string> = []
    var found = 0
    for path in v:oldfiles
        if found >= limit
            break
        endif
        if match(path, "^/usr/share") < 0 && filereadable(expand(path))
            add(recently_used, path)
            found += 1
        endif 
    endfor
    return recently_used
enddef

# Returns just the cwd last directory name
# i.e. a/b/c => c
def GetCurrentDirectory(): string
    return getcwd()[strridx(getcwd(), '/') + 1 : ]
enddef

# Initialize a fuzzy find prompt.
# - "values" -> List of values to search against
# - "Exec_callback" -> Code to run when a value is selected. The argument is
#   a string which was the accepted value
# - "Format_callback" -> Code to run before a value is displayed in the list.
#   The argument is the value in the list "values"
const fuzzy_find_default_options = {
    exec_cb: EchoArg,
    format_cb: DefaultFormatArg,
}
def g:InitFuzzyFind(values: list<string>, options: dict<any>)
    # Skip on empty values, may be an issue with async
    if len(values) == 0
        return
    endif

    # Set globals...
    search_string = ""
    output_list = values
    On_enter_callback = options->has_key("exec_cb") ? options.exec_cb : fuzzy_find_default_options.exec_cb
    Format_callback = options->has_key("format_cb") ? options.format_cb : fuzzy_find_default_options.format_cb
    max_option_length = max(output_list->mapnew((_, v) => len(Format_callback(v))))
    selection_index = 0

    # Create popup window
    const popup_opts = {
        filter: FilterCallback, 
        mapping: 0, 
        filtermode: 'a',
        minwidth: max_option_length,
        maxheight: 20,
        border: [],
        title: ' ' .. GetCurrentDirectory() .. '/ '
    }
    var popup_id = popup_create([""] + output_list->mapnew((_, v) => Format_callback(v)), popup_opts)
    var bufnr = winbufnr(popup_id)
    prop_type_add('match', {
        bufnr: bufnr,
        highlight: 'Search',
    })
    prop_add(2, 1, { length: max_option_length, type: 'match', bufnr: bufnr })
enddef


command! MinifuzzyFind {
    g:InitFuzzyFind(CommandOutputList(BuildFindCommand()), {
        exec_cb: EditArg })
}
command! MinifuzzyBuffers {
    g:InitFuzzyFind(range(1, bufnr('$'))->filter((_, val) => buflisted(val) && bufnr() != val)->map((_, v) => string(v)), {
        format_cb: (s) => bufname(str2nr(s)), 
        exec_cb: (s) => execute("buffer " .. s) })
}
command! MinifuzzyMRU {
    g:InitFuzzyFind(GetMRU(10), {
        exec_cb: EditArg })
}
command! MinifuzzyLines {
    g:InitFuzzyFind(range(1, line('$'))->map((_, v) => string(v)), {
        exec_cb: GotoLineNumberArg, 
        format_cb: GetBufLineByNumber })
}
command! MinifuzzyGitBranch {
    g:InitFuzzyFind(CommandOutputList("git branch --format='%(refname:short)'"), {
        exec_cb: GitCheckoutArg })
}

nnoremap <leader>ff <Cmd>MinifuzzyFind<CR>
nnoremap <C-p> <Cmd>MinifuzzyFind<CR>
nnoremap <leader>fb <Cmd>MinifuzzyBuffers<CR>
nnoremap <leader>fm <Cmd>MinifuzzyMRU<CR>
nnoremap <leader>fl <Cmd>MinifuzzyLines<CR>
