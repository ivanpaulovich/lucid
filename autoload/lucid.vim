vim9script

# lucid — AI review layer for fugitive
#
# In :Git buffer: e=explain file  x=mark reviewed ✓
# From anywhere:  :LucidExplain  :LucidSummary  :LucidChat

const EXPLAIN_BUF = '[lucid]'
const CHAT_BUF = '[lucid-chat]'
const SPINNER = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']

def Bin(): string
  return shellescape(g:lucid_bin)
enddef

var explain_bufnr: number = -1
var chat_bufnr: number = -1
var spinner_timer: number = -1
var spinner_idx: number = 0
var spinner_label: string = ''
var explain_stdout: string = ''
var explain_stderr: string = ''
var last_cmd: string = ''
var explain_context_path: string = ''
var reviewed_files: dict<bool> = {}
var context_items: list<dict<any>> = []
var review_comments: list<dict<any>> = []
var current_pr: string = ''
var status_text: string = ''

# --- Explain callbacks ---

def OnExplainStdout(ch: channel, msg: string)
  explain_stdout = explain_stdout .. msg .. "\n"
enddef

def OnExplainStderr(ch: channel, msg: string)
  explain_stderr = explain_stderr .. msg .. "\n"
enddef

def OnExplainExit(j: job, status: number)
  StopSpinner()
  try
    if status != 0
      SetBufContent(explain_bufnr, [
        'lucid: error (exit ' .. string(status) .. ')',
        ''] + split(explain_stderr, "\n") + ['', ':LucidLog for debug'])
      return
    endif
    try
      var exp = json_decode(explain_stdout)
      SetBufContent(explain_bufnr, RenderExplanation(exp))
    catch
      SetBufContent(explain_bufnr, split(explain_stdout, "\n"))
    endtry
  catch
    # Last resort — make sure spinner is stopped and show something
    echohl ErrorMsg
    echomsg 'lucid: render error — :LucidLog for details'
    echohl None
  endtry
enddef

# --- Public API ---

export def Start(target: string = '')
  silent! execute 'Git'
  if target != ''
    EnsureExplain()
    StartSpinner(target)
    var cmd = Bin() .. ' --format json ' .. shellescape(target) .. ' < /dev/null'
    FetchExplanation(cmd, target)
  else
    ExplainAll()
  endif
enddef

export def Explain(level: string)
  var path = expand('%:p:.')
  if path != ''
    ExplainFile(path, level)
  else
    ExplainAll()
  endif
enddef

export def ExplainOverview()
  ExplainAll()
enddef

export def ReviewPR(pr_number: string)
  current_pr = pr_number
  review_comments = []
  EnsureExplain()
  StartSpinner('PR #' .. pr_number)
  var cmd = Bin() .. ' --format json --pr ' .. shellescape(pr_number) .. ' < /dev/null'
  FetchExplanation(cmd, 'PR #' .. pr_number)
enddef

export def RunVisual()
  var filepath = expand('%:p:.')
  var lstart = line("'<")
  var lend = line("'>")
  var sel_lines = getline(lstart, lend)

  EnsureExplain()
  StartSpinner(fnamemodify(filepath, ':t'))

  var ctx_file = tempname()
  var ctx_lines: list<string> = []
  add(ctx_lines, '--- ' .. filepath .. ':' .. lstart .. '-' .. lend .. ' ---')
  ctx_lines += sel_lines
  writefile(ctx_lines, ctx_file)

  var cmd = Bin() .. ' --format json --level full'
  cmd = cmd .. ' --file ' .. shellescape(filepath)
  cmd = cmd .. ' --context-file ' .. shellescape(ctx_file)
  cmd = cmd .. ' < /dev/null'
  cmd = cmd .. '; rm -f ' .. shellescape(ctx_file)
  FetchExplanation(cmd, filepath)
enddef

# --- Explain ---

def ExplainAll()
  EnsureExplain()
  StartSpinner('overview')
  var cmd = Bin() .. ' --format json < /dev/null'
  FetchExplanation(cmd, '')
enddef

def ExplainFile(path: string, level: string)
  EnsureExplain()
  StartSpinner(fnamemodify(path, ':t'))
  var cmd = Bin() .. ' --format json --level ' .. level .. ' --file ' .. shellescape(path) .. ' < /dev/null'
  FetchExplanation(cmd, path)
