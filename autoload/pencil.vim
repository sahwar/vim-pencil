" ============================================================================
" File:        pencil.vim
" Description: autoload functions for vim-pencil plugin
" Maintainer:  Reed Esau <github.com/reedes>
" Created:     December 28, 2013
" License:     The MIT License (MIT)
" ============================================================================

if exists("autoloaded_pencil") | finish | endif
let autoloaded_pencil = 1

let s:WRAP_MODE_DEFAULT = -1
let s:WRAP_MODE_OFF     = 0
let s:WRAP_MODE_HARD    = 1
let s:WRAP_MODE_SOFT    = 2

" Wrap-mode detector
" Scan lines at end and beginning of file to determine the wrap mode.
" Modelines has priority over long lines found.
function! s:detect_wrap_mode() abort

  let b:max_textwidth = -1      " assume no relevant modeline
  call s:doModelines()

  if b:max_textwidth > 0
    " modelines(s) found with positive textwidth, so hard line breaks
    return s:WRAP_MODE_HARD
  endif

  if b:max_textwidth == 0 || g:pencil#wrapModeDefault ==# 'soft'
    " modeline(s) found only with zero textwidth, so it's soft line wrap
    " or, the user wants to default to soft line wrap
    return s:WRAP_MODE_SOFT
  endif

  " attempt to rule out soft line wrap
  " scan initial lines in an attempt to detect long lines
  for l:line in getline(1, g:pencil#softDetectSample)
    if len(l:line) > g:pencil#softDetectThreshold
      return s:WRAP_MODE_SOFT
    endif
  endfor

  " punt
  return s:WRAP_MODE_DEFAULT
endfunction

function! s:imap(preserve_completion, key, icmd)
  if a:preserve_completion
    execute ":inoremap <silent> <expr> " . a:key . " pumvisible() ? \"" . a:key . "\" : \"" . a:icmd . "\""
  else
    execute ":inoremap <silent> " . a:key . " " . a:icmd
  endif
endfunction

function! pencil#setAutoFormat(mode)
  " 1=auto, 0=manual, -1=toggle
  if !exists('b:last_autoformat')
    let b:last_autoformat = 0
  endif
  let b:last_autoformat = a:mode == -1 ? !b:last_autoformat : a:mode
  if b:last_autoformat
    augroup pencil_autoformat
      autocmd InsertEnter <buffer> set formatoptions+=a
      autocmd InsertLeave <buffer> set formatoptions-=a
    augroup END
  else
    silent! autocmd! pencil_autoformat * <buffer>
  endif
endfunction

" Create mappings for word processing
" args:
"   'wrap': 'detect|off|hard|soft|toggle'
function! pencil#init(...) abort
  let l:args = a:0 ? a:1 : {}

  if !exists('b:wrap_mode')
    let b:wrap_mode = s:WRAP_MODE_OFF
  endif
  if !exists("b:max_textwidth")
    let b:max_textwidth = -1
  endif

  " If user explicitly requested wrap_mode thru args, go with that.
  let l:wrap_arg = get(l:args, 'wrap', 'detect')

  if (b:wrap_mode && l:wrap_arg ==# 'toggle') ||
   \ l:wrap_arg =~# '^\(0\|off\|disable\|false\)$'
    let b:wrap_mode = s:WRAP_MODE_OFF
  elseif l:wrap_arg ==# 'hard'
    let b:wrap_mode = s:WRAP_MODE_HARD
  elseif l:wrap_arg ==# 'soft'
    let b:wrap_mode = s:WRAP_MODE_SOFT
  elseif l:wrap_arg ==# 'default'
    let b:wrap_mode = s:WRAP_MODE_DEFAULT
  else
    " this can return s:WRAP_MODE_ for soft, hard or default
    let b:wrap_mode = s:detect_wrap_mode()
  endif

  " translate default(-1) to soft(1) or hard(2) or off(0)
  if b:wrap_mode == s:WRAP_MODE_DEFAULT
    if g:pencil#wrapModeDefault =~# '^\(0\|off\|disable\|false\)$'
      let b:wrap_mode = s:WRAP_MODE_OFF
    elseif g:pencil#wrapModeDefault ==# 'soft'
      let b:wrap_mode = s:WRAP_MODE_SOFT
    else
      let b:wrap_mode = s:WRAP_MODE_HARD
    endif
  endif

  " autoformat is only used in Hard mode, and then only during
  " Insert mode
  call pencil#setAutoFormat(
        \ b:wrap_mode == s:WRAP_MODE_HARD &&
        \ get(l:args, 'autoformat', g:pencil#autoformat))

  if b:wrap_mode == s:WRAP_MODE_HARD
    if &modeline == 0 && b:max_textwidth > 0
      " Compensate for disabled modeline
      execute 'setlocal textwidth=' . b:max_textwidth
    elseif &textwidth == 0
      execute 'setlocal textwidth=' . g:pencil#textwidth
    else
      setlocal textwidth<
    endif
    setlocal nowrap
  elseif b:wrap_mode == s:WRAP_MODE_SOFT
    setlocal textwidth=0
    setlocal wrap
    setlocal linebreak
    setlocal colorcolumn=0      " doesn't align as expected
  else
    setlocal textwidth<
    setlocal wrap< nowrap<
    setlocal linebreak< nolinebreak<
    setlocal colorcolumn<
  endif

  " global settings
  if b:wrap_mode
    set display+=lastline
    set backspace=indent,eol,start
    if g:pencil#joinspaces
      set joinspaces         " two spaces after .!?
    else
      set nojoinspaces       " only one space after a .!? (default)
    endif
    "if b:wrap_mode == s:WRAP_MODE_SOFT
    "  " augment with additional chars
    "  " TODO not working yet with n and m-dash
    "  set breakat=\ !@*-+;:,./?([{
    "endif
  endif

  " because ve=onemore is relatively rare and could break
  " other plugins, restrict its presence to buffer
  " Better: restore ve to original setting
  if b:wrap_mode && g:pencil#cursorwrap
    set whichwrap+=<,>,b,s,h,l,[,]
    augroup pencil_cursorwrap
      autocmd BufEnter <buffer> set virtualedit+=onemore
      autocmd BufLeave <buffer> set virtualedit-=onemore
    augroup END
  else
    silent! autocmd! pencil_cursorwrap * <buffer>
  endif

  " window/buffer settings
  if b:wrap_mode
    setlocal nolist
    setlocal wrapmargin=0
    setlocal autoindent         " needed by formatoptions=n
    setlocal formatoptions+=n   " recognize numbered lists
    setlocal formatoptions+=1   " don't break line before 1 letter word
    setlocal formatoptions+=t   " autoformat of text
    setlocal formatoptions+=c   " autoformat of comments

    " clean out stuff we likely don't want
    setlocal formatoptions-=2   " use indent of 2nd line for rest of paragraph
    setlocal formatoptions-=v   " only break line at blank entered during insert
    setlocal formatoptions-=w   " avoid erratic behavior if mixed spaces
    setlocal formatoptions-=a   " autoformat will turn on with Insert in HardPencil mode
  else
    setlocal autoindent< noautoindent<
    setlocal list< nolist<
    setlocal wrapmargin<
    setlocal formatoptions<
  endif

  if b:wrap_mode == s:WRAP_MODE_SOFT
    nnoremap <buffer> <silent> $ g$
    nnoremap <buffer> <silent> 0 g0
    vnoremap <buffer> <silent> $ g$
    vnoremap <buffer> <silent> 0 g0
    noremap  <buffer> <silent> <Home> g<Home>
    noremap  <buffer> <silent> <End>  g<End>

    " preserve behavior of home/end keys in popups
    call s:imap(1, '<Home>', '<C-o>g<Home>')
    call s:imap(1, '<End>' , '<C-o>g<End>' )
  else
    silent! nunmap <buffer> $
    silent! nunmap <buffer> 0
    silent! vunmap <buffer> $
    silent! vunmap <buffer> 0
    silent! nunmap <buffer> <Home>
    silent! nunmap <buffer> <End>
    silent! iunmap <buffer> <Home>
    silent! iunmap <buffer> <End>
  endif

  if b:wrap_mode
    nnoremap <buffer> <silent> j gj
    nnoremap <buffer> <silent> k gk
    vnoremap <buffer> <silent> j gj
    vnoremap <buffer> <silent> k gk
    noremap  <buffer> <silent> <Up>   gk
    noremap  <buffer> <silent> <Down> gj

    " preserve behavior of up/down keys in popups
    call s:imap(1, '<Up>'  , '<C-o>g<Up>'  )
    call s:imap(1, '<Down>', '<C-o>g<Down>')
  else
    silent! nunmap <buffer> j
    silent! nunmap <buffer> k
    silent! vunmap <buffer> j
    silent! vunmap <buffer> k
    silent! unmap  <buffer> <Up>
    silent! unmap  <buffer> <Down>

    silent! iunmap <buffer> <Up>
    silent! iunmap <buffer> <Down>
  endif

  " set undo points around common punctuation,
  " line <c-u> and word <c-w> deletions
  if b:wrap_mode
    inoremap <buffer> . .<c-g>u
    inoremap <buffer> ! !<c-g>u
    inoremap <buffer> ? ?<c-g>u
    inoremap <buffer> , ,<c-g>u
    inoremap <buffer> ; ;<c-g>u
    inoremap <buffer> : :<c-g>u
    inoremap <buffer> <c-u> <c-g>u<c-u>
    inoremap <buffer> <c-w> <c-g>u<c-w>
  else
    silent! iunmap <buffer> .
    silent! iunmap <buffer> !
    silent! iunmap <buffer> ?
    silent! iunmap <buffer> ,
    silent! iunmap <buffer> ;
    silent! iunmap <buffer> :
    silent! iunmap <buffer> <c-u>
    silent! iunmap <buffer> <c-w>
  endif
endfunction

" attempt to find a non-zero textwidth, etc.
fun! s:doOne(item) abort
  let l:matches = matchlist(a:item, '^\([a-z]\+\)=\([a-zA-Z0-9_\-.]\+\)$')
  if len(l:matches) > 1
    if l:matches[1] =~ 'textwidth\|tw'
      let l:tw = str2nr(l:matches[2])
      if l:tw > b:max_textwidth
        let b:max_textwidth = l:tw
      endif
    endif
  endif
endfun

" attempt to find a non-zero textwidth, etc.
fun! s:doModeline(line) abort
  let l:matches = matchlist(a:line, '\%(\S\@<!\%(vi\|vim\([<>=]\?\)\([0-9]\+\)\?\)\|\sex\):\s*\%(set\s\+\)\?\([^:]\+\):\S\@!')
  if len(l:matches) > 0
    for l:item in split(l:matches[3])
      call s:doOne(l:item)
    endfor
  endif
  let l:matches = matchlist(a:line, '\%(\S\@<!\%(vi\|vim\([<>=]\?\)\([0-9]\+\)\?\)\|\sex\):\(.\+\)')
  if len(l:matches) > 0
    for l:item in split(l:matches[3], '[ \t:]')
      call s:doOne(l:item)
    endfor
  endif
endfun

" sample lines for detection, capturing both
" modeline(s) and max line length
" Hat tip to https://github.com/ciaranm/securemodelines
fun! s:doModelines() abort
  if line("$") > &modelines
    let l:lines={ }
    call map(filter(getline(1, &modelines) +
          \ getline(line("$") - &modelines, "$"),
          \ 'v:val =~ ":"'), 'extend(l:lines, { v:val : 0 } )')
    for l:line in keys(l:lines)
      call s:doModeline(l:line)
    endfor
  else
    for l:line in getline(1, "$")
      call s:doModeline(l:line)
    endfor
  endif
endfun

" vim:ts=2:sw=2:sts=2
