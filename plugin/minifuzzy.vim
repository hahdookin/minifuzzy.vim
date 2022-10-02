vim9script

import autoload "minifuzzy.vim"

command! MinifuzzyFind minifuzzy.Find()
command! MinifuzzyBuffers minifuzzy.Buffers()
command! MinifuzzyMRU minifuzzy.MRU()
command! MinifuzzyLines minifuzzy.Lines()

nnoremap <leader>ff <Cmd>MinifuzzyFind<CR>
nnoremap <C-p> <Cmd>MinifuzzyFind<CR>
nnoremap <leader>fb <Cmd>MinifuzzyBuffers<CR>
nnoremap <leader>fm <Cmd>MinifuzzyMRU<CR>
nnoremap <leader>fl <Cmd>MinifuzzyLines<CR>