enddef

def FetchExplanation(cmd: string, context_path: string)
  explain_stdout = ''
  explain_stderr = ''
  last_cmd = cmd
  explain_context_path = context_path
  UpdateExplainTitle(context_path)
  job_start(['sh', '-c', cmd], {
    out_cb: function('OnExplainStdout'),
    err_cb: function('OnExplainStderr'),
    exit_cb: function('OnExplainExit'),
  })
enddef

def EnsureExplain()
  var winid = FindBufWin(explain_bufnr)
  if winid > 0
    return
  endif

  if explain_bufnr > 0 && bufexists(explain_bufnr)
    execute 'botright sbuffer ' .. explain_bufnr
    return
  endif

  botright new
  explain_bufnr = bufnr()
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nomodifiable
  setlocal nonumber
  setlocal norelativenumber
  setlocal signcolumn=no
  nnoremap <buffer> <silent> q :close<CR>
  UpdateExplainTitle('')
enddef

def UpdateExplainTitle(context: string)
  var winid = FindBufWin(explain_bufnr)
  if winid <= 0
    return
  endif
  var title = 'lucid'
  if context != ''
    title = 'lucid: ' .. fnamemodify(context, ':t')
  endif
  win_execute(winid, 'silent! noautocmd file ' .. fnameescape('[' .. title .. ']'))
enddef

def RenderExplanation(exp: dict<any>): list<string>
  var lines: list<string> = []

  add(lines, 'Summary:')
  lines += WrapText(get(exp, 'summary', ''), '  ', 60)
  add(lines, '')

  var verdict = get(exp, 'verdict', '')
  if verdict != ''
    add(lines, 'Verdict:')
    lines += WrapText(verdict, '  ', 60)
    add(lines, '')
  endif

  var diagram = get(exp, 'diagram', '')
  if diagram != ''
    add(lines, 'Diagram:')
    for dline in split(diagram, '\n')
      add(lines, '  ' .. dline)
    endfor
    add(lines, '')
  endif

  var stats = get(exp, 'stats', {})
  add(lines, printf('%d files  +%d  -%d',
    get(stats, 'files_changed', 0),
    get(stats, 'additions', 0),
    get(stats, 'deletions', 0)))

  # Review order
  var review_order: list<any> = get(exp, 'review_order', [])
  if !empty(review_order)
    add(lines, '')
    add(lines, 'Review order:')
    for idx in range(len(review_order))
      add(lines, printf('  %d. %s', idx + 1, string(review_order[idx])))
    endfor
  endif

  add(lines, repeat('─', 60))

  # Intent groups
  var groups: list<any> = get(exp, 'intent_groups', [])
  for i in range(len(groups))
    var g = groups[i]
    add(lines, '')
    add(lines, printf('[%d] %s  (%s risk)', i + 1,
      get(g, 'intent', ''), get(g, 'risk', 'low')))
    add(lines, '')
    lines += WrapText(get(g, 'description', ''), '  ', 60)

    var files: list<any> = get(g, 'files', [])
    if !empty(files)
      add(lines, '')
      for f in files
        add(lines, '  ' .. string(get(f, 'path', '')))
        var raw_summary = get(f, 'summary', '')
        if type(raw_summary) == v:t_string && raw_summary != ''
          lines += WrapText(raw_summary, '    ', 60)
        elseif type(raw_summary) == v:t_list
          for bullet in raw_summary
            lines += WrapText(string(bullet), '    ', 60)
          endfor
        endif
        var hunks: list<any> = get(f, 'hunks', [])
        for h in hunks
          add(lines, printf('    L%d-%d: %s',
            get(h, 'start_line', 0),
            get(h, 'end_line', 0),
            string(get(h, 'annotation', ''))))
        endfor
      endfor
    endif
  endfor

  # Checklist
  var checklist: list<any> = get(exp, 'checklist', [])
  if !empty(checklist)
    add(lines, '')
    add(lines, repeat('─', 60))
    add(lines, '')
    add(lines, 'Checklist:')
    for item in checklist
      add(lines, '  [ ] ' .. string(item))
    endfor
  endif

  return lines
