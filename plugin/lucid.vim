vim9script

# lucid.vim — AI review layer for fugitive
# Requires Vim 9.0+ and vim-fugitive

if !has('vim9script') || v:version < 900
  finish
endif

if exists('g:loaded_lucid')
  finish
endif
g:loaded_lucid = 1

# plugin/lucid.vim -> plugin/ -> repo root -> lucid
var bin_path = expand('<script>:p:h:h') .. '/lucid'
if filereadable(bin_path)
  g:lucid_bin = bin_path
else
  g:lucid_bin = 'lucid'
endif

command! Lucid lucid#Start()
command! LucidExplain lucid#Explain('full')
command! -nargs=1 LucidPR lucid#ReviewPR(<q-args>)
command! LucidChat lucid#OpenChat()
command! LucidClear lucid#ClearContext()
command! LucidClearCache lucid#ClearCache()
command! LucidComments lucid#ListComments()
command! LucidSubmitReview lucid#SubmitReview()
command! LucidClearComments lucid#ClearComments()
command! LucidLog lucid#ShowLog()

# Fugitive integration
augroup lucid_fugitive
  autocmd!
  autocmd FileType fugitive lucid#SetupFugitive()
augroup END

if !hasmapto('<Plug>(lucid-explain)')
  nmap <leader>ll <Plug>(lucid-start)
  nmap <leader>le <Plug>(lucid-explain)
  nmap <leader>lc <Plug>(lucid-chat)
  nmap <leader>ln <Plug>(lucid-comment)
  xmap <leader>la <Plug>(lucid-add)
  xmap <leader>le <Plug>(lucid-visual-explain)
endif

nnoremap <silent> <Plug>(lucid-start) <ScriptCmd>lucid#Start()<CR>
nnoremap <silent> <Plug>(lucid-explain) <ScriptCmd>lucid#Explain('full')<CR>
nnoremap <silent> <Plug>(lucid-chat) <ScriptCmd>lucid#OpenChat()<CR>
nnoremap <silent> <Plug>(lucid-comment) <ScriptCmd>lucid#AddComment()<CR>
xnoremap <silent> <Plug>(lucid-add) <Esc><ScriptCmd>lucid#AddContext()<CR>
xnoremap <silent> <Plug>(lucid-visual-explain) <Esc><ScriptCmd>lucid#RunVisual()<CR>
