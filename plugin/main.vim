vim9script

const ignore_directories = [ 'node_modules', '.git' ]

# Builds a Unix find command that ignores directories present in the
# "ignore_directories" list
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
var On_enter_callback: func(string)


def FilterCallback(winid: number, key: string): bool
    if char2nr(key) == 128 # <BS> is constantly fed, seems like a bug
        return false
    endif
    if key == "\<Esc>"
        popup_close(winid)
        return true
    endif

    const bufnr = winbufnr(winid)
    var matches = []
    var lines = []

    def UpdatePopupBuffer()
        # Clear buffer
        for i in range(1, line("$", winid))
            setbufline(bufnr, i, "")
        endfor

        # Collect buffer lines
        lines->add(search_string)
        for m in matches
            lines->add(m)
        endfor

        # Fill the buffer
        for i in range(len(lines))
            call setbufline(bufnr, i + 1, lines[i])
        endfor
        prop_add(2, 1, { 
            length: max_option_length, 
            type: 'match', 
            bufnr: bufnr 
        })
    enddef

    # <CR>: Select best match and exit close window
    if char2nr(key) == 13 # <Enter>
        if search_string == ""
            matches = output_list
        else
            matches = matchfuzzy(output_list, search_string)
        endif
        if len(matches) > 0
            popup_close(winid)
            # execute use_arg_command .. " " .. matches[0]
            On_enter_callback(matches[0])
        else
            popup_close(winid)
        endif
        return 1
    endif

    if char2nr(key) == 16 # <C-p>
        # <C-p>: Clear current search query
        # Reset to empty state
        search_string = ""
        matches = output_list
    else
        # Any other key: Add to search query and re-match
        search_string ..= key
        matches = matchfuzzy(output_list, search_string)
    endif

    UpdatePopupBuffer()

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

# Initialize a fuzzy find prompt using "values" as options and "Exec_callback"
# as code to run with the option passed as the only argument
def InitFuzzyFind(values: list<string>, Exec_callback: func(string))
    # Skip on empty values, may be an issue with async
    if len(values) == 0
        return
    endif
    # Set globals...
    search_string = ""
    output_list = values
    On_enter_callback = Exec_callback
    max_option_length = max(output_list->mapnew((_, v) => len(v)))

    # Create popup window
    const popup_opts = {
        filter: FilterCallback, 
        mapping: 0, 
        filtermode: 'a',
        minwidth: max_option_length,
        maxheight: 20,
        border: [],
        title: ' ' .. getcwd()[strridx(getcwd(), '/') + 1 : ] .. '/ '
    }
    var popup_id = popup_create([""] + output_list, popup_opts)
    var bufnr = winbufnr(popup_id)
    prop_type_add('match', {
        bufnr: bufnr,
        highlight: 'Search',
    })
    prop_add(2, 1, { length: max_option_length, type: 'match', bufnr: bufnr })
enddef

const EditArg = (arg: string) =>  { 
    execute "edit " .. arg
}
const SplitArg = (arg: string) =>  { 
    execute "split " .. arg
}
const VsplitArg = (arg: string) =>  { 
    execute "vsplit " .. arg
}
command! FuzzyFind InitFuzzyFind(CommandOutputList(BuildFindCommand()), EditArg)
nnoremap <leader>ff <Cmd>FuzzyFind<CR>
nnoremap <C-p> <Cmd>FuzzyFind<CR>

command! FuzzyBuffers InitFuzzyFind(BuffersList(), EditArg)
nnoremap <leader>fb <Cmd>FuzzyBuffers<CR>

command! FuzzyMRU InitFuzzyFind(GetMRU(10), EditArg)
nnoremap <leader>fm <Cmd>FuzzyMRU<CR>

command! FuzzyLines InitFuzzyFind(CommandOutputList("cat " .. expand("%")), EditArg)
nnoremap <leader>fl <Cmd>FuzzyLines<CR>