enddef

export def ClearCache()
  var cmd = Bin() .. ' --clear-cache'
  system(cmd)
  echomsg 'lucid: cache cleared'
enddef

# --- Context accumulation ---

export def AddContext()
  var filepath = expand('%:p:.')
  var lstart = line("'<")
  var lend = line("'>")
  var sel_lines = getline(lstart, lend)

  add(context_items, {
    file: filepath,
    lnum_start: lstart,
    lnum_end: lend,
    lines: sel_lines,
  })

  echomsg printf('lucid: added %s:%d-%d (%d selections)',
    fnamemodify(filepath, ':t'), lstart, lend, len(context_items))

  if FindBufWin(chat_bufnr) > 0
    RenderChat()
  endif
enddef

export def ClearContext()
  context_items = []
  echomsg 'lucid: context cleared'
  if FindBufWin(chat_bufnr) > 0
    RenderChat()
  endif
enddef

# --- Chat ---

export def OpenChat()
  EnsureChat()
  RenderChat()
enddef

def EnsureChat()
  var winid = FindBufWin(chat_bufnr)
  if winid > 0
    return
  endif

  if chat_bufnr > 0 && bufexists(chat_bufnr)
    execute 'botright sbuffer ' .. chat_bufnr
    return
  endif

  botright new
  silent! execute 'file ' .. CHAT_BUF
  chat_bufnr = bufnr()
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nonumber
  setlocal norelativenumber
  setlocal signcolumn=no

  nnoremap <buffer> <silent> q :close<CR>
  nnoremap <buffer> <silent> <CR> <ScriptCmd>SubmitChat()<CR>
enddef

def RenderChat()
  var winid = FindBufWin(chat_bufnr)
  if winid <= 0
    return
  endif

  var lines: list<string> = []
  add(lines, 'lucid chat')
  add(lines, repeat('━', 50))

  if empty(context_items)
    add(lines, '')
    add(lines, 'No context. Select code + \la to add.')
  else
    add(lines, '')
    add(lines, string(len(context_items)) .. ' selection(s):')
    for i in range(len(context_items))
      var item = context_items[i]
      add(lines, printf('  [%d] %s:%d-%d',
        i + 1, item.file, item.lnum_start, item.lnum_end))
    endfor
  endif

  add(lines, '')
  add(lines, repeat('─', 50))
  add(lines, '')

  var existing = getbufline(chat_bufnr, 1, '$')
  var history_start = -1
  for k in range(len(existing))
    if existing[k] =~ '^> '
      history_start = k
      break
    endif
  endfor

  if history_start >= 0
    lines += existing[history_start :]
  else
    add(lines, '> ')
  endif

  win_execute(winid, 'setlocal modifiable')
  win_execute(winid, 'silent :1,$delete _')
  setbufline(chat_bufnr, 1, lines)

  var prompt_line = len(lines)
  for k in range(len(lines) - 1, 0, -1)
    if lines[k] =~ '^> '
      prompt_line = k + 1
      break
    endif
  endfor
  win_execute(winid, 'normal! ' .. prompt_line .. 'G$')
enddef

def SubmitChat()
  var buf_lines = getbufline(chat_bufnr, 1, '$')
  var question = ''
  for k in range(len(buf_lines) - 1, 0, -1)
    if buf_lines[k] =~ '^> '
      question = substitute(buf_lines[k], '^> ', '', '')
      break
    endif
  endfor

  if question == '' || question =~ '^\s*$'
    return
  endif

  var ctx_file = tempname()
  var ctx_lines: list<string> = []
  for item in context_items
    add(ctx_lines, '--- ' .. item.file .. ':' .. item.lnum_start .. '-' .. item.lnum_end .. ' ---')
    ctx_lines += item.lines
    add(ctx_lines, '')
  endfor
  writefile(ctx_lines, ctx_file)

  var cmd = Bin() .. ' --format terminal --no-cache'
  if !empty(context_items)
    cmd = cmd .. ' --context-file ' .. shellescape(ctx_file)
  endif
  cmd = cmd .. ' --ask ' .. shellescape(question)
  cmd = cmd .. ' < /dev/null'
  cmd = cmd .. '; rm -f ' .. shellescape(ctx_file)

  var winid = FindBufWin(chat_bufnr)
  if winid > 0
    win_execute(winid, 'setlocal modifiable')
    appendbufline(chat_bufnr, '$', '')
    appendbufline(chat_bufnr, '$', SPINNER[0] .. '  thinking...')
    win_execute(winid, 'setlocal nomodifiable')
  endif

  last_cmd = cmd
  explain_stdout = ''
  explain_stderr = ''

  job_start(['sh', '-c', cmd], {
    out_cb: function('OnExplainStdout'),
    err_cb: function('OnExplainStderr'),
    exit_cb: function('OnChatExit'),
  })
