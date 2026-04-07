vim9script

# lucid.vim — Explain git diffs using AI
# Requires Vim 9.0+

if !has('vim9script') || v:version < 900
  finish
endif

if exists('g:loaded_lucid')
  finish
endif
g:loaded_lucid = 1

command! Lucid lucid#Run('default')
command! LucidSummary lucid#Run('summary')
command! LucidFull lucid#Run('full')

if !hasmapto('<Plug>(lucid-run)')
  nmap <leader>ll <Plug>(lucid-run)
  nmap <leader>ls <Plug>(lucid-summary)
  nmap <leader>lf <Plug>(lucid-full)
endif

nnoremap <silent> <Plug>(lucid-run) <ScriptCmd>lucid#Run('default')<CR>
nnoremap <silent> <Plug>(lucid-summary) <ScriptCmd>lucid#Run('summary')<CR>
nnoremap <silent> <Plug>(lucid-full) <ScriptCmd>lucid#Run('full')<CR>
