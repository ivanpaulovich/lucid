vim9script

# lucid#Run — call lucid and display results in popups
# Features: drill-down into groups, jump to file/line with Enter

var output_buf: string = ''
var current_explanation: dict<any> = {}
var summary_popup_id: number = 0
var stream_popup_id: number = 0
var stream_lines: list<string> = []

export def Run(level: string)
  output_buf = ''
  current_explanation = {}
  stream_lines = ['  lucid: analyzing diff...']

  # Show a streaming popup immediately so the user sees progress
  stream_popup_id = popup_create(stream_lines, {
    title: ' lucid ',
    pos: 'center',
    minwidth: 60,
    maxwidth: 80,
    maxheight: &lines - 4,
    border: [1, 1, 1, 1],
    borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
    padding: [0, 1, 0, 1],
    scrollbar: true,
    filter: function('StreamFilter'),
    mapping: false,
  })

  var cmd = ['sh', '-c', 'lucid --format json --level ' .. level]
  var opts = {
    out_cb: function('OutputCallback'),
    err_cb: function('StreamErrorCallback'),
    exit_cb: function('ExitCallback'),
  }

  job_start(cmd, opts)
enddef

def StreamFilter(winid: number, key: string): bool
  if key == 'q' || key == "\<Esc>"
    popup_close(winid)
    return true
  endif
  return false
enddef

def OutputCallback(channel: channel, msg: string)
  output_buf ..= msg .. "\n"
enddef

def StreamErrorCallback(channel: channel, msg: string)
  # Show stderr messages (like "lucid: explaining staged changes") in the stream popup
  if stream_popup_id > 0
    add(stream_lines, '  ' .. msg)
    popup_settext(stream_popup_id, stream_lines)
  endif
enddef

def ExitCallback(job: job, status: number)
  # Close the streaming popup
  if stream_popup_id > 0
    popup_close(stream_popup_id)
    stream_popup_id = 0
  endif

  if status != 0
    echohl ErrorMsg
    echomsg 'lucid: exited with status ' .. string(status)
    echohl None
    return
  endif

  try
    current_explanation = json_decode(output_buf)
  catch
    echohl ErrorMsg
    echomsg 'lucid: failed to parse output'
    echohl None
    return
  endtry

  ShowSummary()
enddef

def ShowSummary()
  var exp = current_explanation
  var lines: list<string> = []

  add(lines, '  lucid')
  add(lines, '  ' .. repeat('─', 50))
  add(lines, '')
  add(lines, '  Summary')
  add(lines, '  ' .. get(exp, 'summary', ''))
  add(lines, '')

  var stats = get(exp, 'stats', {})
  add(lines, printf('  %d files changed, +%d additions, -%d deletions',
    get(stats, 'files_changed', 0),
    get(stats, 'additions', 0),
    get(stats, 'deletions', 0)))
  add(lines, '  ' .. repeat('─', 50))
  add(lines, '')

  var groups: list<any> = get(exp, 'intent_groups', [])
  for i in range(len(groups))
    var g = groups[i]
    add(lines, printf('  [%d] %s  [%s risk]', i + 1,
      get(g, 'intent', ''), get(g, 'risk', 'low')))
    add(lines, '      ' .. get(g, 'description', ''))

    var files: list<any> = get(g, 'files', [])
    for f in files
      add(lines, '      * ' .. get(f, 'path', ''))
    endfor
    add(lines, '')
  endfor

  add(lines, '  1-9: drill into group  Enter: jump to file  q: close')

  var width = 64
  for line in lines
    if len(line) + 4 > width
      width = len(line) + 4
    endif
  endfor
  if width > &columns - 4
    width = &columns - 4
  endif

  summary_popup_id = popup_create(lines, {
    title: ' lucid ',
    pos: 'center',
    minwidth: width,
    maxwidth: width,
    maxheight: &lines - 4,
    border: [1, 1, 1, 1],
    borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
    padding: [0, 1, 0, 1],
    scrollbar: true,
    filter: function('SummaryFilter'),
    cursorline: true,
    mapping: false,
  })