enddef

def OnChatExit(j: job, status: number)
  var winid = FindBufWin(chat_bufnr)
  if winid <= 0
    return
  endif

  var buf_lines = getbufline(chat_bufnr, 1, '$')
  win_execute(winid, 'setlocal modifiable')
  for k in range(len(buf_lines) - 1, 0, -1)
    if buf_lines[k] =~ '^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]'
      deletebufline(chat_bufnr, k + 1)
      break
    endif
  endfor

  if status != 0
    appendbufline(chat_bufnr, '$', '')
    appendbufline(chat_bufnr, '$', 'Error (exit ' .. string(status) .. '):')
    for errline in split(explain_stderr, "\n")
      if errline != ''
        appendbufline(chat_bufnr, '$', '  ' .. errline)
      endif
    endfor
  else
    appendbufline(chat_bufnr, '$', '')
    for outline in split(explain_stdout, "\n")
      appendbufline(chat_bufnr, '$', outline)
    endfor
  endif

  appendbufline(chat_bufnr, '$', '')
  appendbufline(chat_bufnr, '$', '> ')
  win_execute(winid, 'setlocal nomodifiable')

  var last_line = len(getbufline(chat_bufnr, 1, '$'))
  win_execute(winid, 'normal! ' .. last_line .. 'G$')
enddef

# --- Fugitive integration ---

sign define lucid_reviewed text=✓ texthl=Comment

export def SetupFugitive()
  nnoremap <buffer> <silent> e <ScriptCmd>FugitiveExplain()<CR>
  nnoremap <buffer> <silent> x <ScriptCmd>FugitiveToggleReviewed()<CR>
  nnoremap <buffer> <silent> X <ScriptCmd>FugitiveToggleReviewed()<CR>
  FugitiveRefreshSigns()
enddef

def FugitiveGetPath(): string
  var curline = getline('.')
  var m = matchlist(curline, '^[MADRCU?]\{1,2\} \(.\+\)$')
  if !empty(m)
    return m[1]
  endif
  return ''
enddef

def FugitiveExplain()
  var path = FugitiveGetPath()
  if path == ''
    return
  endif
  ExplainFile(path, 'full')
enddef

def FugitiveToggleReviewed()
  var path = FugitiveGetPath()
  if path == ''
    return
  endif

  if get(reviewed_files, path, false)
    remove(reviewed_files, path)
  else
    reviewed_files[path] = true
  endif

  FugitiveRefreshSigns()

  var total = FugitiveCountFiles()
  var done = len(reviewed_files)
  var remaining = total - done
  if remaining == 0
    echomsg 'lucid: review complete ✓'
  else
    echomsg printf('lucid: %d/%d reviewed, %d remaining', done, total, remaining)
  endif
enddef

def FugitiveRefreshSigns()
  sign_unplace('lucid', {buffer: bufnr()})
  var buf_lines = getline(1, '$')
  for i in range(len(buf_lines))
    var m = matchlist(buf_lines[i], '^[MADRCU?]\{1,2\} \(.\+\)$')
    if !empty(m) && get(reviewed_files, m[1], false)
      sign_place(0, 'lucid', 'lucid_reviewed', bufnr(), {lnum: i + 1})
    endif
  endfor
enddef

def FugitiveCountFiles(): number
  var count = 0
  for line in getline(1, '$')
    if line =~ '^[MADRCU?]\{1,2\} '
      count += 1
    endif
  endfor
  return count
enddef

# --- Spinner ---

