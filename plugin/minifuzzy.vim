vim9script

import autoload "minifuzzy.vim"

command! MinifuzzyFind     minifuzzy.Find()
command! MinifuzzyBuffers  minifuzzy.Buffers()
command! MinifuzzyMRU      minifuzzy.MRU()
command! MinifuzzyLines    minifuzzy.Lines()
command! MinifuzzyGitFiles minifuzzy.GitFiles()
command! MinifuzzyCommand  minifuzzy.Command()
def g:StoreOldCmd(): string
    g:old_cmd_line = getcmdline()
    return ''
enddef

nnoremap <leader>ff <Cmd>MinifuzzyFind<CR>
nnoremap <C-p>      <Cmd>MinifuzzyFind<CR>
nnoremap <leader>fb <Cmd>MinifuzzyBuffers<CR>
nnoremap <leader>fm <Cmd>MinifuzzyMRU<CR>
nnoremap <leader>fl <Cmd>MinifuzzyLines<CR>
nnoremap <leader>fg <Cmd>MinifuzzyGitFiles<CR>

cnoremap <silent> <C-b>   <C-\>eg:StoreOldCmd()<CR><ESC>:MinifuzzyCommand<CR>
cnoremap <silent> <C-Tab> <C-\>eg:StoreOldCmd()<CR><ESC>:MinifuzzyCommand<CR>
