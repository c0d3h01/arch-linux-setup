Basic Navigation:
```
h, j, k, l     - Left, Down, Up, Right
w              - Jump to next word
b              - Jump back one word
gg             - Go to top of file
G              - Go to bottom of file
:number        - Go to line number
Ctrl+d         - Move half page down
Ctrl+u         - Move half page up
```

File Operations:
```
Space+e        - Toggle file explorer
Space+ff       - Find files (Telescope)
Space+fg       - Search in files (grep)
:w             - Save file
:q             - Quit
:wq            - Save and quit
:q!            - Quit without saving
```

Editing Commands:
```
i              - Enter insert mode before cursor
a              - Enter insert mode after cursor
A              - Enter insert mode at end of line
o              - Insert new line below and enter insert mode
O              - Insert new line above and enter insert mode
ESC or Ctrl+[  - Exit insert mode (return to normal mode)
```

Selection and Copy/Paste:
```
v              - Enter visual mode (for selecting text)
V              - Enter visual line mode
y              - Copy (yank) selection
d              - Cut selection
p              - Paste after cursor
P              - Paste before cursor
dd             - Delete/cut current line
yy             - Copy current line
```

Code Navigation:
```
gd             - Go to definition
gr             - Go to references
K              - Show documentation
Space+ff       - Find files
Space+fg       - Find text in files
Ctrl+o         - Go back to previous position
Ctrl+i         - Go forward
```

LSP Commands:
```
gD             - Go to declaration
gi             - Go to implementation
]d             - Next diagnostic
[d             - Previous diagnostic
gl             - Show diagnostic in floating window
:LSPInfo       - Show LSP status
```

Window Management:
```
:sp            - Split window horizontally
:vsp           - Split window vertically
Ctrl+w h       - Move to left window
Ctrl+w j       - Move to window below
Ctrl+w k       - Move to window above
Ctrl+w l       - Move to right window
Ctrl+w =       - Make all windows equal size
```

Search and Replace:
```
/pattern       - Search forward for pattern
?pattern       - Search backward for pattern
n              - Next search result
N              - Previous search result
:%s/old/new/g  - Replace 'old' with 'new' throughout file
```

Code Actions:
```
Space+ca       - Code action menu
gc             - Comment/uncomment (visual mode)
=              - Auto-indent selection
==             - Auto-indent line
```

File Explorer (NvimTree) Commands:
```
Space+e        - Toggle file explorer
a              - Create new file/directory
d              - Delete file/directory
r              - Rename file/directory
x              - Cut file/directory
c              - Copy file/directory
p              - Paste file/directory
```

Git Commands (if you have gitsigns):
```
]c             - Next git change
[c             - Previous git change
Space+hs       - Stage hunk
Space+hu       - Undo stage hunk
Space+hr       - Reset hunk
```

Telescope Commands:
```
Space+ff       - Find files
Space+fg       - Live grep (search in files)
Space+fb       - Browse buffers
Ctrl+c         - Close telescope
```

Auto-completion:
```
Ctrl+Space     - Trigger completion
Ctrl+n         - Next completion item
Ctrl+p         - Previous completion item
Tab           - Confirm completion
```

Common Command Mode Operations:
```
:PackerSync    - Update plugins
:checkhealth   - Check Neovim health
:Mason         - Open Mason (LSP installer)
:TSUpdate      - Update Treesitter parsers
```

Quick Tips:
1. Most commands can be preceded by a number to repeat them
2. Use `.` to repeat the last change
3. Use `u` to undo and `Ctrl+r` to redo
4. Use `ci"` to change text inside quotes
5. Use `%` to jump between matching brackets