const TIPS = [
  'press e on any file in :Git to explain it',
  'press x in :Git to mark a file as reviewed',
  '\ln on a line to add a PR comment',
  '\la to add code to chat context, \lc to ask',
  ':LucidPR 42 to review a PR without checkout',
  '~/.config/lucid/prompt.txt to customize reviews',
  'lucid --ask "is this safe?" from the terminal',
  ':LucidClearCache if results seem stale',
]

# Moon phases animation — fits the Lunar theme
const MOON = [
  [
    '         .  *  .        ',
    '      .    🌑    .     ',
    '    *    new moon    *  ',
    '      .          .     ',
  ],
  [
    '         .  *  .        ',
    '      .    🌒    .     ',
    '   *  waxing crescent *',
    '      .          .     ',
  ],
  [
    '         .  *  .        ',
    '      .    🌓    .     ',
    '    * first quarter  *  ',
    '      .          .     ',
  ],
  [
    '         .  *  .        ',
    '      .    🌔    .     ',
    '    * waxing gibbous *  ',
    '      .          .     ',
  ],
  [
    '         .  *  .        ',
    '      .    🌕    .     ',
    '    *   full moon    *  ',
    '      .          .     ',
  ],
  [
    '         .  *  .        ',
    '      .    🌖    .     ',
    '    * waning gibbous *  ',
    '      .          .     ',
  ],
  [
    '         .  *  .        ',
    '      .    🌗    .     ',
    '    *  last quarter  *  ',
    '      .          .     ',
  ],
  [
    '         .  *  .        ',
    '      .    🌘    .     ',
    '   *  waning crescent *',
    '      .          .     ',
  ],
]

var spinner_start: list<number> = []

def StartSpinner(label: string)
  spinner_idx = 0
  spinner_label = label
  spinner_start = reltime()
  SetBufContent(explain_bufnr, ['', '  ' .. SPINNER[0] .. '  analyzing ' .. label .. '...'])
  StopSpinner()
  spinner_timer = timer_start(200, function('SpinnerTick'), {repeat: -1})
enddef

def SpinnerTick(timer_id: number)
  spinner_idx = (spinner_idx + 1) % len(SPINNER)
  if explain_bufnr < 0 || !bufexists(explain_bufnr)
    StopSpinner()
    return
  endif
  var winid = FindBufWin(explain_bufnr)
  if winid <= 0
    StopSpinner()
    return
  endif

  var elapsed = float2nr(reltimefloat(reltime(spinner_start)))
  var elapsed_str = elapsed < 60 ? string(elapsed) .. 's' : string(elapsed / 60) .. 'm ' .. string(elapsed % 60) .. 's'
  var tip_idx = (elapsed / 5) % len(TIPS)
  var moon_idx = (elapsed / 3) % len(MOON)

  # Update statusline
  status_text = SPINNER[spinner_idx] .. ' ' .. spinner_label .. ' ' .. elapsed_str

  var lines: list<string> = ['']
  lines += MOON[moon_idx]
  add(lines, '')
  add(lines, '  ' .. SPINNER[spinner_idx] .. '  analyzing ' .. spinner_label .. '...  ' .. elapsed_str)
  add(lines, '')
  add(lines, '  ' .. TIPS[tip_idx])

  win_execute(winid, 'setlocal modifiable')
  win_execute(winid, 'silent :1,$delete _')
  setbufline(explain_bufnr, 1, lines)
  win_execute(winid, 'setlocal nomodifiable')
enddef

def StopSpinner()
  if spinner_timer >= 0
    timer_stop(spinner_timer)
    spinner_timer = -1
  endif
  status_text = ''
enddef

# --- Log ---

export def Status(): string
  return status_text
enddef

export def ShowLog()
  EnsureExplain()
  var lines = ['lucid debug log', repeat('─', 40), '']
  add(lines, 'Command: ' .. last_cmd)
  add(lines, '')
  add(lines, 'Stderr:')
  lines += split(explain_stderr, "\n")
  add(lines, '')
  add(lines, 'Stdout (' .. string(len(explain_stdout)) .. ' bytes):')
  lines += split(explain_stdout[0 : 2000], "\n")
  SetBufContent(explain_bufnr, lines)
enddef

# --- Helpers ---

