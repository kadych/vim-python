" vim: set sw=2 sts=2 ts=2 et :
"
if exists('g:loaded_python')
  finish
endif
let g:loaded_python = 1

let g:python_extension = 'py'

function! s:get_script_name()
  return expand('%:t:r')
endfunction

function! s:is_test(script_name)
  return a:script_name =~# '\vtest_[^\.]*$' || a:script_name =~# '\v_test$'
endfunction

function! s:find_window(file_path)
  for i in range(winnr('$'))
    if a:file_path ==# expand('#'.winbufnr(i + 1).':p')
      return i + 1
    endif
  endfor
  return -1
endfunction

function! s:expand_name(source_path, script_name, file_type)
  return expand(a:source_path.'/'.substitute(a:script_name, '\v\.', '/', 'g').'.'.a:file_type)
endfunction

function! s:is_readable(script_name, file_type)
  return filereadable(s:expand_name(expand('%:p:h'), a:script_name, a:file_type))
endfunction

function! s:upper_first(str)
  return toupper(a:str[0]).a:str[1:]
endfunction

function! s:open_script(script_name, file_type)
  let file_path = s:expand_name(expand('%:p:h'), a:script_name, a:file_type)
  if filereadable(file_path)
    let wnum = s:find_window(file_path)
    if wnum != -1
      execute wnum.'wincmd w'
    else
      execute 'edit! '.file_path
    endif
    return 1
  else
    let args = {}
    let source_script_name = substitute(a:script_name, '\v_?test_?', '', '')
    let args['class_name'] = s:upper_first(source_script_name)
    let args['func_name'] = source_script_name
    let args['test'] = s:is_test(a:script_name)
    if exists('g:user')
      let args['user'] = g:user
    endif
    call s:render_template_py(file_path, 'python.templ', args)
  endif
  return 0
endfunction

function! s:get_runtime_path()
  if has('win32')
    return expand('~/vimfiles')
  else
    return expand('~/.vim')
  endif
endfunction

function! s:set_script_path(script_path)
lua << EOF
  script_path = vim.eval('a:script_path')
  if string.find(package.path, script_path, 1, true) == nil then
    package.path = script_path..'?.lua;'..package.path
  end
EOF
endfunction

function! s:render_template_lua(file_path, template_name, args)
  let runtime_path = s:get_runtime_path()
  let template_path = expand(runtime_path.'/templates/')
  call s:set_script_path(expand(runtime_path.'/luascripts/'))
lua << EOF
  require 'lutem'
  template = lutem:new()
  ret, errmsg = template:load(vim.eval('a:template_name'), vim.eval('template_path'))
  if ret == 0 then
    result = template:render(vim.eval('a:args'))
    f = assert(io.open(vim.eval('a:file_path'), 'w'))
    f:write(result)
    f:close()
  else
    vim.command('echom "'..errmsg..'"')
  end
EOF
endfunction

function! s:render_template_py(file_path, template_name, args)
  let runtime_path = s:get_runtime_path()
  let template_path = expand(runtime_path.'/templates/')
  let params = extend({
        \  'runtime_path': runtime_path,
        \  'template_path': template_path,
        \  'template_name': a:template_name,
        \  'file_path': a:file_path,
        \}, a:args)
py << EOF
import vim
try:
  from jinja2 import Environment, FileSystemLoader
  params = vim.eval('params')
  env = Environment(loader=FileSystemLoader(params['template_path']),
                    trim_blocks=True)
  with open(params['file_path'], 'w') as f:
    f.write(env.get_template(params['template_name']).render(params))

  vim.command('execute ":edit! ' + params['file_path'].replace('\\', '\\\\') + '"')
except ImportError as e:
  vim.command('echom "' + e.message + '"')
EOF
endfunction

function! python#toggle()
  let script_name = s:get_script_name()
  if !s:is_test(script_name)
    let new_script_name = substitute(script_name, '$', '_test', '')
    if !s:is_readable(new_script_name, g:python_extension)
      let new_script_name = substitute(script_name, '\v([^\.]+)$', 'test_\1', '')
    endif
  else
    if script_name =~# '\v_test$'
      let new_script_name = substitute(script_name, '\v_test$', '', '')
    elseif script_name =~# '\vtest_[^\.]*$'
      let new_script_name = substitute(script_name, '\vtest_', '', '')
    endif
  endif
  call s:open_script(new_script_name, g:python_extension)
endfunction

function! python#run(...)
  let script_name = s:get_script_name()
  if !s:is_test(script_name)
    let cmd = 'python -m '.script_name.' '.join(a:000, ' ')
  else
    let cmd = 'python -m unittest -v '.script_name
    let merged = join(a:000, ' ')
    if !empty(merged)
      let cmd .= '.'.join(split(merged, ' '), ' '.script_name.'.')
    endif
  endif
  let output_name = 'output.txt'
  let output_idx = s:find_window(expand(getcwd().'/'.output_name))
  if output_idx == -1
    execute ':botright 10split '.output_name
  else
    execute output_idx.'wincmd w'
  endif
  normal Gdgg
  execute '0read! '.cmd
  execute ':write'
endfunction

function! python#format()
  " execute ':silent !python -m yapf -i %'
py << EOF
import vim
try:
  from yapf.yapflib import yapf_api
  yapf_api.FormatFile(vim.current.buffer.name, in_place=True)
  vim.command('execute ":edit!"')
except ImportError as e:
  vim.command('echom "' + e.message + '"')
EOF
endfunction

command! Ptoggle call python#toggle()
command! -nargs=* Prun call python#run(<q-args>)
command! Pformat call python#format()

augroup python
  autocmd FileType python nmap <buffer> <leader>jt :Ptoggle<cr>
  autocmd FileType python nmap <buffer> <leader>jr :Prun<cr>
  autocmd FileType python nmap <buffer> <leader>jf :Pformat<cr>
augroup END
