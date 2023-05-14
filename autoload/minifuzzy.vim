vim9script

import './utils.vim'
import './callbacks.vim'

# Globals used by filter
var search_string = ""
var output_list = []
var max_option_length = 0
var On_enter_callback: func(string): string
var On_ctrl_x_callback: func(string): string
var On_ctrl_v_callback: func(string): string
var On_cancel_callback: func
var Format_callback: func(string): string
var selection_index = 0
var scroll_offset = 0
var results_to_display = 0

# Character Code Strings
const bs_cc_str = "12825396" # Backspace

# Important character codes
const char_code = {
    enter: 13,
    ctrl_n: 14,
    ctrl_p: 16,
    ctrl_u: 21,
    ctrl_v: 22,
    ctrl_w: 23,
    ctrl_x: 24,
}

def FilterCallback(winid: number, key: string): bool
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

    final lines = []

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
    def KeyControlsSelection(): bool
        return key == "\<Up>" || key == "\<Down>" || key == "\<C-p>" || key == "\<C-n>"
    enddef

    # The search_string gets matched against Format_callback(output_list[i]),
    # not output_list[i]. However, once a value is selected, output_list[i] is
    # passed to the On_enter_callback as the argument.
    # For example, MinifuzzyLines sets output_list to the range(1, line("$")), but
    # the Format_callback is set to return the line contents at the line
    # number.

    # Select best match and exit close window
    # <CR>, <C-V>, <C-X>
    if key == "\<CR>" || key == "\<C-x>" || key == "\<C-v>" # <Enter>
        # No need to update display_matches, nothing will be displayed after
        # <CR> is pressed.
        UpdateMatches(search_string)
        popup_close(winid)
        if len(matches) > 0
            if key == "\<C-x>"
                On_ctrl_x_callback(matches[selection_index])
            elseif key == "\<C-v>"
                On_ctrl_v_callback(matches[selection_index])
            else
                On_enter_callback(matches[selection_index])
            endif
        endif
        return 1
    endif


    if KeyControlsSelection()
        # For arrow key presses, update the matches list first and then 
        # do stuff
        UpdateMatches(search_string)
        if key == "\<Up>" || key == "\<C-p>" # Arrow up
            UpdateMatches(search_string)
            selection_index = max([selection_index - 1, 0])
            if selection_index < scroll_offset
                scroll_offset -= 1
            endif
        elseif key == "\<Down>" || key == "\<C-n>" # Arrow down
            var len_count = search_string == "" ? len(output_list) : len(matches)
            selection_index = min([selection_index + 1, len_count - 1])
            if (selection_index + 1) > results_to_display
                scroll_offset += 1
            endif
        endif
    else
        # For everything else, do the stuff and then update the matches list
        if key == "\<C-u>" # <C-u> Clear whole line
            search_string = ""
        elseif key == "\<BS>" # <BS> Remove last letter
            search_string = substitute(search_string, ".$", "", "")
        else # any other key
            search_string ..= key
        endif
        selection_index = 0
        scroll_offset = 0
        UpdateMatches(search_string)
    endif

    # Update the buffer

    # Clear buffer
    for i in range(1, line("$", winid))
        setbufline(bufnr, i, "")
    endfor

    # Collect buffer lines
    lines->add($'> {search_string}')
    for m in display_matches[scroll_offset : ]
        lines->add(m)
    endfor

    # Fill the buffer
    for i in range(len(lines))
        setbufline(bufnr, i + 1, lines[i])
    endfor

    # Add the highlight line
    prop_add(selection_index + 2 - scroll_offset, 1, { 
        length: max_option_length, 
        type: 'match', 
        bufnr: bufnr 
    })

    return true
enddef

# Initialize a fuzzy find prompt.
# - "values" -> List of values to search against
const fuzzy_find_default_options = {
    format_cb: callbacks.DefaultFormatArg, # format_cb(val) is what gets displayed in the prompt
    exec_cb: callbacks.EditArg,            # <CR> callback, exec_cb(val) is executed
    ctrl_x_cb: callbacks.SplitArg,         # <C-X> Callback, ctrl_x_cb(val) is executed
    ctrl_v_cb: callbacks.VsplitArg,        # <C-V> Callback, ctrl_v_cb(val) is executed
    cancel_cb: callbacks.DefaultCancel,    # <Esc> Callback, cancel_cb() is executed
    title: 'Minifuzzy',                    # Title for the popup window
    filetype: '',                          # If non-empty, use filetype syntax highlight in window
    results_to_display: 20,                # Number of lines for showing values
}
export def InitFuzzyFind(values: list<string>, options: dict<any>)
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
    scroll_offset = 0
    results_to_display = opts.results_to_display

    # Create popup window
    const popup_opts = {
        filter: FilterCallback, 
        mapping: 0, 
        filtermode: 'a',
        minwidth: max_option_length,
        maxheight: results_to_display + 1,
        border: [],
        title: $' {opts.title} ',
    }
    const popup_id = popup_create(['> '] + output_list->mapnew((_, v) => Format_callback(v)), popup_opts)

    # Add syntax highlighting if requested
    const bufnr = winbufnr(popup_id)
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