def FindBufWin(bnr: number): number
  if bnr < 0
    return 0
  endif
  for winid in win_findbuf(bnr)
    return winid
  endfor
  return 0
enddef

def SetBufContent(bnr: number, lines: list<string>)
  var winid = FindBufWin(bnr)
  if winid <= 0
    return
  endif
  win_execute(winid, 'setlocal modifiable')
  win_execute(winid, 'silent :1,$delete _')
  setbufline(bnr, 1, lines)
  win_execute(winid, 'setlocal nomodifiable')
  win_execute(winid, 'normal! gg')
enddef

def WrapText(text: string, indent: string, width: number): list<string>
  var lines: list<string> = []
  var words = split(text, '\s\+')
  var line = indent
  for word in words
    if len(line) + len(word) + 1 > width && line != indent
      add(lines, line)
      line = indent .. word
    else
      line = line .. (line == indent ? '' : ' ') .. word
    endif
  endfor
  if line != indent
    add(lines, line)
  endif
  return lines
enddef

# =========================================================================
# PR review comments
# =========================================================================

sign define lucid_comment text=💬 texthl=Comment

export def AddComment()
  var filepath = expand('%:p:.')
  var lnum = line('.')
  var body = input('Comment: ')
  if body == ''
    return
  endif

  add(review_comments, {
    path: filepath,
    line: lnum,
    body: body,
  })

  sign_place(0, 'lucid_comments', 'lucid_comment', bufnr(), {lnum: lnum})
  echomsg printf('lucid: comment added (%d total)', len(review_comments))
enddef

export def ListComments()
  if empty(review_comments)
    echomsg 'lucid: no comments'
    return
  endif

  EnsureExplain()
  var lines: list<string> = []
  var pr_label = current_pr != '' ? 'PR #' .. current_pr : 'review'
  add(lines, 'Comments for ' .. pr_label)
  add(lines, repeat('─', 50))
  add(lines, '')

  for i in range(len(review_comments))
    var c = review_comments[i]
    add(lines, printf('%d. %s:%d', i + 1, c.path, c.line))
    add(lines, '   ' .. c.body)
    add(lines, '')
  endfor

  add(lines, ':LucidSubmitReview to post to GitHub')
  SetBufContent(explain_bufnr, lines)
  UpdateExplainTitle('comments')
enddef

def OnSubmitExit(j: job, status: number)
  if status == 0
    echomsg 'lucid: review submitted'
    review_comments = []
    sign_unplace('lucid_comments')
  else
    echohl ErrorMsg
    echomsg 'lucid: failed to submit review (exit ' .. string(status) .. ')'
    echohl None
  endif
enddef

export def SubmitReview()
  if empty(review_comments)
    echomsg 'lucid: no comments to submit'
    return
  endif

  var pr = current_pr
  if pr == ''
    pr = input('PR number: ')
    if pr == ''
      return
    endif
  endif

  # Build gh pr review command with individual comments
  var tmpfile = tempname()
  var review_body = 'Review via lucid (' .. string(len(review_comments)) .. ' comments)'
  var cmd = 'gh pr review ' .. shellescape(pr) .. ' --comment'
  cmd = cmd .. ' --body ' .. shellescape(review_body)

  # Post each line comment via gh pr review --comment
  # gh api needs explicit owner/repo, so we use gh pr comment instead
  var cmds: list<string> = []
  for c in review_comments
    var line_comment = c.path .. ':' .. c.line .. ' — ' .. c.body
    var line_cmd = 'gh pr comment ' .. shellescape(pr)
    line_cmd = line_cmd .. ' --body ' .. shellescape(line_comment)
    add(cmds, line_cmd)
  endfor

  var full_cmd = cmd
  if !empty(cmds)
    full_cmd = full_cmd .. ' && ' .. join(cmds, ' && ')
  endif

  echomsg 'lucid: submitting ' .. string(len(review_comments)) .. ' comments to PR #' .. pr .. '...'

  job_start(['sh', '-c', full_cmd], {
    exit_cb: function('OnSubmitExit'),
  })
enddef

export def ClearComments()
  review_comments = []
  sign_unplace('lucid_comments')
  echomsg 'lucid: comments cleared'
enddef
