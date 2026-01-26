" === DEVGRU .vimrc – clean & pro ===

" Color and style
syntax on
set background=dark

" Visibility & comfort
set number             " numeracja linii
set cursorline         " highlight current line
set showcmd            " show (partial) commands
set showmode           " show mode (INSERT/REPLACE etc.)
set ruler              " show cursor position

" Tabs and indentation
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab          " use spaces instead of tabs
set autoindent
set smartindent
filetype plugin indent on

" Searching
set ignorecase
set smartcase
set incsearch
set hlsearch

" Clipboard (if you have +clipboard)
" set clipboard=unnamedplus

" Other
set scrolloff=5        " keep 5 lines visible around cursor
set wrap               " wrap long lines
set linebreak          " wrap at word boundaries
set wildmenu           " improved command-line completion
set nobackup
set nowritebackup
set noswapfile

" Editor-like keybindings
noremap <C-s> :w<CR>
noremap <C-q> :q<CR>
inoremap <C-s> <Esc>:w<CR>i
inoremap <C-q> <Esc>:q<CR>

" Status line
set laststatus=2
set statusline=%F%m%r%h%w\ [%{&ff}]\ [%Y]\ [line:%l/%L]\ [col:%c]

" Invisible characters (optional)
" set list listchars=tab:»·,trail:·,nbsp:␣

" Disable bells
set noerrorbells
set visualbell