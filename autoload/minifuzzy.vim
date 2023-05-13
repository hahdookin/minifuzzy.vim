vim9script

# Exec callbacks
const EditArg = (arg: string): string =>  execute("edit " .. arg)
const SplitArg = (arg: string): string =>  execute("split " .. arg)
const VsplitArg = (arg: string): string =>  execute("vsplit " .. arg )
const EchoArg = (arg: string): string =>  execute("echo " .. string(arg), "")
const GitCheckoutArg = (arg: string): string => execute("Git checkout " .. arg)
const GotoLineNumberArg = (arg: string): string => execute(":" .. arg)
const SplitLineNumberArg = (arg: string): string => execute("sp | :" .. arg .. " | norm zz")
const VsplitLineNumberArg = (arg: string): string => execute("vs | :" .. arg .. " | norm zz")

# Format callbacks
const DefaultFormatArg = (arg: string): string => arg
const GetBufLineByNumber = (arg: string): string => repeat(" ", len(string(line('$'))) - len(arg)) .. arg .. " " .. (len(getbufline(bufname(), str2nr(arg))) > 0 ? getbufline(bufname(), str2nr(arg))[0] : "")

# Cancel callbacks
const DefaultCancel = () => null

# Builds a Unix find command that ignores directories present in the
# "ignore_directories" list
const ignore_directories = [ 'node_modules', '.git' ]
def BuildFindCommand(directory: string): string
    if (executable('git') && isdirectory('./.git'))
        return "git ls-files -co --exclude-standard"
    endif
    var cmd_exprs = ignore_directories->mapnew((_, dir) => '-type d -name ' .. dir .. ' -prune')
    cmd_exprs->add('-type f -print')
    return $"find {fnameescape(expand(directory))} {cmd_exprs->join(' -o ')}"
enddef
# g:TestFindCommand = BuildFindCommand

# Globals used by filter
var search_string = ""
var output_list = []
var use_arg_command = ""
var max_option_length = 0
var On_enter_callback: func(string): string
var On_ctrl_x_callback: func(string): string
var On_ctrl_v_callback: func(string): string
var On_cancel_callback: func
var Format_callback: func(string): string
var selection_index = 0

# Character Code Strings
const bs_cc_str = "12825396" # Backspace
const up_cc_str = "128107117" # Arrow key up
const down_cc_str = "128107100" # Arrow key down

# Important character codes
const char_code = {
    ctrl_p: 16,
    ctrl_v: 22,
    ctrl_x: 24,
    enter: 13,
}