enddef

def SummaryFilter(winid: number, key: string): bool
  if key == 'q' || key == "\<Esc>"
    popup_close(winid)
    return true
  endif

  # Drill into intent group
  if key =~ '^\d$'
    var idx = str2nr(key) - 1
    var groups: list<any> = get(current_explanation, 'intent_groups', [])
    if idx >= 0 && idx < len(groups)
      ShowGroup(groups[idx], idx)
    endif
    return true
  endif

  # Jump to file under cursor
  if key == "\<CR>"
    JumpToFileUnderCursor(winid)
    return true
  endif

  if key == 'j' || key == "\<Down>"
    win_execute(winid, 'normal! j')
    return true
  endif
  if key == 'k' || key == "\<Up>"
    win_execute(winid, 'normal! k')
    return true
  endif

  return false
enddef

def ShowGroup(group: dict<any>, idx: number)
  var lines: list<string> = []

  add(lines, printf('  [%d] %s  [%s risk]', idx + 1,
    get(group, 'intent', ''), get(group, 'risk', '')))
  add(lines, '  ' .. repeat('─', 50))
  add(lines, '')
  add(lines, '  ' .. get(group, 'description', ''))
  add(lines, '')

  var files: list<any> = get(group, 'files', [])
  for f in files
    add(lines, '  * ' .. get(f, 'path', ''))
    var summary = get(f, 'summary', '')
    if summary != ''
      add(lines, '    ' .. summary)
    endif

    var hunks: list<any> = get(f, 'hunks', [])
    for h in hunks
      add(lines, printf('    > L%d-%d: %s',
        get(h, 'start_line', 0),
        get(h, 'end_line', 0),
        get(h, 'annotation', '')))
    endfor
    add(lines, '')
  endfor

  add(lines, '  Enter: jump to file  q: back')

  var width = 64
  for line in lines
    if len(line) + 4 > width
      width = len(line) + 4
    endif
  endfor
  if width > &columns - 4
    width = &columns - 4
  endif

  popup_create(lines, {
    title: printf(' Group %d ', idx + 1),
    pos: 'center',
    minwidth: width,
    maxwidth: width,
    maxheight: &lines - 4,
    border: [1, 1, 1, 1],
    borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
    padding: [0, 1, 0, 1],
    scrollbar: true,
    filter: function('GroupFilter'),
    cursorline: true,
    mapping: false,
  })
enddef

def GroupFilter(winid: number, key: string): bool
  if key == 'q' || key == "\<Esc>"
    popup_close(winid)
    return true
  endif

  if key == "\<CR>"
    JumpToFileUnderCursor(winid)
    return true
  endif

  if key == 'j' || key == "\<Down>"
    win_execute(winid, 'normal! j')
    return true
  endif
  if key == 'k' || key == "\<Up>"
    win_execute(winid, 'normal! k')
    return true
  endif

  return false
enddef

# Extract file path from a "* path/to/file" line and jump to it
def JumpToFileUnderCursor(winid: number)
  var curline = ''
  win_execute(winid, 'curline = getline(".")')

  # Match lines like "  * path/to/file" or "      * path/to/file"
  var path = matchstr(curline, '\*\s\+\zs\S\+')
  if path == ''
    return
  endif

  # Extract line number if on a hunk annotation line "> L42-50: ..."
  var lnum = 0
  var hunk_line = matchstr(curline, '>\s\+L\zs\d\+')
  if hunk_line != ''
    lnum = str2nr(hunk_line)
  endif

  # Close all lucid popups
  popup_close(winid)
  if summary_popup_id > 0
    popup_close(summary_popup_id)
    summary_popup_id = 0
  endif

  # Open the file
  if filereadable(path)
    execute 'edit ' .. fnameescape(path)
    if lnum > 0
      execute 'normal! ' .. lnum .. 'G'
    endif
  else
    echohl WarningMsg
    echomsg 'lucid: file not found: ' .. path
    echohl None
  endif
enddef