def FilterCallback(winid: number, key: string): bool
    var bs_pressed = len(key) == 3 && key[1] == 'k' && key[2] == 'b'
    const key_code = char2nr(key)
    const cc_str = key->mapnew((_, v) => string(char2nr(v)))
    if cc_str == bs_cc_str # <BS> is constantly fed, seems like a bug
        return false
    endif
    if key == "\<Esc>"
        popup_close(winid)
        On_cancel_callback()
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



    # Select best match and exit close window
    # <CR>, <C-V>, <C-X>
    if key_code == char_code.enter || key_code == char_code.ctrl_x || key_code == char_code.ctrl_v # <Enter>
        # No need to update display_matches, nothing will be displayed after
        # <CR> is pressed.
        UpdateMatches(search_string)
        popup_close(winid)
        if len(matches) > 0
            if key_code == char_code.ctrl_x
                On_ctrl_x_callback(matches[selection_index])
            elseif key_code == char_code.ctrl_v
                On_ctrl_v_callback(matches[selection_index])
            else
                On_enter_callback(matches[selection_index])
            endif
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
        if char2nr(key) == char_code.ctrl_p # <C-p> Clear whole line
            search_string = ""
        elseif bs_pressed # <BS> Remove last letter
            search_string = substitute(search_string, ".$", "", "")
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
const fuzzy_find_default_options = {
    exec_cb: EditArg,            # <CR> callback, exec_cb(val) is executed
    ctrl_x_cb: SplitArg,         # <C-X> Callback, ctrl_x_cb(val) is executed
    ctrl_v_cb: VsplitArg,        # <C-V> Callback, ctrl_v_cb(val) is executed
    cancel_cb: DefaultCancel,    # <Esc> Callback, cancel_cb() is executed
    format_cb: DefaultFormatArg, # format_cb(val) is what gets displayed in the prompt
    title: 'Minifuzzy',          # Title for the popup window
    filetype: '',                # If non-empty, use filetype syntax highlight in window
}
def g:InitFuzzyFind(values: list<string>, options: dict<any>)
    # Skip on empty values, may be an issue with async
    if len(values) == 0
        return
    endif

    # Object.assign(defaults, options)
    const opts = extendnew(fuzzy_find_default_options, options)

    # Set globals...
    search_string = ""
    output_list = values
    On_enter_callback = opts.exec_cb
    On_ctrl_x_callback = opts.ctrl_x_cb
    On_ctrl_v_callback = opts.ctrl_v_cb
    On_cancel_callback = opts.cancel_cb
    Format_callback = opts.format_cb
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
        # title: ' ' .. GetCurrentDirectory() .. '/ '
        title: ' ' .. opts.title .. ' ',
    }
    var popup_id = popup_create([""] + output_list->mapnew((_, v) => Format_callback(v)), popup_opts)

    # Add syntax highlighting if requested
    var bufnr = winbufnr(popup_id)
    if opts.filetype->len() > 0
        setbufvar(bufnr, '&filetype', opts.filetype)
    endif

    # Add highlight line text prop
    prop_type_add('match', {
        bufnr: bufnr,
        highlight: 'Search',
    })
    prop_add(2, 1, { length: max_option_length, type: 'match', bufnr: bufnr })
enddef

# Command functions
export def Find(directory = '.')
    g:InitFuzzyFind(systemlist(BuildFindCommand(directory)), { title: GetCurrentDirectory() .. '/' })
enddef

export def GitFiles()
    g:InitFuzzyFind(systemlist('git ls-files'), { title: "GIT: " .. GetCurrentDirectory() .. '/' })
enddef

export def Buffers()
    g:InitFuzzyFind(range(1, bufnr('$'))->filter((_, val) => buflisted(val) && bufnr() != val)->map((_, v) => string(v)), {
        format_cb: (s) => bufname(str2nr(s)), 
        exec_cb: (s) => execute("buffer " .. s),
        ctrl_x_cb: (s) => execute("sp | buffer " .. s),
        ctrl_v_cb: (s) => execute("vs | buffer " .. s),
        title: 'Buffers' })
enddef

export def MRU()
    g:InitFuzzyFind(GetMRU(10), { title: 'MRU' })
enddef

export def Lines()
    g:InitFuzzyFind(range(1, line('$'))->map((_, v) => string(v)), {
        exec_cb: GotoLineNumberArg, 
        ctrl_x_cb: SplitLineNumberArg,
        ctrl_v_cb: VsplitLineNumberArg,
        format_cb: GetBufLineByNumber,
        filetype: &filetype,
        title: 'Lines: ' .. expand("%") })
enddef

export def GitBranch()
    g:InitFuzzyFind(systemlist("git branch --format='%(refname:short)'"), {
        exec_cb: GitCheckoutArg })
enddef

g:old_cmd_line = ''
export def Command()
    const Exec_cb = (s: string): string => {
        var list = g:old_cmd_line->split(' ')
        if list->len() == 0
            list = ['']
        endif
        var last_index = g:old_cmd_line->len() - 1
        if g:old_cmd_line[last_index] == ' '
            list->add(s)
        else
            list[-1] = s
        endif
        echomsg $"[{g:old_cmd_line}]"
        var final_cmd = list->join(" ")
        feedkeys($":{final_cmd}")
        return ''
    }
    const Cancel_cb = () => {
        feedkeys($":{g:old_cmd_line}")
    }
    const values = getcompletion(g:old_cmd_line, 'cmdline')

    g:InitFuzzyFind(values->len() == 0 ? [''] : values, { 
        exec_cb: Exec_cb,
        cancel_cb: Cancel_cb,
        filetype: 'vim',
    })
enddef
